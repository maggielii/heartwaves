export interface PersonalInfo {
  age: number | null
  heightCm: number | null
  weightKg: number | null
  sex: '' | 'male' | 'female' | 'other'
  recentComments: string
  lastUpdated: string
}

export interface DailyLogEntry {
  date: string // YYYY-MM-DD
  mood: number // 1-5 or 1-10
  energy: number | null // 1-5 optional
  note: string
}

export const MOOD_LABELS: Record<number, string> = {
  1: 'Very low',
  2: 'Low',
  3: 'Okay',
  4: 'Good',
  5: 'Great',
}

export const MOOD_OPTIONS = [1, 2, 3, 4, 5] as const
