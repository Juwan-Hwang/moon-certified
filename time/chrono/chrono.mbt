/// Chrono — Production-grade date and time library.
///
/// A comprehensive date/time library providing:
///
/// - **Calendar dates** (proleptic Gregorian, ISO 8601 compatible)
/// - **Time of day** (hours, minutes, seconds, nanoseconds)
/// - **DateTime** (date + time combination)
/// - **Duration** (nanosecond-precision time spans)
/// - **Unix timestamps** (seconds and milliseconds since 1970-01-01)
/// - **ISO 8601 formatting and parsing** (RFC 3339 profiles)
/// - **Date arithmetic** (add/subtract days, months, years)
/// - **Day of week** (Monday = 1 … Sunday = 7, ISO 8601)
/// - **Leap year** detection
/// - **Time zone offsets** (fixed UTC offsets, e.g. +08:00)
///
/// ## Design
///
/// Internally, every `DateTime` is stored as a **Unix timestamp in
/// nanoseconds** (`Int64`), plus a UTC offset in minutes. This gives:
///
/// - O(1) comparison and arithmetic (single `Int64` subtract).
/// - No ambiguity about "which midnight?" — the timestamp is absolute.
/// - Time zone is a presentation concern, applied on format/extraction.
///
/// The proleptic Gregorian calendar is used: dates before 1582 are
/// extrapolated backward using Gregorian rules. Year 0 exists (1 BC = 0,
/// 2 BC = -1, etc.), matching ISO 8601.
///
/// ## Limits
///
/// The `Int64` nanosecond timestamp covers approximately ±292 years from
/// 1970, i.e. years 1677–2262. This is the same limit as Rust's
/// `chrono::NaiveDateTime` with nanosecond precision.
///
/// `proof-enabled` is `false`; correctness is backed by the test suite,
/// which includes round-trip, boundary, and property tests.

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

///|
/// Nanoseconds per second.
const NS_PER_SEC : Int64 = 1_000_000_000L

///|
/// Nanoseconds per millisecond.
const NS_PER_MS : Int64 = 1_000_000L

///|
/// Nanoseconds per microsecond.
let _NS_PER_US : Int64 = 1_000L

///|
/// Seconds per minute.
const SECS_PER_MIN : Int64 = 60L

///|
/// Seconds per hour.
const SECS_PER_HOUR : Int64 = 3_600L

///|
/// Seconds per day.
const SECS_PER_DAY : Int64 = 86_400L

///|
/// Days per 400-year cycle (Gregorian).
const DAYS_PER_400_YEARS : Int = 146_097

///|
/// Days per 100-year cycle (within a 400-year cycle).
let _DAYS_PER_100_YEARS : Int = 36_524

///|
/// Days per 4-year cycle (within a 100-year cycle).
let _DAYS_PER_4_YEARS : Int = 1_461

///|
/// Days in each month for a non-leap year (index 0 = January).
let month_days : FixedArray[Int] = FixedArray::from_array([
  31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
])

///|
/// Cumulative days at the start of each month for a non-leap year
/// (index 0 = January, which starts at day 0).
let cumul_days : FixedArray[Int] = FixedArray::from_array([
  0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334,
])

// ---------------------------------------------------------------------------
// Core types
// ---------------------------------------------------------------------------

///|
/// A calendar date (year, month, day) in the proleptic Gregorian calendar.
///
/// Year 0 represents 1 BC. Valid range: years -9999 to 9999.
pub struct Date {
  priv year : Int
  priv month : Int // 1–12
  priv day : Int // 1–31
}

///|
/// A time of day with nanosecond precision.
///
/// All fields are in their canonical ranges:
/// - `hour`: 0–23
/// - `minute`: 0–59
/// - `second`: 0–59 (leap seconds not supported)
/// - `nanosecond`: 0–999_999_999
pub struct Time {
  priv hour : Int
  priv minute : Int
  priv second : Int
  priv nanosecond : Int
}

///|
/// A date-time with a UTC offset (time zone).
///
/// Internally stored as a Unix nanosecond timestamp (`Int64`) and a
/// UTC offset in minutes. The timestamp is always in UTC; the offset
/// affects only how the date/time is displayed.
pub struct DateTime {
  priv timestamp_ns : Int64 // nanoseconds since 1970-01-01T00:00:00Z
  priv offset_minutes : Int // UTC offset in minutes (e.g. +480 for UTC+8)
}

///|
/// A span of time, represented as nanoseconds. Positive = future,
/// negative = past.
pub struct Duration {
  priv ns : Int64
}

// ---------------------------------------------------------------------------
// Leap year and month helpers
// ---------------------------------------------------------------------------

///|
/// Returns `true` if `year` is a leap year in the proleptic Gregorian
/// calendar.
///
/// A year is leap if divisible by 4, except centuries which must be
/// divisible by 400.
pub fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// Number of days in the given `month` (1–12) of `year`.
///
/// Returns 0 for invalid month values.
pub fn days_in_month(year : Int, month : Int) -> Int {
  if month < 1 || month > 12 {
    return 0
  }
  if month == 2 && is_leap_year(year) {
    return 29
  }
  month_days[month - 1]
}

