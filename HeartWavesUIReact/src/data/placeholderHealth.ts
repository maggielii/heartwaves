import type { HealthSummary } from '../types/health'

// Placeholder until real Apple Health data is uploaded
const last7Dates = Array.from({ length: 7 }, (_, i) => {
  const d = new Date()
  d.setDate(d.getDate() - (6 - i))
  return d.toISOString().slice(0, 10)
})

export const placeholderHealthSummary: HealthSummary = {
  restingHeartRate: {
    mean: 62,
    unit: 'bpm',
    last7Days: last7Dates.map((date, i) => ({
      date,
      value: 58 + Math.round(Math.sin(i) * 6) + (i === 6 ? 8 : 0),
      unit: 'bpm',
    })),
  },
  heartRateVariability: {
    meanMs: 48,
    unit: 'ms',
    last7Days: last7Dates.map((date, i) => ({
      date,
      value: Math.round(42 + Math.sin(i * 0.8) * 12),
      unit: 'ms',
    })),
  },
  standMinutes: {
    mean: 35,
    unit: 'min',
    last7Days: last7Dates.map((date, i) => ({
      date,
      value: Math.round(25 + Math.sin(i * 0.7) * 15),
      unit: 'min',
    })),
  },
  activeMinutes: {
    mean: 28,
    unit: 'min',
    last7Days: last7Dates.map((date, i) => ({
      date,
      value: Math.round(20 + Math.sin(i * 0.6) * 12),
      unit: 'min',
    })),
  },
  lastUpdated: new Date().toISOString(),
}
