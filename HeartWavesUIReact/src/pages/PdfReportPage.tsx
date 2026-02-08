import { Link } from 'react-router-dom'
import { useApp } from '../context/AppContext'
import { reportUrl } from '../api'

export default function PdfReportPage() {
  const app = useApp()
  const hasSession = !!app.sessionId
  const url = hasSession ? reportUrl(app.sessionId) : ''

  return (
    <div style={styles.page}>
      <h1 style={styles.title}>Doctor report</h1>
      <p style={styles.subtitle}>
        Open the clinician-ready report generated from your current session, then print to PDF from your browser.
      </p>

      {!hasSession && (
        <section style={styles.placeholder}>
          <h2 style={styles.sectionTitle}>No session loaded</h2>
          <p style={styles.placeholderText}>
            Upload your Apple Health export on the <Link to="/">Home</Link> page first. The report endpoint requires a valid session.
          </p>
        </section>
      )}

      {hasSession && (
        <>
          <section style={styles.reportBox}>
            <h2 style={styles.sectionTitle}>Open report</h2>
            <p style={styles.placeholderText}>
              Session ID: <code style={styles.code}>{app.sessionId}</code>
            </p>
            <div style={styles.buttonRow}>
              <a href={url} target="_blank" rel="noreferrer" style={styles.primaryLink}>
                Open doctor report
              </a>
              <a href={url} style={styles.secondaryLink}>
                Open in this tab
              </a>
            </div>
            <p style={styles.placeholderText}>
              In Safari/Chrome: File → Print → Save as PDF.
            </p>
          </section>

          <section style={styles.previewBox}>
            <h2 style={styles.sectionTitle}>Preview</h2>
            <iframe title="Doctor report preview" src={url} style={styles.previewFrame} />
          </section>
        </>
      )}

      <p style={styles.footer}>
        After answering <Link to="/questions">follow-up questions</Link>, reopen the report so those answers appear in the summary.
      </p>
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
  placeholder: {
    background: 'var(--surface)',
    border: '1px dashed var(--border)',
    borderRadius: 'var(--radius)',
    padding: '1.25rem',
  },
  reportBox: {
    background: 'var(--surface)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    padding: '1.25rem',
  },
  previewBox: {
    background: 'var(--surface)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    padding: '1.25rem',
  },
  previewFrame: {
    width: '100%',
    minHeight: 640,
    border: '1px solid var(--border)',
    borderRadius: 8,
    background: '#fff',
  },
  sectionTitle: {
    margin: '0 0 1rem',
    fontSize: '1.125rem',
    fontWeight: 600,
  },
  placeholderText: {
    margin: '0 0 0.5rem',
    color: 'var(--text-muted)',
    fontSize: '0.9375rem',
  },
  list: {
    margin: '0.5rem 0 1rem',
    paddingLeft: '1.25rem',
    color: 'var(--text-muted)',
    fontSize: '0.9375rem',
  },
  code: {
    fontFamily: 'var(--font-mono)',
    fontSize: '0.875rem',
    background: 'var(--surface-elevated)',
    padding: '0.15rem 0.4rem',
    borderRadius: 4,
  },
  buttonRow: {
    display: 'flex',
    gap: '0.75rem',
    flexWrap: 'wrap',
    marginBottom: '0.75rem',
  },
  primaryLink: {
    padding: '0.75rem 1.25rem',
    background: 'var(--accent)',
    color: 'var(--bg)',
    border: '1px solid var(--accent)',
    borderRadius: 'var(--radius)',
    fontWeight: 600,
    fontSize: '1rem',
    cursor: 'pointer',
    textDecoration: 'none',
  },
  secondaryLink: {
    padding: '0.75rem 1.25rem',
    background: 'var(--surface-elevated)',
    color: 'var(--text)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    fontWeight: 500,
    fontSize: '0.9375rem',
    textDecoration: 'none',
  },
  footer: {
    margin: 0,
    fontSize: '0.875rem',
    color: 'var(--text-muted)',
  },
}
