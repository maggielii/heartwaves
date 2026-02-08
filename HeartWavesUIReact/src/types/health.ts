// ---- Backend response types (matching server.rb JSON shapes) ----

export interface DailyRecord {
  date: string
  resting_hr_mean: number | null
  hrv_sdnn_mean: number | null
  stand_minutes: number
  active_minutes: number
}

export interface RecordCounts {
  total_seen: number
  kept: number
}

export interface ImportedData {
  window_days: number
  start_date: string
  end_date: string
  age: number | null
  export_xml_entry: string
  record_counts: RecordCounts
  daily: DailyRecord[]
  orthostatic_input?: Record<string, number>
}

export interface Signal {
  key: string
  severity: 'low' | 'moderate' | 'high'
  detail: string
}

export interface QuestionItem {
  id: string
  prompt: string
  options: string[]
}

export interface RobustStats {
  n: number
  median: number
  q1: number
  q3: number
  iqr: number
}

export interface ClusteringModelResult {
  source: string
  model_path?: string
  status: string
  phenotype_hint: string
  confidence: string
  reason: string
  cluster_id?: number
  distance_to_centroid?: number
  cluster_purity?: number
  cluster_followup_rate?: number
  feature_coverage?: number
  features_used?: Record<string, number | null>
  error?: string
}

export interface SurveyAssessment {
  status_context: string
  hint_context: string
  answered_count: number
  informative_answers: number
  support_votes: number
  against_votes: number
  support_score: number
  alignment: 'supports' | 'mixed' | 'does_not_support' | 'inconclusive'
  severe_red_flag: boolean
  summary: string
}

export interface Screening {
  status: 'normal' | 'needs_followup'
  phenotype_hint: string
  phenotype_confidence: 'high' | 'medium' | 'low'
  phenotype_reason: string
  bp_data_present: boolean
  signals: Signal[]
  questionnaire: QuestionItem[]
  safety_notes: string[]
  data_notes: string[]
  stats: {
    resting_hr: RobustStats | null
    hrv_sdnn: RobustStats | null
    stand_minutes: RobustStats | null
    active_minutes: RobustStats | null
  }
  clustering_model?: ClusteringModelResult
  survey_assessment?: SurveyAssessment | null
  llm?: GeminiScreeningResult | null
  llm_error?: string
}

export interface Symptoms {
  answers: { id: string; prompt: string; answer: string }[]
  updated_at: string | null
}

export interface SessionData {
  session_id: string
  imported: ImportedData
  screening: Screening
  symptoms: Symptoms
}

// ---- Gemini LLM output ----

export interface GeminiScreeningResult {
  status: string
  signals: Signal[] | string[]
  questionnaire: QuestionItem[]
  doctor_summary_bullets: string[]
  safety_notes: string[]
}

// ---- Frontend display helpers ----

export interface DailyMetric {
  date: string
  value: number
  unit: string
}

export interface HealthSummary {
  restingHeartRate: { mean: number | null; unit: string; last7Days: DailyMetric[] }
  heartRateVariability: { meanMs: number | null; unit: string; last7Days: DailyMetric[] }
  standMinutes: { mean: number | null; unit: string; last7Days: DailyMetric[] }
  activeMinutes: { mean: number | null; unit: string; last7Days: DailyMetric[] }
  lastUpdated: string
}

// ---- Answers POST response ----

export interface AnswersResponse {
  ok: boolean
  symptoms: Symptoms
  screening: Screening
  survey_assessment: SurveyAssessment
}
