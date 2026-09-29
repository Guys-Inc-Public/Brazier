/** Severity ranking and quiet hours for per-device preferences.
 *  A `severity` label is read case-insensitively; anything unknown or missing counts as warning, so a
 *  device that asks for "critical and up" never hears about a rule whose author forgot the label. */

export const LEVELS = ["info", "warning", "critical", "page"] as const;
export type Level = (typeof LEVELS)[number];

const WORDS: Record<string, Level> = {
  info: "info",
  notice: "info",
  low: "info",
  warning: "warning",
  warn: "warning",
  medium: "warning",
  critical: "critical",
  crit: "critical",
  high: "critical",
  error: "critical",
  page: "page",
  emergency: "page",
};

export function level(severity: string | undefined): Level {
  return WORDS[(severity ?? "").trim().toLowerCase()] ?? "warning";
}

export function rank(l: Level): number {
  return LEVELS.indexOf(l);
}

export function isLevel(v: unknown): v is Level {
  return typeof v === "string" && (LEVELS as readonly string[]).includes(v);
}

/** Does an alert with this severity label clear the device's floor? No floor means everything does. */
export function meets(severity: string | undefined, min: Level | undefined): boolean {
  if (!min) return true;
  return rank(level(severity)) >= rank(min);
}

/** Quiet hours in the device's own zone. Inside the window a push still arrives, silently. */
export interface Quiet {
  start: string;
  end: string;
  /** IANA zone name, "America/Chicago" */
  tz: string;
  /** severity=page still sounds inside the window unless this is false */
  allowPage?: boolean;
}

export const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/;

function minutesOf(hhmm: string): number | null {
  const m = HHMM.exec(hhmm);
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

/** Minutes since local midnight in `tz`, or null when the zone is unknown to the runtime. */
export function localMinutes(tz: string, now: Date): number | null {
  try {
    const parts = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour12: false, hour: "2-digit", minute: "2-digit" }).formatToParts(now);
    const h = Number(parts.find((p) => p.type === "hour")?.value);
    const m = Number(parts.find((p) => p.type === "minute")?.value);
    if (!Number.isFinite(h) || !Number.isFinite(m)) return null;
    return (h % 24) * 60 + m; // some engines print 24 for midnight
  } catch {
    return null;
  }
}

/** True inside the window; the window may cross midnight ("22:00" to "07:00"). A bad time or zone means no window. */
export function inQuietHours(quiet: Quiet | null | undefined, now = new Date()): boolean {
  if (!quiet) return false;
  const start = minutesOf(quiet.start);
  const end = minutesOf(quiet.end);
  if (start === null || end === null || start === end) return false;
  const cur = localMinutes(quiet.tz, now);
  if (cur === null) return false;
  return start < end ? cur >= start && cur < end : cur >= start || cur < end;
}