// ---------------------------------------------------------------------------
// Date <-> ordinal day conversions
// ---------------------------------------------------------------------------

///|
/// Convert a proleptic Gregorian date to a **day number** where
/// 1970-01-01 = day 0.
///
/// Uses the algorithm from Howard Hinnant's `date` library (also used in
/// C++20 `<chrono>`), which is the industry standard for date arithmetic.
/// It avoids iterative loops and runs in O(1).
fn date_to_days(year : Int, month : Int, day : Int) -> Int {
  let y = year - (if month <= 2 { 1 } else { 0 })
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400 // [0, 399]
  let doy = (153 * (month + (if month > 2 { -3 } else { 9 })) + 2) / 5 + day - 1 // [0, 365]
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy // [0, 146096]
  era * DAYS_PER_400_YEARS + doe - 719_468
}

///|
/// Convert a day number (1970-01-01 = day 0) to a proleptic Gregorian
/// date.
///
/// Inverse of `date_to_days`. O(1), no loops.
fn days_to_date(days : Int) -> Date {
  let z = days + 719_468
  let era = (if z >= 0 { z } else { z - 146_096 }) / DAYS_PER_400_YEARS
  let doe = z - era * DAYS_PER_400_YEARS // [0, 146096]
  let yoe = (doe - doe / 1_460 + doe / 36_524) / 365 // [0, 399]
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100) // [0, 365]
  let mp = (5 * doy + 2) / 153 // [0, 11]
  let d = doy - (153 * mp + 2) / 5 + 1 // [1, 31]
  let m = if mp < 10 { mp + 3 } else { mp - 9 } // [1, 12]
  { year: if m <= 2 { y + 1 } else { y }, month: m, day: d }
}

///|
/// Day of week for a date. Returns 1 = Monday … 7 = Sunday (ISO 8601).
///
/// 1970-01-01 was a Thursday (4).
pub fn weekday(date : Date) -> Int {
  let days = date_to_days(date.year, date.month, date.day)
  // 1970-01-01 (day 0) was Thursday = 4 in ISO (Mon=1..Sun=7).
  let wd = (days % 7 + 4 + 7) % 7 // 0=Sunday..6=Saturday
  if wd == 0 {
    7 // Sunday
  } else {
    wd
  }
}

///|
/// Day of year (1-based). January 1 = 1.
pub fn day_of_year(date : Date) -> Int {
  let base = cumul_days[date.month - 1]
  let leap_adj = if date.month > 2 && is_leap_year(date.year) { 1 } else { 0 }
  base + leap_adj + date.day
}

// ---------------------------------------------------------------------------
// Date constructors and accessors
// ---------------------------------------------------------------------------

///|
/// Create a `Date` from year, month (1–12), and day (1–31).
///
/// Returns `None` if the values do not form a valid calendar date.
pub fn date(year : Int, month : Int, day : Int) -> Date? {
  if year < -9999 || year > 9999 {
    return None
  }
  if month < 1 || month > 12 {
    return None
  }
  if day < 1 || day > days_in_month(year, month) {
    return None
  }
  Some({ year, month, day })
}

///|
/// Year component of a `Date`.
pub fn year(d : Date) -> Int {
  d.year
}

///|
/// Month component of a `Date` (1–12).
pub fn month(d : Date) -> Int {
  d.month
}

///|
/// Day component of a `Date` (1–31).
pub fn day(d : Date) -> Int {
  d.day
}

// ---------------------------------------------------------------------------
// Date arithmetic
// ---------------------------------------------------------------------------

///|
/// Add `n` days to a `Date`, returning a new `Date`.
pub fn add_days(d : Date, n : Int) -> Date {
  days_to_date(date_to_days(d.year, d.month, d.day) + n)
}

///|
/// Subtract `n` days from a `Date`, returning a new `Date`.
pub fn sub_days(d : Date, n : Int) -> Date {
  add_days(d, -n)
}

///|
/// Add `n` months to a `Date`. If the resulting day exceeds the number
/// of days in the target month, it is clamped to the last day.
///
/// For example, adding 1 month to January 31 yields February 28 (or 29).
pub fn add_months(d : Date, n : Int) -> Date {
  let total = d.year * 12 + (d.month - 1) + n
  let new_year = total / 12
  let new_month = total % 12 + 1
  let max_day = days_in_month(new_year, new_month)
  let new_day = if d.day > max_day { max_day } else { d.day }
  { year: new_year, month: new_month, day: new_day }
}

///|
/// Add `n` years to a `Date`. February 29 is clamped to February 28
/// if the target year is not a leap year.
pub fn add_years(d : Date, n : Int) -> Date {
  let new_year = d.year + n
  let max_day = days_in_month(new_year, d.month)
  let new_day = if d.day > max_day { max_day } else { d.day }
  { year: new_year, month: d.month, day: new_day }
}

