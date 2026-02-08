import { useId } from 'react'
import type { DailyMetric } from '../types/health'

interface LineChartProps {
  data: DailyMetric[]
  valueLabel: string
  selectedDate: string | null
  onSelectDate?: (date: string) => void
  height?: number
  accentColor?: string
}

export default function LineChart({
  data,
  valueLabel,
  selectedDate,
  onSelectDate,
  height = 120,
  accentColor = 'var(--accent)',
}: LineChartProps) {
  const gradientId = useId().replace(/:/g, '-')
  if (data.length === 0) return null

  const values = data.map((d) => d.value)
  const min = Math.min(...values)
  const max = Math.max(...values)
  const range = max - min || 1
  const padding = { top: 8, right: 8, bottom: 24, left: 36 }
  const width = 280
  const chartWidth = width - padding.left - padding.right
  const chartHeight = height - padding.top - padding.bottom
  const stepX = data.length > 1 ? chartWidth / (data.length - 1) : 0

  const points = data.map((d, i) => {
    const x = padding.left + i * stepX
    const y = padding.top + chartHeight - ((d.value - min) / range) * chartHeight
    return { ...d, x, y }
  })

  const pathD = points
    .map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x} ${p.y}`)
    .join(' ')

  const today = new Date().toISOString().slice(0, 10)

  return (
    <svg
      width="100%"
      viewBox={`0 0 ${width} ${height}`}
      preserveAspectRatio="xMidYMid meet"
      style={{ maxWidth: width, height }}
      role="img"
      aria-label={`Line chart: ${valueLabel} over last ${data.length} days`}
    >
      <defs>
        <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={accentColor} stopOpacity={0.3} />
          <stop offset="100%" stopColor={accentColor} stopOpacity={0} />
        </linearGradient>
      </defs>
      {/* Area fill under line */}
      {pathD && (
        <path
          d={`${pathD} L ${points[points.length - 1].x} ${padding.top + chartHeight} L ${points[0].x} ${padding.top + chartHeight} Z`}
          fill={`url(#${gradientId})`}
        />
      )}
      {/* Line */}
      <path
        d={pathD}
        fill="none"
        stroke={accentColor}
        strokeWidth="2"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      {/* Points: highlight selected or today */}
      {points.map((p) => {
        const isSelected = selectedDate === p.date
        const isToday = p.date === today
        const showPoint = isSelected || isToday || data.length <= 7
        if (!showPoint) return null
        return (
          <g key={p.date}>
            <circle
              cx={p.x}
              cy={p.y}
              r={isSelected || isToday ? 6 : 4}
              fill="var(--bg)"
              stroke={isSelected ? 'var(--accent)' : isToday ? 'var(--warning)' : 'var(--border)'}
              strokeWidth={isSelected || isToday ? 2.5 : 1.5}
              style={onSelectDate ? { cursor: 'pointer' } : undefined}
              onClick={() => onSelectDate?.(p.date)}
              aria-label={`${p.date}: ${p.value} ${valueLabel}`}
            />
          </g>
        )
      })}
      {/* X labels: short day labels */}
      {data.map((d, i) => {
        const x = padding.left + i * stepX
        const label = (() => {
          const dt = new Date(d.date)
          const isToday = d.date === today
          if (isToday) return 'Today'
          return dt.toLocaleDateString('en-US', { weekday: 'short', month: 'numeric', day: 'numeric' }).replace(/^(\w+),?\s*/, '$1 ')
        })()
        return (
          <text
            key={d.date}
            x={x}
            y={height - 6}
            textAnchor="middle"
            fontSize="10"
            fill="var(--text-muted)"
          >
            {label}
          </text>
        )
      })}
    </svg>
  )
}
