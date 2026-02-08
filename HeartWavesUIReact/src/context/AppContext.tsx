import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from 'react'
import type {
  SessionData,
  Screening,
  Symptoms,
  ImportedData,
  HealthSummary,
  DailyMetric,
  GeminiScreeningResult,
  SurveyAssessment,
} from '../types/health'
import {
  uploadAppleHealth,
  saveAnswers,
  callGeminiBrowser,
  persistLlm,
  type UploadOptions,
} from '../api'

// ---- Build HealthSummary from backend imported data ----

function meanOf(nums: (number | null)[]): number | null {
  const xs = nums.filter((x): x is number => x != null && Number.isFinite(x))
  if (!xs.length) return null
  return xs.reduce((a, b) => a + b, 0) / xs.length
}

export function buildHealthSummary(imported: ImportedData): HealthSummary {
  const daily = imported.daily ?? []
  const last30 = daily.slice(-30)

  const toDailyMetric = (
    records: typeof daily,
    accessor: (d: (typeof daily)[0]) => number | null,
    unit: string
  ): DailyMetric[] =>
    records.map((d) => ({
      date: d.date,
      value: accessor(d) ?? 0,
      unit,
    }))

  return {
    restingHeartRate: {
      mean: meanOf(last30.map((d) => d.resting_hr_mean)),
      unit: 'bpm',
      last7Days: toDailyMetric(daily.slice(-7), (d) => d.resting_hr_mean, 'bpm'),
    },
    heartRateVariability: {
      meanMs: meanOf(last30.map((d) => d.hrv_sdnn_mean)),
      unit: 'ms',
      last7Days: toDailyMetric(daily.slice(-7), (d) => d.hrv_sdnn_mean, 'ms'),
    },
    standMinutes: {
      mean: meanOf(last30.map((d) => d.stand_minutes)),
      unit: 'min',
      last7Days: toDailyMetric(daily.slice(-7), (d) => d.stand_minutes, 'min'),
    },
    activeMinutes: {
      mean: meanOf(last30.map((d) => d.active_minutes)),
      unit: 'min',
      last7Days: toDailyMetric(daily.slice(-7), (d) => d.active_minutes, 'min'),
    },
    lastUpdated: new Date().toISOString(),
  }
}

// ---- Reconcile screening profile (mirrors server.rb logic) ----

function reconcileScreeningProfile(screening: Screening) {
  if (screening.status === 'normal') {
    screening.phenotype_hint = 'normal'
    screening.phenotype_confidence = 'high'
    screening.phenotype_reason =
      screening.phenotype_reason || 'No strong follow-up pattern in this window.'
  } else if (
    !screening.phenotype_hint ||
    screening.phenotype_hint === 'normal'
  ) {
    screening.phenotype_hint = 'unspecified_autonomic'
    if (!screening.phenotype_confidence) screening.phenotype_confidence = 'low'
  }
}

function applyLlmToScreening(screening: Screening, llm: GeminiScreeningResult) {
  screening.llm = llm
  if (llm.status === 'normal' || llm.status === 'needs_followup') {
    screening.status = llm.status as Screening['status']
  }
  if (Array.isArray(llm.signals) && llm.signals.length) {
    screening.signals = llm.signals as Screening['signals']
  }
  if (Array.isArray(llm.questionnaire) && llm.questionnaire.length) {
    screening.questionnaire = llm.questionnaire
  }
  if (Array.isArray(llm.safety_notes) && llm.safety_notes.length) {
    screening.safety_notes = llm.safety_notes
  }
  reconcileScreeningProfile(screening)
}

// ---- Context shape ----

interface AppContextValue {
  // State
  sessionId: string
  imported: ImportedData | null
  screening: Screening | null
  symptoms: Symptoms | null
  healthSummary: HealthSummary | null
  surveyAssessment: SurveyAssessment | null

  // Loading / error states
  uploading: boolean
  uploadError: string
  savingAnswers: boolean
  answersError: string
  geminiRunning: boolean
  geminiError: string
  geminiEnabled: boolean

  // Actions
  doUpload: (opts: UploadOptions, geminiKey?: string, geminiModel?: string) => Promise<void>
  doSaveAnswers: (answers: Record<string, string>) => Promise<void>
  doReset: () => void
  setGeminiEnabled: (v: boolean) => void
}