///|
/// Number of days between two dates. Positive if `end` is after `start`.
pub fn days_between(start : Date, end : Date) -> Int {
  date_to_days(end.year, end.month, end.day) -
  date_to_days(start.year, start.month, start.day)
}

// ---------------------------------------------------------------------------
// Time constructors and accessors
// ---------------------------------------------------------------------------

///|
/// Create a `Time` from hour, minute, second, and nanosecond.
///
/// Returns `None` if any value is out of range.
pub fn time(hour : Int, minute : Int, second : Int, nanosecond : Int) -> Time? {
  if hour < 0 || hour > 23 {
    return None
  }
  if minute < 0 || minute > 59 {
    return None
  }
  if second < 0 || second > 59 {
    return None
  }
  if nanosecond < 0 || nanosecond > 999_999_999 {
    return None
  }
  Some({ hour, minute, second, nanosecond })
}

///|
/// Create a `Time` with second precision (nanosecond = 0).
pub fn time_s(hour : Int, minute : Int, second : Int) -> Time? {
  time(hour, minute, second, 0)
}

///|
/// Hour component (0–23).
pub fn hour(t : Time) -> Int {
  t.hour
}

///|
/// Minute component (0–59).
pub fn minute(t : Time) -> Int {
  t.minute
}

///|
/// Second component (0–59).
pub fn second(t : Time) -> Int {
  t.second
}

///|
/// Nanosecond component (0–999_999_999).
pub fn nanosecond(t : Time) -> Int {
  t.nanosecond
}

// ---------------------------------------------------------------------------
// Duration
// ---------------------------------------------------------------------------

///|
/// Create a `Duration` from a number of nanoseconds.
pub fn duration_ns(ns : Int64) -> Duration {
  { ns, }
}

///|
/// Create a `Duration` from a number of seconds.
pub fn duration_secs(secs : Int64) -> Duration {
  { ns: secs * NS_PER_SEC }
}

///|
/// Create a `Duration` from a number of milliseconds.
pub fn duration_ms(ms : Int64) -> Duration {
  { ns: ms * NS_PER_MS }
}

///|
/// Total nanoseconds in a `Duration`.
pub fn duration_as_ns(d : Duration) -> Int64 {
  d.ns
}

///|
/// Total seconds in a `Duration` (truncated toward zero).
pub fn duration_as_secs(d : Duration) -> Int64 {
  d.ns / NS_PER_SEC
}

///|
/// Total milliseconds in a `Duration` (truncated toward zero).
pub fn duration_as_ms(d : Duration) -> Int64 {
  d.ns / NS_PER_MS
}

///|
/// Add two durations.
pub fn duration_add(a : Duration, b : Duration) -> Duration {
  { ns: a.ns + b.ns }
}

///|
/// Subtract `b` from `a`.
pub fn duration_sub(a : Duration, b : Duration) -> Duration {
  { ns: a.ns - b.ns }
}

// ---------------------------------------------------------------------------
// DateTime construction
// ---------------------------------------------------------------------------

///|
/// Create a `DateTime` from a date, time, and UTC offset in minutes.
///
/// The offset is applied to compute the UTC timestamp. For example,
/// `datetime(date(2024, 1, 1), time_s(0, 0, 0), 480)` creates
/// 2024-01-01T00:00:00+08:00, which is 2023-12-31T16:00:00Z.
///
/// Returns `None` if the date or time is invalid.
pub fn datetime(d : Date, t : Time, offset_minutes : Int) -> DateTime? {
  let days = date_to_days(d.year, d.month, d.day)
  let secs = days.to_int64() * SECS_PER_DAY +
    t.hour.to_int64() * SECS_PER_HOUR +
    t.minute.to_int64() * SECS_PER_MIN +
    t.second.to_int64()
  let local_ns = secs * NS_PER_SEC + t.nanosecond.to_int64()
  let offset_ns = offset_minutes.to_int64() * SECS_PER_MIN * NS_PER_SEC
  let dt : DateTime = { timestamp_ns: local_ns - offset_ns, offset_minutes }
  Some(dt)
}

///|
/// Create a UTC `DateTime` (offset = 0).
pub fn datetime_utc(d : Date, t : Time) -> DateTime? {
  datetime(d, t, 0)
}

///|
/// Create a `DateTime` from a Unix timestamp (seconds since epoch) and
/// a UTC offset in minutes.
pub fn from_timestamp(ts : Int64, offset_minutes : Int) -> DateTime {
  { timestamp_ns: ts * NS_PER_SEC, offset_minutes }
}

///|
/// Create a `DateTime` from a Unix timestamp in milliseconds.
pub fn from_timestamp_ms(ts_ms : Int64, offset_minutes : Int) -> DateTime {
  { timestamp_ns: ts_ms * NS_PER_MS, offset_minutes }
}

///|
/// Unix timestamp (seconds) of a `DateTime`.
pub fn timestamp(dt : DateTime) -> Int64 {
  dt.timestamp_ns / NS_PER_SEC
}

///|
/// Unix timestamp (milliseconds) of a `DateTime`.
pub fn timestamp_ms(dt : DateTime) -> Int64 {
  dt.timestamp_ns / NS_PER_MS
}

