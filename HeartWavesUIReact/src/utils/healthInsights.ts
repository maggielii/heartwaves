import type { HealthSummary } from '../types/health'

export type TrendDirection = 'up' | 'down' | 'stable'

export interface MetricInsight {
  metric: 'restingHeartRate' | 'heartRateVariability' | 'standMinutes' | 'activeMinutes'
  label: string
  trend: TrendDirection
  percentChange: number
  baseline: number
  recentMean: number
  bestDay: { date: string; value: number }
  worstDay: { date: string; value: number }
  tip: string
  tipReason: string
}

// Normalize metric to 0-100 for comparison (higher = better where possible)
function normalizeScore(
  metric: keyof Omit<HealthSummary, 'lastUpdated'>,
  value: number
): number {
  switch (metric) {
    case 'restingHeartRate':
      if (value <= 50) return 100
      if (value >= 90) return 0
      return Math.round(100 - ((value - 50) / 40) * 100)
    case 'heartRateVariability':
      if (value >= 60) return 100
      if (value <= 15) return 0
      return Math.round(((value - 15) / 45) * 100)
    case 'standMinutes':
      // 30+ min/day is good, 0 is bad
      if (value >= 30) return 100
      return Math.min(100, Math.round((value / 30) * 100))
    case 'activeMinutes':
      // 30+ min/day is great (WHO recommendation)
      if (value >= 30) return 100
      return Math.min(100, Math.round((value / 30) * 100))
    default:
      return 50
  }
}

export interface DailyComposite {
  date: string
  restingHeartRate: number
  heartRateVariability: number
  standMinutes: number
  activeMinutes: number
  compositeScore: number
  scores: { restingHeartRate: number; heartRateVariability: number; standMinutes: number; activeMinutes: number }
}

export function computeDailyComposites(data: HealthSummary): DailyComposite[] {
  const dates = data.restingHeartRate.last7Days.map((d) => d.date)
  return dates.map((date) => {
    const hr = data.restingHeartRate.last7Days.find((d) => d.date === date)?.value ?? 0
    const hrv = data.heartRateVariability.last7Days.find((d) => d.date === date)?.value ?? 0
    const stand = data.standMinutes.last7Days.find((d) => d.date === date)?.value ?? 0
    const active = data.activeMinutes.last7Days.find((d) => d.date === date)?.value ?? 0
    const scores = {
      restingHeartRate: normalizeScore('restingHeartRate', hr),
      heartRateVariability: normalizeScore('heartRateVariability', hrv),
      standMinutes: normalizeScore('standMinutes', stand),
      activeMinutes: normalizeScore('activeMinutes', active),
    }
    const compositeScore = Math.round(
      (scores.restingHeartRate + scores.heartRateVariability + scores.standMinutes + scores.activeMinutes) / 4
    )
    return {
      date,
      restingHeartRate: hr,
      heartRateVariability: hrv,
      standMinutes: stand,
      activeMinutes: active,
      compositeScore,
      scores,
    }
  })
}

function trendDirection(values: number[]): { direction: TrendDirection; percentChange: number } {
  if (values.length < 2) return { direction: 'stable', percentChange: 0 }
  const firstHalf = values.slice(0, Math.floor(values.length / 2))
  const secondHalf = values.slice(Math.ceil(values.length / 2))
  const early = firstHalf.reduce((a, b) => a + b, 0) / firstHalf.length
  const late = secondHalf.reduce((a, b) => a + b, 0) / secondHalf.length
  const percentChange = early === 0 ? 0 : ((late - early) / early) * 100
  if (Math.abs(percentChange) < 3) return { direction: 'stable', percentChange }
  return {
    direction: percentChange > 0 ? 'up' : 'down',
    percentChange,
  }
}

