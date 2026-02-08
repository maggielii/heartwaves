import { useState, useMemo } from 'react'
import { Link } from 'react-router-dom'
import { useApp } from '../context/AppContext'

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

export default function QuestionsPage() {
  const app = useApp()
  const hasSession = !!app.sessionId
  const screening = app.screening
  const signals = screening?.signals ?? []
  const questionnaire = screening?.questionnaire ?? []
  const safetyNotes = screening?.safety_notes ?? []

  // Build initial answers from previously saved symptoms
  const savedAnswerMap = useMemo(() => {
    const map: Record<string, string> = {}
    if (app.symptoms?.answers) {
      for (const a of app.symptoms.answers) {
        if (a.id && a.answer) map[a.id] = a.answer
      }
    }
    return map
  }, [app.symptoms])

  const [answers, setAnswers] = useState<Record<string, string>>(savedAnswerMap)

  const handleAnswer = (id: string, value: string) => {
    setAnswers((prev) => ({ ...prev, [id]: value }))
  }

  const handleSubmit = async () => {
    await app.doSaveAnswers(answers)
  }

  return (
    <div style={styles.page}>
      <h1 style={styles.title}>Follow-up questions</h1>
      <p style={styles.subtitle}>
        If our system notices patterns in your health data that might be worth discussing with a doctor, we'll ask you a few short questions here. Your answers help clarify context — we never diagnose. If follow-up is suggested, take your doctor report with you.
      </p>

      {!hasSession && (
        <div style={styles.emptyState}>
          <p>Upload your Apple Health data on the <Link to="/">Home</Link> page first. Your screening results and follow-up questions will appear here.</p>
        </div>
      )}

      {hasSession && screening && (
        <>
          {/* Status summary */}
          <section style={styles.statusCard}>
            <div style={styles.statusRow}>
              <span
                style={{
                  ...styles.statusPill,
                  ...(screening.status === 'normal' ? styles.pillOk : styles.pillBad),
                }}
              >
                {screening.status === 'normal' ? 'NORMAL' : 'NEEDS FOLLOW-UP'}
              </span>
              <span style={styles.phenotype}>
                {formatPhenotypeHint(screening.phenotype_hint)}
              </span>
            </div>
          </section>

          {/* Signals */}
          {signals.length > 0 && (
            <section style={styles.signals}>
              <h2 style={styles.sectionTitle}>What we noticed</h2>
              <ul style={styles.signalList}>
                {signals.map((s, i) => (
                  <li key={i}>{typeof s === 'string' ? s : s.detail || s.key}</li>
                ))}
              </ul>
              {safetyNotes.length > 0 && (
                <p style={styles.safety}>{safetyNotes.join(' ')}</p>
              )}
            </section>
          )}

          {/* Questionnaire */}
          {questionnaire.length > 0 && (
            <section style={styles.questions}>
              <h2 style={styles.sectionTitle}>Please answer these questions</h2>
              {questionnaire.map((q) => (
                <div key={q.id} style={styles.questionBlock}>
                  <p style={styles.questionText}>{q.prompt}</p>
                  <div style={styles.options}>
                    {(q.options ?? []).map((opt) => (
                      <label key={opt} style={styles.option}>
                        <input
                          type="radio"
                          name={q.id}
                          value={opt}
                          checked={answers[q.id] === opt}
                          onChange={() => handleAnswer(q.id, opt)}
                        />
                        <span>{opt}</span>
                      </label>
                    ))}
                  </div>
                </div>
              ))}
              <button
                type="button"
                onClick={handleSubmit}
                disabled={app.savingAnswers || Object.keys(answers).length === 0}
                style={styles.primaryButton}
              >
                {app.savingAnswers ? 'Saving...' : 'Save symptoms to report'}
              </button>
              {app.answersError && (
                <p style={styles.errorMsg}>Error: {app.answersError}</p>
              )}
            </section>
          )}

          {/* Survey assessment result */}
          {app.surveyAssessment && (
            <div style={styles.outcome}>
              <h2 style={styles.sectionTitle}>Survey assessment</h2>
              <p style={styles.assessmentText}>{app.surveyAssessment.summary}</p>
              <p style={styles.assessmentDetail}>
                Alignment: <strong>{app.surveyAssessment.alignment.replace(/_/g, ' ')}</strong>
                {' \u00B7 '}Score: {app.surveyAssessment.support_score.toFixed(2)}
                {' \u00B7 '}Informative answers: {app.surveyAssessment.informative_answers}
              </p>
            </div>
          )}

          {/* Next steps */}
          {(app.surveyAssessment || signals.length > 0) && (
            <div style={styles.nextSteps}>
              <h2 style={styles.sectionTitle}>Next steps</h2>
              <p>
                If follow-up was suggested, we recommend bringing your doctor report to your next visit. Generate it on the{' '}
                <Link to="/report">Doctor report</Link> page.
              </p>
              {screening.llm?.doctor_summary_bullets && screening.llm.doctor_summary_bullets.length > 0 && (
                <ul style={styles.bullets}>
                  {screening.llm.doctor_summary_bullets.map((b, i) => (
                    <li key={i}>{b}</li>
                  ))}
                </ul>
              )}
            </div>
          )}
        </>
      )}
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  page: { display: 'flex', flexDirection: 'column', gap: '1.5rem' },
  title: { margin: 0, fontSize: '1.75rem', fontWeight: 700 },
  subtitle: { margin: 0, color: 'var(--text-muted)', fontSize: '1rem' },
  emptyState: { background: 'var(--surface)', border: '1px dashed var(--border)', borderRadius: 'var(--radius)', padding: '2rem', textAlign: 'center', color: 'var(--text-muted)' },

  // Status
  statusCard: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1rem 1.25rem' },
  statusRow: { display: 'flex', alignItems: 'center', gap: '1rem', flexWrap: 'wrap' },
  statusPill: { display: 'inline-block', padding: '0.3rem 0.75rem', borderRadius: 20, fontSize: '0.8125rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.04em' },
  pillOk: { background: 'rgba(94,191,158,0.15)', color: 'var(--accent)' },
  pillBad: { background: 'rgba(217,117,109,0.15)', color: 'var(--danger)' },
  phenotype: { fontSize: '1rem', fontWeight: 600, color: 'var(--text)' },

  // Signals
  signals: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  sectionTitle: { margin: '0 0 0.75rem', fontSize: '1.125rem', fontWeight: 600 },
  signalList: { margin: 0, paddingLeft: '1.25rem', color: 'var(--text-muted)' },
  safety: { margin: '1rem 0 0', fontSize: '0.875rem', color: 'var(--warning)' },

  // Questions
  questions: { display: 'flex', flexDirection: 'column', gap: '1.25rem' },
  questionBlock: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  questionText: { margin: '0 0 0.75rem', fontWeight: 500 },
  options: { display: 'flex', flexDirection: 'column', gap: '0.5rem' },
  option: { display: 'flex', alignItems: 'center', gap: '0.5rem', cursor: 'pointer' },
  primaryButton: { alignSelf: 'flex-start', padding: '0.75rem 1.25rem', background: 'var(--accent)', color: 'var(--bg)', border: 'none', borderRadius: 'var(--radius)', fontWeight: 600, fontSize: '1rem', cursor: 'pointer' },
  errorMsg: { margin: '0.5rem 0 0', color: 'var(--danger)', fontSize: '0.875rem' },

  // Assessment
  outcome: { background: 'var(--surface-elevated)', border: '1px solid var(--accent-dim)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  assessmentText: { margin: '0 0 0.5rem', fontSize: '0.9375rem', color: 'var(--text)' },
  assessmentDetail: { margin: 0, fontSize: '0.8125rem', color: 'var(--text-muted)', fontFamily: 'var(--font-mono)' },

  // Next steps
  nextSteps: { background: 'var(--surface)', border: '1px solid var(--border)', borderRadius: 'var(--radius)', padding: '1.25rem' },
  bullets: { margin: '0.75rem 0 0', paddingLeft: '1.25rem' },
}
