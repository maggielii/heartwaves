import { useState, useMemo, useRef, useEffect } from 'react'
import { useApp } from '../context/AppContext'
import { checkHealth } from '../api'
import { placeholderHealthSummary } from '../data/placeholderHealth'
import type { HealthSummary } from '../types/health'
import DatePickerStrip from '../components/DatePickerStrip'
import LineChart from '../components/LineChart'
import CombinedMetricsChart from '../components/CombinedMetricsChart'
import {
  computeMetricInsights,
  computeDailyComposites,
  getCrossMetricInsight,
} from '../utils/healthInsights'

const GEMINI_KEY_SESSION_KEY = 'heartwaves_google_api_key'
const GEMINI_MODEL_STORAGE_KEY = 'heartwaves_gemini_model'

const today = new Date().toISOString().slice(0, 10)

function getValueForDate(
  trend: HealthSummary['restingHeartRate']['last7Days'],
  date: string
): number | null {
  const row = trend.find((d) => d.date === date)
  return row ? row.value : null
}

function formatPhenotypeHint(hint: string) {
  switch (hint) {
    case 'normal': return 'Normal pattern'
    case 'pots_like': return 'POTS-like pattern'
    case 'ist_like': return 'IST-like pattern'
    case 'oh_like': return 'OH-like pattern'
    case 'vvs_like': return 'VVS-like pattern'
    case 'unspecified_autonomic': return 'Unspecified autonomic pattern'
    default: return 'Unspecified'
  }
}

