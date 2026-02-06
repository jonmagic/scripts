/**
 * Week utility functions for Sunday-Saturday week boundaries
 */

/**
 * Get the Sunday date of the week containing the given date
 */
export function getWeekStart(date: Date): Date {
  const d = new Date(date)
  const day = d.getDay()
  // getDay() returns 0 for Sunday, 1 for Monday, etc.
  // Subtract the day number to get back to Sunday
  d.setDate(d.getDate() - day)
  d.setHours(0, 0, 0, 0)
  return d
}

/**
 * Get the Saturday date of the week containing the given date
 */
export function getWeekEnd(date: Date): Date {
  const weekStart = getWeekStart(date)
  const d = new Date(weekStart)
  d.setDate(d.getDate() + 6)
  d.setHours(23, 59, 59, 999)
  return d
}

/**
 * Format a date as YYYY-MM-DD
 */
export function formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}

/**
 * Get the week label for display (e.g., "Week of 2026-02-02")
 */
export function getWeekLabel(weekStart: Date): string {
  return `Week of ${formatDate(weekStart)}`
}

/**
 * Get dates for each day in the week (Sun-Sat)
 */
export function getWeekDays(weekStart: Date): Date[] {
  const days: Date[] = []
  for (let i = 0; i < 7; i++) {
    const d = new Date(weekStart)
    d.setDate(d.getDate() + i)
    d.setHours(0, 0, 0, 0)
    days.push(d)
  }
  return days
}

/**
 * Get day name (e.g., "Monday")
 */
export function getDayName(date: Date): string {
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
  return dayNames[date.getDay()] ?? 'Sunday'
}