export function computeMetricInsights(data: HealthSummary): MetricInsight[] {
  const metrics: {
    metric: MetricInsight['metric']
    label: string
    series: { date: string; value: number }[]
    lowerIsBetter: boolean
  }[] = [
    {
      metric: 'restingHeartRate',
      label: 'Resting heart rate',
      series: data.restingHeartRate.last7Days.map((d) => ({ date: d.date, value: d.value })),
      lowerIsBetter: true,
    },
    {
      metric: 'heartRateVariability',
      label: 'Heart rate variability',
      series: data.heartRateVariability.last7Days.map((d) => ({ date: d.date, value: d.value })),
      lowerIsBetter: false,
    },
    {
      metric: 'standMinutes',
      label: 'Stand minutes',
      series: data.standMinutes.last7Days.map((d) => ({ date: d.date, value: d.value })),
      lowerIsBetter: false,
    },
    {
      metric: 'activeMinutes',
      label: 'Active minutes',
      series: data.activeMinutes.last7Days.map((d) => ({ date: d.date, value: d.value })),
      lowerIsBetter: false,
    },
  ]

  return metrics.map((m) => {
    const values = m.series.map((s) => s.value)
    const { direction, percentChange } = trendDirection(values)
    const baseline = values.length >= 5
      ? values.slice(0, 5).reduce((a, b) => a + b, 0) / 5
      : values[0] ?? 0
    const recentMean = values.length >= 3
      ? values.slice(-3).reduce((a, b) => a + b, 0) / 3
      : values[values.length - 1] ?? 0
    const bestIdx = m.lowerIsBetter
      ? values.indexOf(Math.min(...values))
      : values.indexOf(Math.max(...values))
    const worstIdx = m.lowerIsBetter
      ? values.indexOf(Math.max(...values))
      : values.indexOf(Math.min(...values))
    const bestDay = m.series[bestIdx]
      ? { date: m.series[bestIdx].date, value: m.series[bestIdx].value }
      : { date: m.series[0]?.date ?? '', value: 0 }
    const worstDay = m.series[worstIdx]
      ? { date: m.series[worstIdx].date, value: m.series[worstIdx].value }
      : { date: m.series[0]?.date ?? '', value: 0 }

    let tip: string
    let tipReason: string

    switch (m.metric) {
      case 'restingHeartRate':
        if (direction === 'up' && percentChange > 5) {
          tip = 'Consider stress, sleep, and caffeine \u2014 they can nudge resting HR up.'
          tipReason = `Resting HR is up ~${Math.abs(percentChange).toFixed(0)}% vs your earlier week.`
        } else if (recentMean > 65) {
          tip = 'Resting HR is on the higher side. Good sleep and consistent activity often help.'
          tipReason = `7-day average is ${recentMean.toFixed(0)} bpm.`
        } else {
          tip = 'Resting HR looks in a good range. Keep up your usual habits.'
          tipReason = `Best day this week: ${bestDay.value} bpm.`
        }
        break
      case 'heartRateVariability':
        if (direction === 'down' && percentChange < -8) {
          tip = 'HRV has dipped \u2014 focus on recovery, sleep, and avoiding overtraining.'
          tipReason = `HRV down ~${Math.abs(percentChange).toFixed(0)}% over the week.`
        } else if (recentMean < 35) {
          tip = 'HRV is lower than typical. Consistency in sleep and routine can help.'
          tipReason = `Recent average ${recentMean.toFixed(0)} ms.`
        } else {
          tip = 'HRV is in a healthy range. Variability is normal day to day.'
          tipReason = `Your best day was ${bestDay.value} ms.`
        }
        break
      case 'standMinutes':
        if (recentMean < 15) {
          tip = 'Try to break up sitting with short standing breaks throughout the day.'
          tipReason = `Average this week: ${recentMean.toFixed(0)} min.`
        } else if (direction === 'down' && percentChange < -10) {
          tip = 'Standing time has dropped this week. Even brief stand breaks add up.'
          tipReason = `Down ~${Math.abs(percentChange).toFixed(0)}% vs start of week.`
        } else {
          tip = 'Standing time is in a good range. Keep moving throughout the day.'
          tipReason = `Best day: ${bestDay.value} min.`
        }
        break
      case 'activeMinutes':
        if (recentMean < 15) {
          tip = 'Adding short walks or light activity can boost active minutes easily.'
          tipReason = `Recent average ~${Math.round(recentMean)} min.`
        } else if (direction === 'down' && percentChange < -10) {
          tip = 'Active minutes have dropped. Even small increases make a difference.'
          tipReason = `Down ~${Math.abs(percentChange).toFixed(0)}% vs start of week.`
        } else {
          tip = 'Activity level is looking good. Consistency is key.'
          tipReason = `Best day: ${bestDay.value} min.`
        }
        break
      default:
        tip = 'Track over time and share trends with your doctor if you have concerns.'
        tipReason = ''
    }

    return {
      metric: m.metric,
      label: m.label,
      trend: direction,
      percentChange,
      baseline,
      recentMean,
      bestDay,
      worstDay,
      tip,
      tipReason,
    }
  })
}

export function getCrossMetricInsight(composites: DailyComposite[]): string {
  if (composites.length < 3) return ''
  const lowActivityDays = composites.filter((c) => c.activeMinutes < 15)
  const highHrDays = composites.filter((c) => c.restingHeartRate > composites.reduce((a, b) => a + b.restingHeartRate, 0) / composites.length)
  const sameDay = lowActivityDays.some((d) => highHrDays.some((h) => h.date === d.date))
  if (sameDay && lowActivityDays.length >= 1) {
    return 'On low-activity days, your resting heart rate tended higher \u2014 activity and HR often move together.'
  }
  const scoreTrend = composites[composites.length - 1].compositeScore - composites[0].compositeScore
  if (scoreTrend > 10) return 'Your overall pattern improved over the week \u2014 rest and activity are aligning well.'
  if (scoreTrend < -10) return 'Your combined metrics dipped this week \u2014 worth keeping an eye on recovery.'
  return 'Metrics are moving in a mixed pattern; no single factor stands out.'
}
