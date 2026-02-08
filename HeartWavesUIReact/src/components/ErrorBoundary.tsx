import { Component, type ErrorInfo, type ReactNode } from 'react'

interface Props {
  children: ReactNode
  fallback?: ReactNode
}

interface State {
  hasError: boolean
  error: Error | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { hasError: false, error: null }

  static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('ErrorBoundary caught:', error, info.componentStack)
  }

  render() {
    if (this.state.hasError && this.state.error) {
      if (this.props.fallback) return this.props.fallback
      return (
        <div style={{ padding: '2rem', maxWidth: 560, margin: '0 auto', fontFamily: 'var(--font-sans)' }}>
          <h2 style={{ color: 'var(--danger)', marginTop: 0 }}>Something went wrong</h2>
          <p style={{ color: 'var(--text)' }}>{this.state.error.message}</p>
          <pre style={{ background: 'var(--surface)', padding: '1rem', borderRadius: 8, overflow: 'auto', fontSize: 12 }}>
            {this.state.error.stack}
          </pre>
          <button
            type="button"
            onClick={() => this.setState({ hasError: false, error: null })}
            style={{
              marginTop: '1rem',
              padding: '0.5rem 1rem',
              background: 'var(--accent)',
              border: 'none',
              borderRadius: 8,
              cursor: 'pointer',
            }}
          >
            Try again
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