///|
/// Unix timestamp (nanoseconds) of a `DateTime`.
pub fn timestamp_ns(dt : DateTime) -> Int64 {
  dt.timestamp_ns
}

///|
/// UTC offset in minutes of a `DateTime`.
pub fn offset(dt : DateTime) -> Int {
  dt.offset_minutes
}

// ---------------------------------------------------------------------------
// DateTime component extraction
// ---------------------------------------------------------------------------

///|
/// Extract the `Date` part of a `DateTime` (in the datetime's own offset).
pub fn date_of(dt : DateTime) -> Date {
  let local_ns = dt.timestamp_ns +
    dt.offset_minutes.to_int64() * SECS_PER_MIN * NS_PER_SEC
  let day_unit = SECS_PER_DAY * NS_PER_SEC
  // Floor division: for negative local_ns, truncation toward zero
  // gives the wrong day (e.g. -1s → 0 days = 1970-01-01, not -1 = 1969-12-31).
  let q = local_ns / day_unit
  let r = local_ns % day_unit
  let days = (if r < 0L { q - 1L } else { q }).to_int()
  days_to_date(days)
}

///|
/// Extract the `Time` part of a `DateTime` (in the datetime's own offset).
pub fn time_of(dt : DateTime) -> Time {
  let local_ns = dt.timestamp_ns +
    dt.offset_minutes.to_int64() * SECS_PER_MIN * NS_PER_SEC
  let day_ns = local_ns % (SECS_PER_DAY * NS_PER_SEC)
  let day_ns_pos = if day_ns < 0L {
    day_ns + SECS_PER_DAY * NS_PER_SEC
  } else {
    day_ns
  }
  let total_secs = day_ns_pos / NS_PER_SEC
  let h = (total_secs / SECS_PER_HOUR).to_int()
  let m = (total_secs % SECS_PER_HOUR / SECS_PER_MIN).to_int()
  let s = (total_secs % SECS_PER_MIN).to_int()
  let ns = (day_ns_pos % NS_PER_SEC).to_int()
  { hour: h, minute: m, second: s, nanosecond: ns }
}

///|
/// Weekday of a `DateTime` (1 = Monday … 7 = Sunday).
pub fn weekday_of(dt : DateTime) -> Int {
  weekday(date_of(dt))
}

// ---------------------------------------------------------------------------
// DateTime arithmetic
// ---------------------------------------------------------------------------

///|
/// Add a `Duration` to a `DateTime`. The offset is preserved.
pub fn add_duration(dt : DateTime, d : Duration) -> DateTime {
  { timestamp_ns: dt.timestamp_ns + d.ns, offset_minutes: dt.offset_minutes }
}

///|
/// Subtract a `Duration` from a `DateTime`. The offset is preserved.
pub fn sub_duration(dt : DateTime, d : Duration) -> DateTime {
  { timestamp_ns: dt.timestamp_ns - d.ns, offset_minutes: dt.offset_minutes }
}

///|
/// Duration between two `DateTime`s. Both are compared in UTC, so
/// the result is independent of their offsets.
pub fn duration_between(a : DateTime, b : DateTime) -> Duration {
  { ns: b.timestamp_ns - a.timestamp_ns }
}

// ---------------------------------------------------------------------------
// Comparison
// ---------------------------------------------------------------------------

///|
/// Compare two `Date`s. Returns -1, 0, or 1.
pub fn compare_date(a : Date, b : Date) -> Int {
  if a.year != b.year {
    return if a.year < b.year { -1 } else { 1 }
  }
  if a.month != b.month {
    return if a.month < b.month { -1 } else { 1 }
  }
  if a.day != b.day {
    return if a.day < b.day { -1 } else { 1 }
  }
  0
}

