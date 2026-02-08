import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  type ReactNode,
} from 'react'
import type { PersonalInfo, DailyLogEntry } from '../types/personal'

const STORAGE_KEY_INFO = 'health-app-personal-info'
const STORAGE_KEY_LOGS = 'health-app-daily-logs'

const defaultInfo: PersonalInfo = {
  age: null,
  heightCm: null,
  weightKg: null,
  sex: '',
  recentComments: '',
  lastUpdated: '',
}

function loadInfo(): PersonalInfo {
  try {
    if (typeof localStorage === 'undefined') return defaultInfo
    const raw = localStorage.getItem(STORAGE_KEY_INFO)
    if (!raw) return defaultInfo
    const parsed = JSON.parse(raw) as PersonalInfo
    return { ...defaultInfo, ...parsed }
  } catch {
    return defaultInfo
  }
}

function loadLogs(): DailyLogEntry[] {
  try {
    if (typeof localStorage === 'undefined') return []
    const raw = localStorage.getItem(STORAGE_KEY_LOGS)
    if (!raw) return []
    return JSON.parse(raw) as DailyLogEntry[]
  } catch {
    return []
  }
}

interface PersonalContextValue {
  personalInfo: PersonalInfo
  setPersonalInfo: (info: Partial<PersonalInfo>) => void
  dailyLogs: DailyLogEntry[]
  addOrUpdateLog: (entry: DailyLogEntry) => void
  getLogForDate: (date: string) => DailyLogEntry | undefined
}

const PersonalContext = createContext<PersonalContextValue | null>(null)

export function PersonalProvider({ children }: { children: ReactNode }) {
  const [personalInfo, setInfoState] = useState<PersonalInfo>(loadInfo)
  const [dailyLogs, setDailyLogs] = useState<DailyLogEntry[]>(loadLogs)

  useEffect(() => {
    try {
      if (typeof localStorage !== 'undefined') {
        localStorage.setItem(STORAGE_KEY_INFO, JSON.stringify(personalInfo))
      }
    } catch {
      // ignore
    }
  }, [personalInfo])

  useEffect(() => {
    try {
      if (typeof localStorage !== 'undefined') {
        localStorage.setItem(STORAGE_KEY_LOGS, JSON.stringify(dailyLogs))
      }
    } catch {
      // ignore
    }
  }, [dailyLogs])

  const setPersonalInfo = useCallback((patch: Partial<PersonalInfo>) => {
    setInfoState((prev) => ({
      ...prev,
      ...patch,
      lastUpdated: new Date().toISOString(),
    }))
  }, [])

  const addOrUpdateLog = useCallback((entry: DailyLogEntry) => {
    setDailyLogs((prev) => {
      const rest = prev.filter((e) => e.date !== entry.date)
      return [...rest, entry].sort((a, b) => b.date.localeCompare(a.date))
    })
  }, [])

  const getLogForDate = useCallback(
    (date: string) => dailyLogs.find((e) => e.date === date),
    [dailyLogs]
  )

  const value: PersonalContextValue = {
    personalInfo,
    setPersonalInfo,
    dailyLogs,
    addOrUpdateLog,
    getLogForDate,
  }

  return (
    <PersonalContext.Provider value={value}>
      {children}
    </PersonalContext.Provider>
  )
}

export function usePersonal() {
  const ctx = useContext(PersonalContext)
  if (!ctx) throw new Error('usePersonal must be used within PersonalProvider')
  return ctx
}