const AppContext = createContext<AppContextValue | null>(null)

export function AppProvider({ children }: { children: ReactNode }) {
  const [sessionId, setSessionId] = useState('')
  const [imported, setImported] = useState<ImportedData | null>(null)
  const [screening, setScreening] = useState<Screening | null>(null)
  const [symptoms, setSymptoms] = useState<Symptoms | null>(null)
  const [healthSummary, setHealthSummary] = useState<HealthSummary | null>(null)
  const [surveyAssessment, setSurveyAssessment] = useState<SurveyAssessment | null>(null)

  const [uploading, setUploading] = useState(false)
  const [uploadError, setUploadError] = useState('')
  const [savingAnswers, setSavingAnswers] = useState(false)
  const [answersError, setAnswersError] = useState('')
  const [geminiRunning, setGeminiRunning] = useState(false)
  const [geminiError, setGeminiError] = useState('')
  const [geminiEnabled, setGeminiEnabled] = useState(false)

  const applySession = useCallback((data: SessionData) => {
    reconcileScreeningProfile(data.screening)
    setSessionId(data.session_id)
    setImported(data.imported)
    setScreening({ ...data.screening })
    setSymptoms(data.symptoms)
    setHealthSummary(buildHealthSummary(data.imported))
    setSurveyAssessment(data.screening.survey_assessment ?? null)
  }, [])

  const doUpload = useCallback(
    async (opts: UploadOptions, geminiKey?: string, geminiModel?: string) => {
      setUploading(true)
      setUploadError('')
      setGeminiError('')
      try {
        const data = await uploadAppleHealth(opts)
        applySession(data)

        // Browser-side Gemini if enabled
        if (geminiEnabled && geminiKey) {
          setGeminiRunning(true)
          try {
            const llm = await callGeminiBrowser(
              data.imported,
              data.screening,
              geminiKey,
              geminiModel || 'gemini-2.5-flash'
            )
            applyLlmToScreening(data.screening, llm)
            setScreening({ ...data.screening })
            setHealthSummary(buildHealthSummary(data.imported))
            await persistLlm(data.session_id, llm)
          } catch (e) {
            setGeminiError(e instanceof Error ? e.message : 'Gemini call failed')
          } finally {
            setGeminiRunning(false)
          }
        }
      } catch (e) {
        const raw = e instanceof Error ? e.message : 'Upload failed'
        const friendly =
          /Load failed|Failed to fetch|NetworkError|aborted/i.test(raw)
            ? 'Cannot reach backend right now. Start `ruby server.rb` and reload this page.'
            : raw
        setUploadError(friendly)
      } finally {
        setUploading(false)
      }
    },
    [geminiEnabled, applySession]
  )

  const doSaveAnswers = useCallback(
    async (answers: Record<string, string>) => {
      if (!sessionId) {
        setAnswersError('Upload data first.')
        return
      }
      setSavingAnswers(true)
      setAnswersError('')
      try {
        const data = await saveAnswers(sessionId, answers)
        setScreening({ ...data.screening })
        setSymptoms(data.symptoms)
        setSurveyAssessment(data.survey_assessment)
      } catch (e) {
        setAnswersError(e instanceof Error ? e.message : 'Save failed')
      } finally {
        setSavingAnswers(false)
      }
    },
    [sessionId]
  )

  const doReset = useCallback(() => {
    setSessionId('')
    setImported(null)
    setScreening(null)
    setSymptoms(null)
    setHealthSummary(null)
    setSurveyAssessment(null)
    setUploadError('')
    setAnswersError('')
    setGeminiError('')
  }, [])

  const value: AppContextValue = {
    sessionId,
    imported,
    screening,
    symptoms,
    healthSummary,
    surveyAssessment,
    uploading,
    uploadError,
    savingAnswers,
    answersError,
    geminiRunning,
    geminiError,
    geminiEnabled,
    doUpload,
    doSaveAnswers,
    doReset,
    setGeminiEnabled,
  }

  return <AppContext.Provider value={value}>{children}</AppContext.Provider>
}

export function useApp() {
  const ctx = useContext(AppContext)
  if (!ctx) throw new Error('useApp must be used within AppProvider')
  return ctx
}
