import { useState } from 'react'
import { usePersonal } from '../context/PersonalContext'
import { MOOD_OPTIONS, MOOD_LABELS, type PersonalInfo } from '../types/personal'

const today = new Date().toISOString().slice(0, 10)

export default function PersonalPage() {
  const { personalInfo, setPersonalInfo, dailyLogs, addOrUpdateLog, getLogForDate } = usePersonal()
  const [logDate, setLogDate] = useState(today)
  const [mood, setMood] = useState<number>(() => getLogForDate(today)?.mood ?? 3)
  const [energy, setEnergy] = useState<number | ''>(() => getLogForDate(today)?.energy ?? '')
  const [logNote, setLogNote] = useState(() => getLogForDate(today)?.note ?? '')

  const handleSaveLog = () => {
    addOrUpdateLog({
      date: logDate,
      mood,
      energy: energy === '' ? null : Number(energy),
      note: logNote.trim(),
    })
    if (logDate === today) {
      setMood(getLogForDate(today)?.mood ?? 3)
      setEnergy(getLogForDate(today)?.energy ?? '')
      setLogNote(getLogForDate(today)?.note ?? '')
    }
  }

  const recentLogs = dailyLogs.slice(0, 14)

  return (
    <div style={styles.page}>
      <h1 style={styles.title}>Personal information</h1>
      <p style={styles.subtitle}>
        Update your details anytime. This info can appear on your summary and in your doctor report. Stored only on this device unless you export or share.
      </p>

      <section style={styles.section}>
        <h2 style={styles.sectionTitle}>About you</h2>
        <div style={styles.formGrid}>
          <label style={styles.label}>
            Age (years)
            <input
              type="number"
              min={1}
              max={120}
              value={personalInfo.age ?? ''}
              onChange={(e) =>
                setPersonalInfo({
                  age: e.target.value === '' ? null : Math.max(0, parseInt(e.target.value, 10) || 0),
                })
              }
              placeholder="e.g. 32"
              style={styles.input}
            />
          </label>
          <label style={styles.label}>
            Height (cm)
            <input
              type="number"
              min={100}
              max={250}
              value={personalInfo.heightCm ?? ''}
              onChange={(e) =>
                setPersonalInfo({
                  heightCm:
                    e.target.value === '' ? null : Math.max(0, parseInt(e.target.value, 10) || 0),
                })
              }
              placeholder="e.g. 170"
              style={styles.input}
            />
          </label>
          <label style={styles.label}>
            Weight (kg)
            <input
              type="number"
              min={30}
              max={300}
              step={0.1}
              value={personalInfo.weightKg ?? ''}
              onChange={(e) =>
                setPersonalInfo({
                  weightKg:
                    e.target.value === ''
                      ? null
                      : Math.max(0, parseFloat(e.target.value) || 0),
                })
              }
              placeholder="e.g. 68"
              style={styles.input}
            />
          </label>
          <label style={styles.label}>
            Sex (optional)
            <select
              value={personalInfo.sex}
              onChange={(e) =>
                setPersonalInfo({
                  sex: e.target.value as PersonalInfo['sex'],
                })
              }
              style={styles.input}
            >
              <option value="">Prefer not to say</option>
              <option value="female">Female</option>
              <option value="male">Male</option>
              <option value="other">Other</option>
            </select>
          </label>
        </div>
        <label style={styles.labelBlock}>
          Recent comments about your life (stress, routine changes, etc.)
          <textarea
            value={personalInfo.recentComments}
            onChange={(e) => setPersonalInfo({ recentComments: e.target.value })}
            placeholder="e.g. Started a new job, traveling more, changed medication..."
            rows={3}
            style={styles.textarea}
          />
        </label>
        {personalInfo.lastUpdated && (
          <p style={styles.updated}>
            Last updated: {new Date(personalInfo.lastUpdated).toLocaleString()}
          </p>
        )}
      </section>

      <section style={styles.section}>
        <h2 style={styles.sectionTitle}>Daily log — mood & notes</h2>
        <p style={styles.sectionHint}>
          Log how you felt each day. Helps you and your doctor see patterns over time.
        </p>
        <div style={styles.logForm}>
          <label style={styles.label}>
            Date
            <input
              type="date"
              value={logDate}
              onChange={(e) => {
                const d = e.target.value
                setLogDate(d)
                const log = getLogForDate(d)
                setMood(log?.mood ?? 3)
                setEnergy(log?.energy ?? '')
                setLogNote(log?.note ?? '')
              }}
              style={styles.input}
            />
          </label>
          <div style={styles.moodRow}>
            <span style={styles.moodLabel}>Mood</span>
            <div style={styles.moodOptions} role="group" aria-label="Mood">
              {MOOD_OPTIONS.map((n) => (
                <button
                  key={n}
                  type="button"
                  onClick={() => setMood(n)}
                  style={{
                    ...styles.moodBtn,
                    ...(mood === n ? styles.moodBtnActive : {}),
                  }}
                  title={MOOD_LABELS[n]}
                >
                  {n}
                </button>
              ))}
            </div>
            <span style={styles.moodValue}>{MOOD_LABELS[mood]}</span>
          </div>
          <label style={styles.label}>
            Energy (1–5, optional)
            <select
              value={energy === '' ? '' : energy}
              onChange={(e) => setEnergy(e.target.value === '' ? '' : Number(e.target.value))}
              style={styles.input}
            >
              <option value="">—</option>
              {[1, 2, 3, 4, 5].map((n) => (
                <option key={n} value={n}>
                  {n} — {n <= 2 ? 'Low' : n <= 3 ? 'Okay' : 'High'}
                </option>
              ))}
            </select>
          </label>
          <label style={styles.labelBlock}>
            Note for this day
            <input
              type="text"
              value={logNote}
              onChange={(e) => setLogNote(e.target.value)}
              placeholder="e.g. Busy day, slept poorly"
              style={styles.input}
            />
          </label>
          <button type="button" onClick={handleSaveLog} style={styles.saveBtn}>
            Save log for {logDate === today ? 'today' : logDate}
          </button>
        </div>
        {recentLogs.length > 0 && (
          <div style={styles.recentLogs}>
            <h3 style={styles.recentTitle}>Recent logs</h3>
            <ul style={styles.logList}>
              {recentLogs.map((entry) => (
                <li key={entry.date} style={styles.logItem}>
                  <span style={styles.logDate}>
                    {entry.date === today ? 'Today' : new Date(entry.date + 'T12:00:00').toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}
                  </span>
                  <span style={styles.logMood}>Mood: {MOOD_LABELS[entry.mood]}</span>
                  {entry.energy != null && (
                    <span style={styles.logEnergy}>Energy: {entry.energy}/5</span>
                  )}
                  {entry.note && (
                    <span style={styles.logNote}>“{entry.note}”</span>
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}
      </section>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  page: {
    display: 'flex',
    flexDirection: 'column',
    gap: '1.5rem',
  },
  title: {
    margin: 0,
    fontSize: '1.75rem',
    fontWeight: 700,
  },
  subtitle: {
    margin: 0,
    color: 'var(--text-muted)',
    fontSize: '1rem',
  },
  section: {
    background: 'var(--surface)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    padding: '1.5rem',
  },
  sectionTitle: {
    margin: '0 0 1rem',
    fontSize: '1.125rem',
    fontWeight: 600,
  },
  sectionHint: {
    margin: '-0.5rem 0 1rem',
    fontSize: '0.875rem',
    color: 'var(--text-muted)',
  },
  formGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(140px, 1fr))',
    gap: '1rem',
    marginBottom: '1rem',
  },
  label: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.35rem',
    fontSize: '0.875rem',
    fontWeight: 500,
    color: 'var(--text-muted)',
  },
  labelBlock: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.35rem',
    fontSize: '0.875rem',
    fontWeight: 500,
    color: 'var(--text-muted)',
    marginBottom: '1rem',
  },
  input: {
    padding: '0.5rem 0.75rem',
    background: 'var(--bg)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    color: 'var(--text)',
    fontFamily: 'inherit',
    fontSize: '1rem',
  },
  textarea: {
    padding: '0.5rem 0.75rem',
    background: 'var(--bg)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    color: 'var(--text)',
    fontFamily: 'inherit',
    fontSize: '1rem',
    resize: 'vertical',
    minHeight: 80,
  },
  updated: {
    margin: 0,
    fontSize: '0.8rem',
    color: 'var(--text-muted)',
  },
  logForm: {
    display: 'flex',
    flexDirection: 'column',
    gap: '1rem',
    marginBottom: '1.5rem',
  },
  moodRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '0.75rem',
    flexWrap: 'wrap',
  },
  moodLabel: {
    fontSize: '0.875rem',
    fontWeight: 500,
    color: 'var(--text-muted)',
    minWidth: 48,
  },
  moodOptions: {
    display: 'flex',
    gap: '0.35rem',
  },
  moodBtn: {
    width: 36,
    height: 36,
    borderRadius: 'var(--radius)',
    border: '1px solid var(--border)',
    background: 'var(--surface-elevated)',
    color: 'var(--text)',
    fontWeight: 600,
    fontSize: '1rem',
  },
  moodBtnActive: {
    background: 'var(--accent)',
    borderColor: 'var(--accent)',
    color: 'var(--bg)',
  },
  moodValue: {
    fontSize: '0.875rem',
    color: 'var(--text-muted)',
  },
  saveBtn: {
    alignSelf: 'flex-start',
    padding: '0.75rem 1.25rem',
    background: 'var(--accent)',
    color: 'var(--bg)',
    border: 'none',
    borderRadius: 'var(--radius)',
    fontWeight: 600,
    fontSize: '1rem',
  },
  recentLogs: {
    borderTop: '1px solid var(--border)',
    paddingTop: '1rem',
  },
  recentTitle: {
    margin: '0 0 0.75rem',
    fontSize: '0.9375rem',
    fontWeight: 600,
    color: 'var(--text-muted)',
  },
  logList: {
    margin: 0,
    paddingLeft: '1.25rem',
    listStyle: 'none',
  },
  logItem: {
    display: 'flex',
    flexWrap: 'wrap',
    gap: '0.5rem 1rem',
    alignItems: 'baseline',
    marginBottom: '0.5rem',
    fontSize: '0.875rem',
  },
  logDate: {
    fontWeight: 600,
    minWidth: 100,
  },
  logMood: {
    color: 'var(--accent)',
  },
  logEnergy: {
    color: 'var(--text-muted)',
  },
  logNote: {
    color: 'var(--text-muted)',
    fontStyle: 'italic',
  },
}