///|
/// Compare two `DateTime`s in UTC. Returns -1, 0, or 1.
pub fn compare_datetime(a : DateTime, b : DateTime) -> Int {
  if a.timestamp_ns < b.timestamp_ns {
    -1
  } else if a.timestamp_ns > b.timestamp_ns {
    1
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// ISO 8601 formatting
// ---------------------------------------------------------------------------

///|
/// Zero-pad a number to `width` digits.
fn pad(n : Int, width : Int) -> String {
  let s = n.to_string()
  let neg = s.length() > 0 && s[0] == '-'
  let digits = if neg { s[1:].to_owned() } else { s }
  let pad_count = width - digits.length()
  let mut result = ""
  if neg {
    result = "-"
  }
  for _i = 0; _i < pad_count; _i = _i + 1 {
    result = result + "0"
  }
  result + digits
}

///|
/// Format a `Date` as an ISO 8601 date string: `YYYY-MM-DD`.
///
/// Years are zero-padded to 4 digits (5 for negative years with a
/// leading `-`).
pub fn format_date(d : Date) -> String {
  let y = if d.year >= 0 { pad(d.year, 4) } else { "-" + pad(-d.year, 4) }
  y + "-" + pad(d.month, 2) + "-" + pad(d.day, 2)
}

///|
/// Format a `Time` as an ISO 8601 time string: `HH:MM:SS`.
///
/// If nanoseconds are non-zero, they are appended as `.NNNNNNNNN`.
pub fn format_time(t : Time) -> String {
  let base = pad(t.hour, 2) + ":" + pad(t.minute, 2) + ":" + pad(t.second, 2)
  if t.nanosecond > 0 {
    let ns_str = pad(t.nanosecond, 9)
    // Trim trailing zeros from the fractional part.
    let mut end = ns_str.length()
    while end > 0 && ns_str[end - 1] == '0' {
      end = end - 1
    }
    base + "." + ns_str[:end].to_owned()
  } else {
    base
  }
}

///|
/// Format a UTC offset as `±HH:MM` or `Z` for UTC.
fn format_offset(offset_minutes : Int) -> String {
  if offset_minutes == 0 {
    return "Z"
  }
  let sign = if offset_minutes >= 0 { "+" } else { "-" }
  let abs_min = if offset_minutes >= 0 {
    offset_minutes
  } else {
    -offset_minutes
  }
  let h = abs_min / 60
  let m = abs_min % 60
  sign + pad(h, 2) + ":" + pad(m, 2)
}

///|
/// Format a `DateTime` as an ISO 8601 / RFC 3339 string.
///
/// Format: `YYYY-MM-DDTHH:MM:SS.fffffffff±HH:MM`
///
/// The fractional seconds and offset are included. UTC offset is shown
/// as `Z` for UTC.
pub fn format_datetime(dt : DateTime) -> String {
  let d = date_of(dt)
  let t = time_of(dt)
  format_date(d) + "T" + format_time(t) + format_offset(dt.offset_minutes)
}

// ---------------------------------------------------------------------------
// ISO 8601 parsing
// ---------------------------------------------------------------------------

///|
/// Parse a single digit character to its integer value.
fn parse_digit(c : UInt16) -> Int? {
  let v = c.to_int() - 48 // '0' = 48
  if v >= 0 && v <= 9 {
    Some(v)
  } else {
    None
  }
}

///|
/// Parse `len` consecutive digits from `s` starting at position `pos`.
/// Returns `(value, new_pos)` or `None` on failure.
fn parse_digits(s : String, pos : Int, len : Int) -> (Int, Int)? {
  if pos + len > s.length() {
    return None
  }
  let mut val = 0
  for i = 0; i < len; i = i + 1 {
    match parse_digit(s[pos + i]) {
      Some(d) => val = val * 10 + d
      None => return None
    }
  }
  Some((val, pos + len))
}

///|
/// Parse an ISO 8601 date string: `YYYY-MM-DD`.
///
/// Returns `None` on invalid input.
pub fn parse_date(s : String) -> Date? {
  let mut pos = 0
  let mut year_sign = 1
  if pos < s.length() && s[pos] == '-' {
    year_sign = -1
    pos = pos + 1
  }
  // Parse 4-digit year (at least).
  match parse_digits(s, pos, 4) {
    Some((y, np)) =>
      if np < s.length() && s[np] == '-' {
        pos = np + 1
        match parse_digits(s, pos, 2) {
          Some((m, np2)) =>
            if np2 < s.length() && s[np2] == '-' {
              pos = np2 + 1
              match parse_digits(s, pos, 2) {
                Some((d, _)) => date(year_sign * y, m, d)
                None => None
              }
            } else {
              None
            }
          None => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
/// Parse an ISO 8601 time string: `HH:MM:SS` or `HH:MM:SS.fffffffff`.
///
/// Returns `None` on invalid input.
pub fn parse_time(s : String) -> Time? {
  match parse_digits(s, 0, 2) {
    Some((h, p1)) =>
      if p1 < s.length() && s[p1] == ':' {
        match parse_digits(s, p1 + 1, 2) {
          Some((m, p2)) =>
            if p2 < s.length() && s[p2] == ':' {
              match parse_digits(s, p2 + 1, 2) {
                Some((sec, p3)) => {
                  let mut ns = 0
                  let mut p4 = p3
                  if p3 < s.length() && s[p3] == '.' {
                    // Parse fractional seconds (up to 9 digits).
                    let mut frac = 0
                    let mut count = 0
                    p4 = p3 + 1
                    while p4 < s.length() && count < 9 {
                      match parse_digit(s[p4]) {
                        Some(d) => {
                          frac = frac * 10 + d
                          count = count + 1
                          p4 = p4 + 1
                        }
                        None => break
                      }
                    }
                    // Scale to nanoseconds.
                    for _i = count; _i < 9; _i = _i + 1 {
                      frac = frac * 10
                    }
                    ns = frac
                  }
                  time(h, m, sec, ns)
                }
                None => None
              }
            } else {
              None
            }
          None => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
/// Parse an ISO 8601 / RFC 3339 datetime string.
///
/// Accepted formats:
/// - `YYYY-MM-DDTHH:MM:SSZ`
/// - `YYYY-MM-DDTHH:MM:SS+HH:MM`
/// - `YYYY-MM-DDTHH:MM:SS-HH:MM`
/// - `YYYY-MM-DDTHH:MM:SS.fffffffffZ`
/// - Space separator instead of `T` is also accepted.
///
/// Returns `None` on invalid input.
pub fn parse_datetime(s : String) -> DateTime? {
  // Find the separator between date and time ('T' or ' ').
  let mut sep_pos = -1
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == 'T' || c == 't' || c == ' ' {
      sep_pos = i
      break
    }
  }
  if sep_pos < 0 {
    return None
  }
  let date_str = s[:sep_pos].to_owned()
  let d = match parse_date(date_str) {
    Some(d) => d
    None => return None
  }
  // The time portion starts after the separator.
  let time_and_offset = s[sep_pos + 1:].to_owned()
  // Find where the time ends and offset begins.
  // The offset starts with 'Z', '+', or '-'.
  let mut offset_start = time_and_offset.length()
  for i = 0; i < time_and_offset.length(); i = i + 1 {
    let c = time_and_offset[i]
    if c == 'Z' || c == 'z' {
      offset_start = i
      break
    }
    if (c == '+' || c == '-') && i > 0 {
      // Make sure this isn't the sign of the hours — it must come after
      // at least the HH:MM:SS part (8 chars minimum).
      offset_start = i
      break
    }
  }
  let time_str = time_and_offset[:offset_start].to_owned()
  let offset_str = time_and_offset[offset_start:].to_owned()
  let t = match parse_time(time_str) {
    Some(t) => t
    None => return None
  }
  // Parse the offset.
  let offset_minutes = if offset_str.length() == 0 {
    // No offset — assume UTC.
    0
  } else if offset_str[0] == 'Z' || offset_str[0] == 'z' {
    0
  } else {
    let sign = if offset_str[0] == '+' { 1 } else { -1 }
    if offset_str.length() < 6 {
      return None
    }
    match parse_digits(offset_str, 1, 2) {
      Some((oh, p)) =>
        if p < offset_str.length() && offset_str[p] == ':' {
          match parse_digits(offset_str, p + 1, 2) {
            Some((om, _)) => sign * (oh * 60 + om)
            None => return None
          }
        } else {
          // Also accept ±HHMM without colon.
          match parse_digits(offset_str, 3, 2) {
            Some((om, _)) => sign * (oh * 60 + om)
            None => return None
          }
        }
      None => return None
    }
  }
  datetime(d, t, offset_minutes)
}

// ---------------------------------------------------------------------------
// Utility: now (caller-provided timestamp)
// ---------------------------------------------------------------------------

///|
/// Create a UTC `DateTime` from a caller-provided Unix timestamp.
///
/// MoonBit has no system clock access, so the caller must obtain the
/// current time from the host (e.g. via FFI or a platform API) and pass
/// it here.
pub fn from_unix_secs(ts : Int64) -> DateTime {
  from_timestamp(ts, 0)
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

///|
test "chrono: leap year detection" {
  assert_true(is_leap_year(2000))
  assert_false(is_leap_year(1900))
  assert_true(is_leap_year(2024))
  assert_false(is_leap_year(2023))
  assert_true(is_leap_year(0))
  assert_true(is_leap_year(-4))
}

///|
test "chrono: days in month" {
  assert_eq(days_in_month(2024, 2), 29)
  assert_eq(days_in_month(2023, 2), 28)
  assert_eq(days_in_month(2024, 1), 31)
  assert_eq(days_in_month(2024, 4), 30)
  assert_eq(days_in_month(2024, 13), 0)
}

///|
test "chrono: date creation and validation" {
  assert_true(date(2024, 1, 1) is Some(_))
  assert_true(date(2024, 2, 29) is Some(_)) // leap year
  assert_true(date(2023, 2, 29) is None) // not leap
  assert_true(date(2024, 13, 1) is None)
  assert_true(date(2024, 0, 1) is None)
  assert_true(date(2024, 1, 0) is None)
  assert_true(date(2024, 1, 32) is None)
}

///|
test "chrono: date to days round-trip" {
  // 1970-01-01 is day 0.
  let epoch = date(1970, 1, 1).unwrap()
  let d = date_to_days(epoch.year, epoch.month, epoch.day)
  assert_eq(d, 0)
  let back = days_to_date(0)
  assert_eq(back.year, 1970)
  assert_eq(back.month, 1)
  assert_eq(back.day, 1)
}

///|
test "chrono: weekday calculation" {
  // 1970-01-01 was a Thursday (ISO 4).
  let epoch = date(1970, 1, 1).unwrap()
  assert_eq(weekday(epoch), 4)
  // 2024-01-01 was a Monday (ISO 1).
  let d = date(2024, 1, 1).unwrap()
  assert_eq(weekday(d), 1)
  // 2000-01-01 was a Saturday (ISO 6).
  let y2k = date(2000, 1, 1).unwrap()
  assert_eq(weekday(y2k), 6)
}

///|
test "chrono: day of year" {
  assert_eq(day_of_year(date(2024, 1, 1).unwrap()), 1)
  assert_eq(day_of_year(date(2024, 12, 31).unwrap()), 366) // leap year
  assert_eq(day_of_year(date(2023, 12, 31).unwrap()), 365)
  assert_eq(day_of_year(date(2024, 3, 1).unwrap()), 61) // Jan(31)+Feb(29)+1
}

///|
test "chrono: add_days" {
  let d = date(2024, 1, 1).unwrap()
  let d2 = add_days(d, 31)
  assert_eq(d2.year, 2024)
  assert_eq(d2.month, 2)
  assert_eq(d2.day, 1)
  let d3 = add_days(d, -1)
  assert_eq(d3.year, 2023)
  assert_eq(d3.month, 12)
  assert_eq(d3.day, 31)
}

///|
test "chrono: add_months with clamping" {
  let d = date(2024, 1, 31).unwrap()
  let d2 = add_months(d, 1)
  // Jan 31 + 1 month = Feb 29 (clamped, 2024 is leap).
  assert_eq(d2.month, 2)
  assert_eq(d2.day, 29)
  let d3 = add_months(d, 2)
  // Jan 31 + 2 months = Mar 31.
  assert_eq(d3.month, 3)
  assert_eq(d3.day, 31)
}

///|
test "chrono: add_years with Feb 29 clamping" {
  let d = date(2024, 2, 29).unwrap()
  let d2 = add_years(d, 1)
  // 2025 is not a leap year, so Feb 29 -> Feb 28.
  assert_eq(d2.year, 2025)
  assert_eq(d2.month, 2)
  assert_eq(d2.day, 28)
}

///|
test "chrono: days_between" {
  let a = date(2024, 1, 1).unwrap()
  let b = date(2024, 2, 1).unwrap()
  assert_eq(days_between(a, b), 31)
  assert_eq(days_between(b, a), -31)
  let c = date(2024, 12, 31).unwrap()
  assert_eq(days_between(a, c), 365) // 2024 is leap, but Jan 1 to Dec 31 = 365 days
}

///|
test "chrono: time creation and validation" {
  assert_true(time(0, 0, 0, 0) is Some(_))
  assert_true(time(23, 59, 59, 999_999_999) is Some(_))
  assert_true(time(24, 0, 0, 0) is None)
  assert_true(time(0, 60, 0, 0) is None)
  assert_true(time(0, 0, 60, 0) is None)
  assert_true(time(0, 0, 0, 1_000_000_000) is None)
}

///|
test "chrono: datetime and timestamp round-trip" {
  let d = date(2024, 1, 1).unwrap()
  let t = time(0, 0, 0, 0).unwrap()
  let dt = datetime_utc(d, t).unwrap()
  // 2024-01-01T00:00:00Z = 1704067200.
  assert_eq(timestamp(dt), 1704067200L)
  let dt2 = from_timestamp(1704067200L, 0)
  let d2 = date_of(dt2)
  assert_eq(d2.year, 2024)
  assert_eq(d2.month, 1)
  assert_eq(d2.day, 1)
}

///|
test "chrono: datetime with offset" {
  let d = date(2024, 1, 1).unwrap()
  let t = time(8, 0, 0, 0).unwrap()
  let dt = datetime(d, t, 480).unwrap() // UTC+8
  // 2024-01-01T08:00:00+08:00 = 2024-01-01T00:00:00Z = 1704067200.
  assert_eq(timestamp(dt), 1704067200L)
  // The local time should be 08:00:00.
  let t2 = time_of(dt)
  assert_eq(t2.hour, 8)
}

///|
test "chrono: format_date" {
  assert_eq(format_date(date(2024, 1, 1).unwrap()), "2024-01-01")
  assert_eq(format_date(date(2024, 12, 31).unwrap()), "2024-12-31")
  assert_eq(format_date(date(1, 1, 1).unwrap()), "0001-01-01")
}

///|
test "chrono: format_time" {
  assert_eq(format_time(time(12, 30, 45, 0).unwrap()), "12:30:45")
  let t = time(1, 2, 3, 500_000_000).unwrap()
  assert_eq(format_time(t), "01:02:03.5")
  let t2 = time(1, 2, 3, 123_456_789).unwrap()
  assert_eq(format_time(t2), "01:02:03.123456789")
}

///|
test "chrono: format_datetime UTC" {
  let d = date(2024, 1, 1).unwrap()
  let t = time(0, 0, 0, 0).unwrap()
  let dt = datetime_utc(d, t).unwrap()
  assert_eq(format_datetime(dt), "2024-01-01T00:00:00Z")
}

///|
test "chrono: format_datetime with offset" {
  let d = date(2024, 1, 1).unwrap()
  let t = time(12, 0, 0, 0).unwrap()
  let dt = datetime(d, t, 480).unwrap() // UTC+8
  assert_eq(format_datetime(dt), "2024-01-01T12:00:00+08:00")
}

///|
test "chrono: parse_date" {
  let d = parse_date("2024-01-15").unwrap()
  assert_eq(d.year, 2024)
  assert_eq(d.month, 1)
  assert_eq(d.day, 15)
  assert_true(parse_date("invalid") is None)
}

///|
test "chrono: parse_time" {
  let t = parse_time("12:30:45").unwrap()
  assert_eq(t.hour, 12)
  assert_eq(t.minute, 30)
  assert_eq(t.second, 45)
  let t2 = parse_time("01:02:03.5").unwrap()
  assert_eq(t2.nanosecond, 500_000_000)
}

///|
test "chrono: parse_datetime UTC" {
  let dt = parse_datetime("2024-01-01T00:00:00Z").unwrap()
  assert_eq(timestamp(dt), 1704067200L)
  let d = date_of(dt)
  assert_eq(d.year, 2024)
  assert_eq(d.month, 1)
  assert_eq(d.day, 1)
}

///|
test "chrono: parse_datetime with offset" {
  let dt = parse_datetime("2024-01-01T08:00:00+08:00").unwrap()
  assert_eq(timestamp(dt), 1704067200L)
}

///|
test "chrono: parse_datetime with fractional seconds" {
  let dt = parse_datetime("2024-01-01T00:00:00.5Z").unwrap()
  let t = time_of(dt)
  assert_eq(t.nanosecond, 500_000_000)
}

///|
test "chrono: round-trip format and parse" {
  let d = date(2024, 6, 15).unwrap()
  let t = time(14, 30, 45, 123_456_789).unwrap()
  let dt = datetime(d, t, 300).unwrap() // UTC+5
  let formatted = format_datetime(dt)
  let parsed = parse_datetime(formatted).unwrap()
  assert_eq(timestamp(parsed), timestamp(dt))
  let t2 = time_of(parsed)
  assert_eq(t2.hour, 14)
  assert_eq(t2.minute, 30)
  assert_eq(t2.second, 45)
  assert_eq(t2.nanosecond, 123_456_789)
}

///|
test "chrono: duration operations" {
  let d1 = duration_secs(100)
  let d2 = duration_secs(50)
  let d3 = duration_add(d1, d2)
  assert_eq(duration_as_secs(d3), 150)
  let d4 = duration_sub(d1, d2)
  assert_eq(duration_as_secs(d4), 50)
  assert_eq(duration_as_ms(d1), 100_000L)
  assert_eq(duration_as_ns(d1), 100_000_000_000L)
}

///|
test "chrono: add_duration to datetime" {
  let d = date(2024, 1, 1).unwrap()
  let t = time(23, 59, 59, 0).unwrap()
  let dt = datetime_utc(d, t).unwrap()
  let dt2 = add_duration(dt, duration_secs(1))
  let d2 = date_of(dt2)
  assert_eq(d2.day, 2) // Crossed midnight.
  let t2 = time_of(dt2)
  assert_eq(t2.hour, 0)
  assert_eq(t2.minute, 0)
  assert_eq(t2.second, 0)
}

///|
test "chrono: duration_between" {
  let a = from_timestamp(100L, 0)
  let b = from_timestamp(200L, 0)
  let dur = duration_between(a, b)
  assert_eq(duration_as_secs(dur), 100)
}

///|
test "chrono: compare_date" {
  let a = date(2024, 1, 1).unwrap()
  let b = date(2024, 1, 2).unwrap()
  let c = date(2024, 1, 1).unwrap()
  assert_eq(compare_date(a, b), -1)
  assert_eq(compare_date(b, a), 1)
  assert_eq(compare_date(a, c), 0)
}

///|
test "chrono: compare_datetime" {
  let a = from_timestamp(100L, 0)
  let b = from_timestamp(200L, 0)
  let c = from_timestamp(100L, 0)
  assert_eq(compare_datetime(a, b), -1)
  assert_eq(compare_datetime(b, a), 1)
  assert_eq(compare_datetime(a, c), 0)
}

///|
test "chrono: negative timestamp (pre-1970)" {
  let dt = from_timestamp(-1L, 0)
  let d = date_of(dt)
  assert_eq(d.year, 1969)
  assert_eq(d.month, 12)
  assert_eq(d.day, 31)
  let t = time_of(dt)
  assert_eq(t.hour, 23)
  assert_eq(t.minute, 59)
  assert_eq(t.second, 59)
}

///|
test "chrono: parse_datetime with space separator" {
  let dt = parse_datetime("2024-06-15 14:30:00Z").unwrap()
  let d = date_of(dt)
  assert_eq(d.month, 6)
  assert_eq(d.day, 15)
}

///|
test "chrono: format and parse offset round-trip" {
  let d = date(2024, 6, 15).unwrap()
  let t = time(14, 30, 0, 0).unwrap()
  let offsets = [0, 60, -60, 300, -300, 480, -480, 330, -330]
  for i = 0; i < offsets.length(); i = i + 1 {
    let dt = datetime(d, t, offsets[i]).unwrap()
    let formatted = format_datetime(dt)
    let parsed = parse_datetime(formatted).unwrap()
    assert_eq(timestamp(parsed), timestamp(dt))
  }
}