export default function HomePage() {
  const app = useApp()
  const data = app.healthSummary ?? placeholderHealthSummary
  const hasSession = !!app.sessionId

  // Server health
  const [serverOnline, setServerOnline] = useState<boolean | null>(null)
  useEffect(() => {
    let cancelled = false

    const refreshHealth = async () => {
      const ok = await checkHealth()
      if (!cancelled) setServerOnline(ok)
    }

    refreshHealth()
    const interval = window.setInterval(refreshHealth, 5000)

    return () => {
      cancelled = true
      window.clearInterval(interval)
    }
  }, [])

  // Upload form state
  const fileRef = useRef<HTMLInputElement>(null)
  const [orthoRestHr, setOrthoRestHr] = useState('')
  const [orthoStandHr, setOrthoStandHr] = useState('')
  const [orthoRestSbp, setOrthoRestSbp] = useState('')
  const [orthoStandSbp, setOrthoStandSbp] = useState('')
  const [showOrtho, setShowOrtho] = useState(false)
  const [geminiKey, setGeminiKey] = useState(() => sessionStorage.getItem(GEMINI_KEY_SESSION_KEY) ?? '')
  const [geminiModel, setGeminiModel] = useState(() => localStorage.getItem(GEMINI_MODEL_STORAGE_KEY) ?? 'gemini-2.5-flash')

  const handleUpload = async () => {
    const file = fileRef.current?.files?.[0]
    if (!file) return
    sessionStorage.setItem(GEMINI_KEY_SESSION_KEY, geminiKey)
    localStorage.setItem(GEMINI_MODEL_STORAGE_KEY, geminiModel)
    await app.doUpload(
      { file, orthoRestHr, orthoStandHr, orthoRestSbp, orthoStandSbp },
      geminiKey || undefined,
      geminiModel || undefined
    )
  }

  // Date picker
  const availableDates = useMemo(
    () => data.restingHeartRate.last7Days.map((d) => d.date),
    [data]
  )
  const defaultSelected =
    availableDates.includes(today) ? today : availableDates[availableDates.length - 1] ?? today
  const [selectedDate, setSelectedDate] = useState(defaultSelected)

  // Reset selected date when data changes
  useEffect(() => {
    if (availableDates.length > 0) {
      const pick = availableDates.includes(today) ? today : availableDates[availableDates.length - 1]
      setSelectedDate(pick)
    }
  }, [availableDates])

  const dayValues = useMemo(
    () => ({
      restingHeartRate: getValueForDate(data.restingHeartRate.last7Days, selectedDate),
      heartRateVariability: getValueForDate(data.heartRateVariability.last7Days, selectedDate),
      standMinutes: getValueForDate(data.standMinutes.last7Days, selectedDate),
      activeMinutes: getValueForDate(data.activeMinutes.last7Days, selectedDate),
    }),
    [data, selectedDate]
  )

  const selectedLabel =
    selectedDate === today
      ? 'Today'
      : new Date(selectedDate + 'T12:00:00').toLocaleDateString('en-US', {
          weekday: 'long',
          month: 'short',
          day: 'numeric',
        })

  const insights = useMemo(() => computeMetricInsights(data), [data])
  const composites = useMemo(() => computeDailyComposites(data), [data])
  const crossInsight = useMemo(() => getCrossMetricInsight(composites), [composites])

  return (
    <div style={styles.page}>
      {/* Upload Section */}
      <section style={styles.uploadSection}>
        <h2 style={styles.uploadTitle}>Upload Apple Health Export</h2>
        <p style={styles.uploadHint}>
          Export your data from the Apple Health app (Settings &rarr; Health &rarr; Export All Health Data), then upload the .zip or export.xml file below.
        </p>
        <div style={styles.serverStatus}>
          {serverOnline === null
            ? 'Checking server...'
            : serverOnline
              ? 'Server: online'
              : 'Server: offline — start ruby server.rb'}
        </div>
        <div style={styles.uploadRow}>
          <input ref={fileRef} type="file" accept=".zip,.xml" style={styles.fileInput} />
          <button
            type="button"
            onClick={handleUpload}
            disabled={app.uploading}
            style={styles.uploadBtn}
          >
            {app.uploading ? 'Processing...' : 'Upload & Analyze'}
          </button>
          <button type="button" onClick={app.doReset} style={styles.resetBtn}>
            Reset
          </button>
        </div>

        {/* Orthostatic quick-check (collapsible) */}
        <button
          type="button"
          onClick={() => setShowOrtho(!showOrtho)}
          style={styles.orthoToggle}
        >
          {showOrtho ? '\u25BE' : '\u25B8'} Orthostatic quick-check (optional)
        </button>
        {showOrtho && (
          <div style={styles.orthoGrid}>
            <label style={styles.orthoLabel}>
              Resting HR (bpm)
              <input type="number" value={orthoRestHr} onChange={(e) => setOrthoRestHr(e.target.value)} style={styles.orthoInput} placeholder="e.g. 72" />
            </label>
            <label style={styles.orthoLabel}>
              Standing HR (bpm)
              <input type="number" value={orthoStandHr} onChange={(e) => setOrthoStandHr(e.target.value)} style={styles.orthoInput} placeholder="e.g. 105" />
            </label>
            <label style={styles.orthoLabel}>
              Resting SBP (mmHg)
              <input type="number" value={orthoRestSbp} onChange={(e) => setOrthoRestSbp(e.target.value)} style={styles.orthoInput} placeholder="e.g. 120" />
            </label>
            <label style={styles.orthoLabel}>
              Standing SBP (mmHg)
              <input type="number" value={orthoStandSbp} onChange={(e) => setOrthoStandSbp(e.target.value)} style={styles.orthoInput} placeholder="e.g. 95" />
            </label>
          </div>
        )}

        {/* Gemini toggle */}
        <div style={styles.geminiRow}>
          <label style={styles.geminiCheckLabel}>
            <input
              type="checkbox"
              checked={app.geminiEnabled}
              onChange={(e) => app.setGeminiEnabled(e.target.checked)}
            />
            Use Gemini from browser (optional)
          </label>
          {app.geminiEnabled && (
            <div style={styles.geminiFields}>
              <input
                type="password"
                value={geminiKey}
                onChange={(e) => setGeminiKey(e.target.value)}
                placeholder="Google AI Studio API key"
                style={styles.geminiInput}
              />
              <input
                type="text"
                value={geminiModel}
                onChange={(e) => setGeminiModel(e.target.value)}
                placeholder="gemini-2.5-flash"
                style={{ ...styles.geminiInput, maxWidth: 200 }}
              />
            </div>
          )}
        </div>

        {/* Status messages */}
        {app.uploadError && <p style={styles.errorMsg}>Error: {app.uploadError}</p>}
        {app.geminiRunning && <p style={styles.infoMsg}>Running Gemini in browser...</p>}
        {app.geminiError && <p style={styles.warnMsg}>Gemini: {app.geminiError} (used rules-only)</p>}
        {hasSession && app.imported && (
          <p style={styles.successMsg}>
            Parsed {app.imported.record_counts.kept} records in-window ({app.imported.window_days}-day window).
          </p>
        )}
      </section>

      {/* Screening Status (only after upload) */}
      {hasSession && app.screening && (
        <section style={styles.screeningSection}>
          <div style={styles.statusRow}>
            <span
              style={{
                ...styles.statusPill,
                ...(app.screening.status === 'normal' ? styles.pillOk : styles.pillBad),
              }}
            >
              {app.screening.status === 'normal' ? 'NORMAL' : 'NEEDS FOLLOW-UP'}
            </span>
            <span style={styles.phenotypeText}>
              {formatPhenotypeHint(app.screening.phenotype_hint)}
            </span>
            <span style={styles.confidenceText}>
              Confidence: {app.screening.phenotype_confidence}
            </span>
          </div>
          {app.screening.phenotype_reason && (
            <p style={styles.phenotypeReason}>{app.screening.phenotype_reason}</p>
          )}
          {app.screening.clustering_model && !app.screening.clustering_model.error && (
            <p style={styles.modelStatus}>
              Cluster model: {app.screening.clustering_model.status?.toUpperCase()} |{' '}
              {formatPhenotypeHint(app.screening.clustering_model.phenotype_hint)} |{' '}
              {app.screening.clustering_model.confidence} confidence |{' '}
              coverage {((app.screening.clustering_model.feature_coverage ?? 0) * 100).toFixed(0)}%
            </p>
          )}
          {app.surveyAssessment && (
            <p style={styles.surveyText}>{app.surveyAssessment.summary}</p>
          )}
        </section>
      )}

      {/* Health Dashboard */}
      <h1 style={styles.title}>
        {hasSession ? 'Your health at a glance' : 'Health Summary (placeholder data)'}
      </h1>
      <p style={styles.subtitle}>
        {hasSession
          ? "Summary from your uploaded health data. Pick a day below to see that day's metrics."
          : 'Upload your Apple Health export above to see your real data. Showing demo data below.'}
      </p>

      <DatePickerStrip
        selectedDate={selectedDate}
        onSelectDate={setSelectedDate}
        availableDates={availableDates}
      />

      <section style={styles.todaySection} aria-label={`Metrics for ${selectedLabel}`}>
        <h2 style={styles.todayTitle}>{selectedLabel}</h2>
        <div style={styles.todayCards}>
          <DayMetricCard label="Resting heart rate" value={dayValues.restingHeartRate} unit={data.restingHeartRate.unit} />
          <DayMetricCard label="Heart rate variability" value={dayValues.heartRateVariability} unit={data.heartRateVariability.unit} />
          <DayMetricCard label="Stand minutes" value={dayValues.standMinutes} unit={data.standMinutes.unit} />
          <DayMetricCard label="Active minutes" value={dayValues.activeMinutes} unit={data.activeMinutes.unit} />
        </div>
      </section>

      <section style={styles.chartsSection} aria-label="7-day trends">
        <h2 style={styles.sectionTitle}>Last 7 days — line trends</h2>
        <div style={styles.chartGrid}>
          <MetricLineCard label="Resting heart rate" trend={data.restingHeartRate.last7Days} valueLabel={data.restingHeartRate.unit} selectedDate={selectedDate} onSelectDate={setSelectedDate} />
          <MetricLineCard label="Heart rate variability" trend={data.heartRateVariability.last7Days} valueLabel={data.heartRateVariability.unit} selectedDate={selectedDate} onSelectDate={setSelectedDate} />
          <MetricLineCard label="Stand minutes" trend={data.standMinutes.last7Days} valueLabel={data.standMinutes.unit} selectedDate={selectedDate} onSelectDate={setSelectedDate} />
          <MetricLineCard label="Active minutes" trend={data.activeMinutes.last7Days} valueLabel={data.activeMinutes.unit} selectedDate={selectedDate} onSelectDate={setSelectedDate} />
        </div>
      </section>

      {/* Insights Section */}
      <section style={styles.insightsSection} aria-label="Insights and tips">
        <h2 style={styles.insightsTitle}>
          <span style={styles.insightsBadge}>Insights</span>
          Tips & combined view
        </h2>
        <p style={styles.insightsIntro}>
          Derived from your data: trends, baselines, and simple tips. Not medical advice — use them to start conversations with your doctor.
        </p>

        <div style={styles.combinedChartCard}>
          <h3 style={styles.combinedChartTitle}>All metrics on one scale (0-100)</h3>
          <CombinedMetricsChart composites={composites} height={220} />
        </div>

        {crossInsight && (
          <div style={styles.crossInsightCard}>
            <span style={styles.crossInsightLabel}>Pattern</span>
            <p style={styles.crossInsightText}>{crossInsight}</p>
          </div>
        )}

        <div style={styles.tipsGrid}>
          {insights.map((ins) => (
            <article key={ins.metric} style={styles.tipCard}>
              <div style={styles.tipCardHeader}>
                <span style={styles.tipCardLabel}>{ins.label}</span>
                <span
                  style={{
                    ...styles.trendBadge,
                    ...(ins.trend === 'up'
                      ? styles.trendUp
                      : ins.trend === 'down'
                        ? styles.trendDown
                        : styles.trendStable),
                  }}
                >
                  {ins.trend === 'up' ? '\u2191' : ins.trend === 'down' ? '\u2193' : '\u2192'} {Math.abs(ins.percentChange).toFixed(0)}%
                </span>
              </div>
              <p style={styles.tipText}>{ins.tip}</p>
              {ins.tipReason && <p style={styles.tipReason}>{ins.tipReason}</p>}
              <p style={styles.tipMeta}>
                Best day: {ins.bestDay.value}{' '}
                {ins.metric === 'standMinutes' || ins.metric === 'activeMinutes' ? 'min' : ins.metric === 'heartRateVariability' ? 'ms' : 'bpm'}
                {' \u00B7 '}
                Worst: {ins.worstDay.value}{' '}
                {ins.metric === 'standMinutes' || ins.metric === 'activeMinutes' ? 'min' : ins.metric === 'heartRateVariability' ? 'ms' : 'bpm'}
              </p>
            </article>
          ))}
        </div>
      </section>

      <p style={styles.footer}>
        {hasSession
          ? `Data from ${app.imported?.start_date} to ${app.imported?.end_date}.`
          : 'Data last updated: placeholder \u2014 connect your Apple Health export when ready.'}
      </p>
    </div>
  )
}

