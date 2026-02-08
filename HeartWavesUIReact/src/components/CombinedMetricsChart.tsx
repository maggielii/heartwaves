import type { DailyComposite } from '../utils/healthInsights'

const METRIC_COLORS: Record<keyof DailyComposite['scores'], string> = {
  restingHeartRate: '#d9756d',
  heartRateVariability: '#5ebf9e',
  standMinutes: '#7b9dd4',
  activeMinutes: '#e8b86d',
}

const METRIC_LABELS: Record<keyof DailyComposite['scores'], string> = {
  restingHeartRate: 'Resting HR',
  heartRateVariability: 'HRV',
  standMinutes: 'Stand',
  activeMinutes: 'Active',
}

interface CombinedMetricsChartProps {
  composites: DailyComposite[]
  height?: number
}

export default function CombinedMetricsChart({
  composites,
  height = 220,
}: CombinedMetricsChartProps) {
  if (composites.length === 0) return null

  const today = new Date().toISOString().slice(0, 10)
  const padding = { top: 16, right: 12, bottom: 32, left: 40 }
  const width = 520
  const chartWidth = width - padding.left - padding.right
  const chartHeight = height - padding.top - padding.bottom
  const stepX = composites.length > 1 ? chartWidth / (composites.length - 1) : 0

  const metricKeys = Object.keys(METRIC_COLORS) as (keyof DailyComposite['scores'])[]

  const paths = metricKeys.map((key) => {
    const points = composites.map((c, i) => ({
      x: padding.left + i * stepX,
      y: padding.top + chartHeight - (c.scores[key] / 100) * chartHeight,
      value: c.scores[key],
    }))
    const d = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ')
    return { key, points, d, color: METRIC_COLORS[key] }
  })

  const compositePoints = composites.map((c, i) => ({
    x: padding.left + i * stepX,
    y: padding.top + chartHeight - (c.compositeScore / 100) * chartHeight,
  }))
  const compositeD = compositePoints.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`).join(' ')

  return (
    <div style={{ width: '100%', overflowX: 'auto' }}>
      <svg
        width="100%"
        viewBox={`0 0 ${width} ${height + 24}`}
        preserveAspectRatio="xMidYMid meet"
        style={{ maxWidth: '100%', minWidth: 320 }}
        aria-label="Combined metrics: all four metrics normalized to 0–100 for comparison"
      >
        {/* Y axis labels */}
        {[0, 50, 100].map((v) => {
          const y = padding.top + chartHeight - (v / 100) * chartHeight
          return (
            <g key={v}>
              <line
                x1={padding.left}
                y1={y}
                x2={padding.left - 6}
                y2={y}
                stroke="var(--border)"
                strokeWidth="1"
              />
              <text
                x={padding.left - 10}
                y={y + 4}
                textAnchor="end"
                fontSize="10"
                fill="var(--text-muted)"
              >
                {v}
              </text>
            </g>
          )
        })}
        {/* Grid line at 50 */}
        <line
          x1={padding.left}
          y1={padding.top + chartHeight / 2}
          x2={padding.left + chartWidth}
          y2={padding.top + chartHeight / 2}
          stroke="var(--border)"
          strokeWidth="1"
          strokeDasharray="4 4"
          opacity={0.6}
        />
        {/* Composite (thick, on top) */}
        <path
          d={compositeD}
          fill="none"
          stroke="var(--accent)"
          strokeWidth="3"
          strokeLinecap="round"
          strokeLinejoin="round"
          opacity={0.9}
        />
        {/* Individual metric lines */}
        {paths.map(({ key, d, color }) => (
          <path
            key={key}
            d={d}
            fill="none"
            stroke={color}
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            opacity={0.85}
          />
        ))}
        {/* X labels */}
        {composites.map((c, i) => {
          const x = padding.left + i * stepX
          const label =
            c.date === today
              ? 'Today'
              : new Date(c.date + 'T12:00:00').toLocaleDateString('en-US', {
                  weekday: 'short',
                })
          return (
            <text
              key={c.date}
              x={x}
              y={height - 8}
              textAnchor="middle"
              fontSize="10"
              fill="var(--text-muted)"
            >
              {label}
            </text>
          )
        })}
      </svg>
      {/* Legend */}
      <div style={legendStyle}>
        <span style={{ ...legendItemStyle, color: 'var(--accent)', fontWeight: 700 }}>
          ● Composite
        </span>
        {metricKeys.map((key) => (
          <span key={key} style={{ ...legendItemStyle, color: METRIC_COLORS[key] }}>
            ● {METRIC_LABELS[key]}
          </span>
        ))}
      </div>
      <p style={hintStyle}>
        All metrics normalized 0–100 (higher = better). Composite = average of the four.
      </p>
    </div>
  )
}

const legendStyle: React.CSSProperties = {
  display: 'flex',
  flexWrap: 'wrap',
  gap: '0.75rem 1.25rem',
  marginTop: '0.5rem',
  paddingLeft: 4,
}

const legendItemStyle: React.CSSProperties = {
  fontSize: '0.75rem',
  fontWeight: 500,
}

const hintStyle: React.CSSProperties = {
  margin: '0.5rem 0 0',
  fontSize: '0.7rem',
  color: 'var(--text-muted)',
}
