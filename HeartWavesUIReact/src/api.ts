import type { SessionData, AnswersResponse, GeminiScreeningResult, Screening } from './types/health'

// ---- Helpers ----

function fetchWithTimeout(url: string, options: RequestInit, timeoutMs: number): Promise<Response> {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMs)
  return fetch(url, { ...options, signal: controller.signal }).finally(() => clearTimeout(timeout))
}

// ---- Health check ----

export async function checkHealth(): Promise<boolean> {
  try {
    const res = await fetchWithTimeout('/api/health', { method: 'GET' }, 2500)
    if (!res.ok) return false
    const data = await res.json()
    return data.ok === true
  } catch {
    return false
  }
}

// ---- Upload Apple Health export ----

export interface UploadOptions {
  file: File
  orthoRestHr?: string
  orthoStandHr?: string
  orthoRestSbp?: string
  orthoStandSbp?: string
}

export async function uploadAppleHealth(opts: UploadOptions): Promise<SessionData> {
  const fd = new FormData()
  fd.append('zip', opts.file)
  fd.append('use_gemini', '0') // always run Gemini browser-side

  if (opts.orthoRestHr) fd.append('ortho_rest_hr', opts.orthoRestHr)
  if (opts.orthoStandHr) fd.append('ortho_stand_hr', opts.orthoStandHr)
  if (opts.orthoRestSbp) fd.append('ortho_rest_sbp', opts.orthoRestSbp)
  if (opts.orthoStandSbp) fd.append('ortho_stand_sbp', opts.orthoStandSbp)

  const res = await fetchWithTimeout('/api/import/apple_health', { method: 'POST', body: fd }, 120_000)
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || `Upload failed (${res.status})`)
  return data as SessionData
}

// ---- Save symptom answers ----

export async function saveAnswers(
  sessionId: string,
  answers: Record<string, string>
): Promise<AnswersResponse> {
  const res = await fetchWithTimeout(
    '/api/session/answers',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId, answers }),
    },
    10_000
  )
  const data = await res.json()
  if (!res.ok) throw new Error(data.error || `Save answers failed (${res.status})`)
  return data as AnswersResponse
}

// ---- Persist Gemini LLM output to session ----

export async function persistLlm(sessionId: string, llm: GeminiScreeningResult): Promise<void> {
  const res = await fetchWithTimeout(
    '/api/session/llm',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: sessionId, llm }),
    },
    10_000
  )
  if (!res.ok) {
    const data = await res.json().catch(() => ({}))
    throw new Error((data as { error?: string }).error || `Persist LLM failed (${res.status})`)
  }
}

// ---- Report URL ----

export function reportUrl(sessionId: string): string {
  return `/api/report?session_id=${encodeURIComponent(sessionId)}`
}

// ---- Browser-side Gemini call ----

function mean(nums: (number | null | undefined)[]): number | null {
  const xs = nums.filter((x): x is number => typeof x === 'number' && Number.isFinite(x))
  if (!xs.length) return null
  return xs.reduce((a, b) => a + b, 0) / xs.length
}

function sum(nums: (number | null | undefined)[]): number {
  const xs = nums.filter((x): x is number => typeof x === 'number' && Number.isFinite(x))
  return xs.reduce((a, b) => a + b, 0)
}

function extractJson(text: string): string {
  const trimmed = text
    .trim()
    .replace(/^```(?:json)?\s*/i, '')
    .replace(/```\s*$/i, '')
    .trim()
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) return trimmed
  const match = trimmed.match(/\{[\s\S]*\}/)
  if (!match) throw new Error('Gemini did not return JSON')
  return match[0]
}

export async function callGeminiBrowser(
  imported: SessionData['imported'],
  screening: Screening,
  apiKey: string,
  model = 'gemini-2.5-flash'
): Promise<GeminiScreeningResult> {
  const daily = imported.daily ?? []
  const last7 = daily.slice(-7)
  const summary = {
    window: {
      start_date: imported.start_date,
      end_date: imported.end_date,
      window_days: imported.window_days,
    },
    recent_7d: {
      resting_hr_mean: mean(last7.map((d) => d.resting_hr_mean)),
      hrv_sdnn_mean: mean(last7.map((d) => d.hrv_sdnn_mean)),
      stand_minutes_total: sum(last7.map((d) => d.stand_minutes)),
      active_minutes_total: sum(last7.map((d) => d.active_minutes)),
    },
    baseline_stats: screening.stats ?? {},
    missingness: {
      days_with_resting_hr: daily.filter((d) => d.resting_hr_mean != null).length,
      days_with_hrv: daily.filter((d) => d.hrv_sdnn_mean != null).length,
    },
    baseline_status: screening.status,
    baseline_signals: screening.signals ?? [],
  }

  const prompt = [
    'You are assisting with a non-diagnostic health screening and self-advocacy tool.',
    'You must be conservative, avoid diagnosis, and avoid claiming certainty.',
    '',
    'INPUT: You will receive aggregated wearable features only (no raw streams).',
    'TASK: Produce JSON ONLY matching this schema:',
    '{',
    '  "status": "normal" | "needs_followup",',
    '  "signals": [{"key": string, "severity": "low"|"moderate"|"high", "detail": string}],',
    '  "questionnaire": [{"id": string, "prompt": string, "options": [string]}],',
    '  "doctor_summary_bullets": [string],',
    '  "safety_notes": [string]',
    '}',
    '',
    'Rules:',
    '- Do not diagnose (no "you have POTS" etc). Use "may warrant evaluation" phrasing.',
    '- Status means: "needs_followup" if patterns or missingness suggest talking to a clinician.',
    '- Keep signals to 2-5 items max and make them specific to the numbers provided.',
    '- Questionnaire should be 5-8 questions if needs_followup, otherwise 3-5.',
    '- Include a safety note about urgent red flags (chest pain, fainting, severe shortness of breath).',
    '- Use dysautonomia examples only as possible issues to watch for.',
    '',
    'SUMMARY JSON:',
    JSON.stringify(summary, null, 2),
  ].join('\n')

  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`
  const res = await fetchWithTimeout(
    url,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-goog-api-key': apiKey },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.2, maxOutputTokens: 900 },
      }),
    },
    45_000
  )

  if (!res.ok) {
    const text = await res.text()
    throw new Error(`Gemini HTTP ${res.status}: ${text.slice(0, 120)}`)
  }

  const payload = await res.json()
  const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text ?? ''
  const jsonText = extractJson(text)
  const llm = JSON.parse(jsonText) as GeminiScreeningResult
  llm.status = String(llm.status ?? '')
  llm.signals = Array.isArray(llm.signals) ? llm.signals : []
  llm.questionnaire = Array.isArray(llm.questionnaire) ? llm.questionnaire : []
  llm.doctor_summary_bullets = Array.isArray(llm.doctor_summary_bullets) ? llm.doctor_summary_bullets : []
  llm.safety_notes = Array.isArray(llm.safety_notes) ? llm.safety_notes : []
  return llm
}