// Sub-components

function DayMetricCard({ label, value, unit }: { label: string; value: number | null; unit: string }) {
  const display =
    value !== null && value !== undefined
      ? typeof value === 'number' && Number.isInteger(value)
        ? value.toLocaleString()
        : Number(value).toFixed(1)
      : '\u2014'
  return (
    <article style={styles.dayCard}>
      <h3 style={styles.dayCardTitle}>{label}</h3>
      <p style={styles.dayCardValue}>
        {display}
        {value !== null && <span style={styles.dayCardUnit}> {unit}</span>}
      </p>
    </article>
  )
}

function MetricLineCard({
  label, trend, valueLabel, selectedDate, onSelectDate,
}: {
  label: string
  trend: HealthSummary['restingHeartRate']['last7Days']
  valueLabel: string
  selectedDate: string
  onSelectDate: (date: string) => void
}) {
  const selectedPoint = trend.find((d) => d.date === selectedDate)
  const displayValue = selectedPoint
    ? typeof selectedPoint.value === 'number' && Number.isInteger(selectedPoint.value)
      ? selectedPoint.value.toLocaleString()
      : Number(selectedPoint.value).toFixed(1)
    : '\u2014'

  return (
    <article style={styles.lineCard}>
      <h3 style={styles.lineCardTitle}>{label}</h3>
      <p style={styles.lineCardValue}>
        {displayValue} <span style={styles.lineCardUnit}>{valueLabel}</span>
        <span style={styles.lineCardHint}> (selected day)</span>
      </p>
      <div style={styles.chartWrap}>
        <LineChart data={trend} valueLabel={valueLabel} selectedDate={selectedDate} onSelectDate={onSelectDate} height={120} />
      </div>
    </article>
  )
}

