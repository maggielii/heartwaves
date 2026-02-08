const DAYS_TO_SHOW = 14

interface DatePickerStripProps {
  selectedDate: string
  onSelectDate: (date: string) => void
  availableDates: string[]
}

export default function DatePickerStrip({
  selectedDate,
  onSelectDate,
  availableDates,
}: DatePickerStripProps) {
  const today = new Date().toISOString().slice(0, 10)

  const dates = availableDates.length >= DAYS_TO_SHOW
    ? availableDates.slice(-DAYS_TO_SHOW)
    : availableDates

  return (
    <div style={styles.wrapper}>
      <span style={styles.label}>View day</span>
      <div style={styles.strip} role="tablist" aria-label="Select a day to view">
        {dates.map((date) => {
          const d = new Date(date + 'T12:00:00')
          const isSelected = date === selectedDate
          const isToday = date === today
          const label = isToday ? 'Today' : d.toLocaleDateString('en-US', { weekday: 'short' })
          const dayNum = d.getDate()
          const month = d.toLocaleDateString('en-US', { month: 'short' })

          return (
            <button
              key={date}
              type="button"
              role="tab"
              aria-selected={isSelected}
              aria-label={isToday ? `Today, ${month} ${dayNum}` : `${label}, ${month} ${dayNum}`}
              style={{
                ...styles.dayButton,
                ...(isSelected ? styles.dayButtonSelected : {}),
                ...(isToday && !isSelected ? styles.dayButtonToday : {}),
              }}
              onClick={() => onSelectDate(date)}
            >
              <span style={styles.dayLabel}>{label}</span>
              <span style={styles.dayNum}>{dayNum}</span>
              {isToday && <span style={styles.todayBadge}>Today</span>}
            </button>
          )
        })}
      </div>
    </div>
  )
}

const styles: Record<string, React.CSSProperties> = {
  wrapper: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.5rem',
  },
  label: {
    fontSize: '0.75rem',
    fontWeight: 600,
    color: 'var(--text-muted)',
    textTransform: 'uppercase',
    letterSpacing: '0.04em',
  },
  strip: {
    display: 'flex',
    gap: '0.5rem',
    overflowX: 'auto',
    paddingBottom: '4px',
    scrollbarWidth: 'thin',
  },
  dayButton: {
    flexShrink: 0,
    minWidth: 56,
    padding: '0.5rem 0.6rem',
    background: 'var(--surface)',
    border: '1px solid var(--border)',
    borderRadius: 'var(--radius)',
    color: 'var(--text)',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '2px',
    transition: 'border-color 0.15s, background 0.15s',
  },
  dayButtonSelected: {
    background: 'var(--accent)',
    borderColor: 'var(--accent)',
    color: 'var(--bg)',
  },
  dayButtonToday: {
    borderColor: 'var(--accent-dim)',
  },
  dayLabel: {
    fontSize: '0.7rem',
    color: 'inherit',
    opacity: 0.9,
  },
  dayNum: {
    fontSize: '1.125rem',
    fontWeight: 700,
    fontFamily: 'var(--font-mono)',
  },
  todayBadge: {
    fontSize: '0.6rem',
    fontWeight: 600,
    textTransform: 'uppercase',
    letterSpacing: '0.03em',
    opacity: 0.9,
  },
}
