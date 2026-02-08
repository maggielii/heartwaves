import { Outlet, NavLink } from 'react-router-dom'

export default function Layout() {
  return (
    <div style={styles.wrapper}>
      <header style={styles.header}>
        <NavLink to="/" style={styles.logo}>
          Health Summary
        </NavLink>
        <nav style={styles.nav}>
          <NavLink
            to="/"
            end
            style={({ isActive }) => ({ ...styles.navLink, ...(isActive ? styles.navLinkActive : {}) })}
          >
            Home
          </NavLink>
          <NavLink
            to="/questions"
            style={({ isActive }) => ({ ...styles.navLink, ...(isActive ? styles.navLinkActive : {}) })}
          >
            Follow-up questions
          </NavLink>
          <NavLink
            to="/report"
            style={({ isActive }) => ({ ...styles.navLink, ...(isActive ? styles.navLinkActive : {}) })}
          >
            Doctor report
          </NavLink>
        </nav>
      </header>
      <main style={styles.main}>
        <Disclaimer />
        <Outlet />
      </main>
    </div>
  )
}

function Disclaimer() {
  return (
    <aside style={styles.disclaimer} role="note">
      <strong>Not a diagnosis.</strong> This tool helps you see patterns in your health data and prepare a summary for your doctor. It does not diagnose conditions. Always discuss your health with a qualified clinician.
    </aside>
  )
}

const styles: Record<string, React.CSSProperties> = {
  wrapper: {
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
  },
  header: {
    background: 'var(--surface)',
    borderBottom: '1px solid var(--border)',
    padding: '1rem 1.5rem',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexWrap: 'wrap',
    gap: '1rem',
  },
  logo: {
    fontSize: '1.25rem',
    fontWeight: 600,
    color: 'var(--text)',
    textDecoration: 'none',
  },
  nav: {
    display: 'flex',
    gap: '1.5rem',
  },
  navLink: {
    color: 'var(--text-muted)',
    textDecoration: 'none',
    fontWeight: 500,
  },
  navLinkActive: {
    color: 'var(--accent)',
  },
  main: {
    flex: 1,
    padding: '1.5rem',
    maxWidth: 960,
    margin: '0 auto',
    width: '100%',
  },
  disclaimer: {
    background: 'var(--surface-elevated)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    padding: '0.75rem 1rem',
    marginBottom: '1.5rem',
    fontSize: '0.875rem',
    color: 'var(--text-muted)',
  },
}