// Styles

const styles: Record<string, React.CSSProperties> = {
  page: { display: 'flex', flexDirection: 'column', gap: '1.5rem' },

  // Upload
  uploadSection: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.5rem' },
  uploadTitle: { margin: '0 0 0.5rem', fontSize: '1.25rem', fontWeight: 700 },
  uploadHint: { margin: '0 0 0.75rem', fontSize: '0.875rem', color: 'var(--text-muted)' },
  serverStatus: { fontSize: '0.75rem', color: 'var(--text-muted)', marginBottom: '0.75rem' },
  uploadRow: { display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' },
  fileInput: { fontSize: '0.875rem', color: 'var(--text)' },
  uploadBtn: { padding: '0.6rem 1.25rem', background: 'var(--accent)', color: 'var(--bg)', border: 'none', borderRadius: 'var(--radius)', fontWeight: 600, fontSize: '0.9375rem', cursor: 'pointer' },
  resetBtn: { padding: '0.6rem 1rem', background: 'var(--surface-elevated)', color: 'var(--text-muted)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', fontWeight: 500, fontSize: '0.875rem', cursor: 'pointer' },

  // Orthostatic
  orthoToggle: { background: 'none', border: 'none', color: 'var(--text-muted)', fontSize: '0.8125rem', fontWeight: 500, cursor: 'pointer', padding: '0.5rem 0', textAlign: 'left' },
  orthoGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: '0.75rem', marginBottom: '0.5rem' },
  orthoLabel: { display: 'flex', flexDirection: 'column', gap: '0.25rem', fontSize: '0.8125rem', color: 'var(--text-muted)', fontWeight: 500 },
  orthoInput: { padding: '0.4rem 0.6rem', background: 'var(--bg)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', color: 'var(--text)', fontSize: '0.9375rem', fontFamily: 'inherit' },

  // Gemini
  geminiRow: { marginTop: '0.5rem', display: 'flex', flexDirection: 'column', gap: '0.5rem' },
  geminiCheckLabel: { display: 'flex', alignItems: 'center', gap: '0.5rem', fontSize: '0.875rem', color: 'var(--text-muted)', cursor: 'pointer' },
  geminiFields: { display: 'flex', gap: '0.5rem', flexWrap: 'wrap' },
  geminiInput: { padding: '0.4rem 0.6rem', background: 'var(--bg)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', color: 'var(--text)', fontSize: '0.875rem', fontFamily: 'inherit', flex: '1 1 250px' },

  // Status messages
  errorMsg: { margin: '0.5rem 0 0', color: 'var(--danger)', fontSize: '0.875rem', fontWeight: 600 },
  warnMsg: { margin: '0.5rem 0 0', color: 'var(--warning)', fontSize: '0.875rem' },
  infoMsg: { margin: '0.5rem 0 0', color: 'var(--text-muted)', fontSize: '0.875rem' },
  successMsg: { margin: '0.5rem 0 0', color: 'var(--accent)', fontSize: '0.875rem', fontWeight: 500 },

  // Screening status
  screeningSection: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  statusRow: { display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' },
  statusPill: { display: 'inline-block', padding: '0.3rem 0.75rem', borderRadius: 20, fontSize: '0.8125rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.04em' },
  pillOk: { background: 'rgba(94,191,158,0.15)', color: 'var(--accent)' },
  pillBad: { background: 'rgba(217,117,109,0.15)', color: 'var(--danger)' },
  phenotypeText: { fontSize: '1rem', fontWeight: 600, color: 'var(--text)' },
  confidenceText: { fontSize: '0.8125rem', color: 'var(--text-muted)' },
  phenotypeReason: { margin: '0.5rem 0 0', fontSize: '0.875rem', color: 'var(--text-muted)' },
  modelStatus: { margin: '0.5rem 0 0', fontSize: '0.8125rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' },
  surveyText: { margin: '0.5rem 0 0', fontSize: '0.8125rem', color: 'var(--accent)' },

  // Dashboard
  title: { margin: 0, fontSize: '1.75rem', fontWeight: 700 },
  subtitle: { margin: 0, color: 'var(--text-muted)', fontSize: '1rem' },
  todaySection: { display: 'flex', flexDirection: 'column', gap: '1rem' },
  todayTitle: { margin: 0, fontSize: '1.125rem', fontWeight: 600, color: 'var(--text-muted)' },
  todayCards: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))', gap: '0.75rem' },
  dayCard: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1rem' },
  dayCardTitle: { margin: '0 0 0.25rem', fontSize: '0.75rem', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' },
  dayCardValue: { margin: 0, fontSize: '1.375rem', fontWeight: 700, fontFamily: 'var(--font-mono)', color: 'var(--accent)' },
  dayCardUnit: { fontSize: '0.875rem', fontWeight: 500, color: 'var(--text-muted)' },
  chartsSection: { display: 'flex', flexDirection: 'column', gap: '1rem' },
  sectionTitle: { margin: 0, fontSize: '1.125rem', fontWeight: 600, color: 'var(--text-muted)' },
  chartGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))', gap: '1rem' },
  lineCard: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  lineCardTitle: { margin: '0 0 0.25rem', fontSize: '0.875rem', fontWeight: 600, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' },
  lineCardValue: { margin: '0 0 0.75rem', fontSize: '1.25rem', fontWeight: 700, fontFamily: 'var(--font-mono)', color: 'var(--accent)' },
  lineCardUnit: { fontSize: '0.875rem', fontWeight: 500, color: 'var(--text-muted)' },
  lineCardHint: { fontSize: '0.75rem', fontWeight: 400, color: 'var(--text-muted)', marginLeft: '0.25rem' },
  chartWrap: { width: '100%', minHeight: 120 },

  // Insights
  insightsSection: { marginTop: '0.5rem', padding: '1.5rem', background: 'linear-gradient(180deg, var(--surface-elevated) 0%, var(--surface) 100%)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', boxShadow: '0 4px 24px rgba(0,0,0,0.2)' },
  insightsTitle: { margin: '0 0 0.25rem', fontSize: '1.375rem', fontWeight: 700, display: 'flex', alignItems: 'center', gap: '0.5rem', flexWrap: 'wrap' },
  insightsBadge: { display: 'inline-block', padding: '0.2rem 0.5rem', background: 'var(--accent)', color: 'var(--bg)', borderRadius: 6, fontSize: '0.75rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.05em' },
  insightsIntro: { margin: '0 0 1.25rem', fontSize: '0.9375rem', color: 'var(--text-muted)', maxWidth: '42ch' },
  combinedChartCard: { background: 'var(--bg)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem', marginBottom: '1.25rem' },
  combinedChartTitle: { margin: '0 0 1rem', fontSize: '0.875rem', fontWeight: 600, color: 'var(--text-muted)' },
  crossInsightCard: { background: 'rgba(94, 191, 158, 0.08)', border: '1px solid var(--accent-dim)', borderRadius: 'var(--radius)', padding: '1rem 1.25rem', marginBottom: '1.25rem' },
  crossInsightLabel: { fontSize: '0.7rem', fontWeight: 700, color: 'var(--accent)', textTransform: 'uppercase', letterSpacing: '0.05em' },
  crossInsightText: { margin: '0.35rem 0 0', fontSize: '0.9375rem', lineHeight: 1.5, color: 'var(--text)' },
  tipsGrid: { display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: '1rem' },
  tipCard: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  tipCardHeader: { display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: '0.5rem', marginBottom: '0.5rem' },
  tipCardLabel: { fontSize: '0.8rem', fontWeight: 700, color: 'var(--text-muted)', textTransform: 'uppercase', letterSpacing: '0.04em' },
  trendBadge: { fontSize: '0.7rem', fontWeight: 600, padding: '0.15rem 0.4rem', borderRadius: 4 },
  trendUp: { background: 'rgba(232, 184, 109, 0.2)', color: 'var(--warning)' },
  trendDown: { background: 'rgba(217, 117, 109, 0.2)', color: 'var(--danger)' },
  trendStable: { background: 'var(--surface-elevated)', color: 'var(--text-muted)' },
  tipText: { margin: 0, fontSize: '0.9375rem', lineHeight: 1.5, color: 'var(--text)' },
  tipReason: { margin: '0.5rem 0 0', fontSize: '0.8125rem', color: 'var(--text-muted)' },
  tipMeta: { margin: '0.75rem 0 0', fontSize: '0.75rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' },
  footer: { margin: 0, fontSize: '0.875rem', color: 'var(--text-muted)' },
}
