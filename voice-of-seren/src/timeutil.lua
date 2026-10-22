-- timeutil.lua
-- Small, dependency-free helpers for working with Unix time (seconds since
-- January 1st, 1970, UTC). The plugin API has no date library, so the calendar
-- maths is done by hand here.
--
-- Nothing in this file reads a clock. It only converts and formats numbers,
-- which keeps it easy to unit test.

local TimeUtil = {}

TimeUtil.SECONDS_PER_MINUTE = 60
TimeUtil.SECONDS_PER_HOUR = 3600
TimeUtil.SECONDS_PER_DAY = 86400

local MONTH_NUMBERS = {
    jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
    jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
}

-- Number of days from January 1st, 1970 to the given calendar date (UTC).
-- This is Howard Hinnant's "days_from_civil" algorithm, which works for any
-- date in the Gregorian calendar without lookup tables.
function TimeUtil.DaysFromCivil(year, month, day)
    if month <= 2 then
        year = year - 1
    end
    local era = math.floor(year / 400)
    local yearOfEra = year - era * 400
    local shiftedMonth = (month + 9) % 12 -- March = 0 ... February = 11
    local dayOfYear = math.floor((153 * shiftedMonth + 2) / 5) + day - 1
    local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4)
        - math.floor(yearOfEra / 100) + dayOfYear
    return era * 146097 + dayOfEra - 719468
end

-- Converts a UTC calendar date and time into Unix seconds.
function TimeUtil.ToUnix(year, month, day, hour, minute, second)
    local days = TimeUtil.DaysFromCivil(year, month, day)
    return days * TimeUtil.SECONDS_PER_DAY
        + (hour or 0) * TimeUtil.SECONDS_PER_HOUR
        + (minute or 0) * TimeUtil.SECONDS_PER_MINUTE
        + (second or 0)
end

-- Parses an ISO 8601 UTC timestamp such as "2026-10-20T14:00:00.000Z" into
-- Unix seconds. Returns nil for anything it does not understand, including
-- timestamps with a non-UTC offset, rather than guessing.
function TimeUtil.ParseIso8601(text)
    if type(text) ~= "string" then
        return nil
    end
    local year, month, day, hour, minute, second, rest = string.match(text,
        "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)(.*)$")
    if not year then
        return nil
    end
    -- Accept "Z", "+00:00", or fractional seconds followed by either of those.
    rest = string.gsub(rest, "^%.%d+", "")
    if rest ~= "Z" and rest ~= "+00:00" and rest ~= "" then
        return nil
    end
    return TimeUtil.ToUnix(tonumber(year), tonumber(month), tonumber(day),
        tonumber(hour), tonumber(minute), tonumber(second))
end

-- Finds the "Date:" line in a block of HTTP response headers and returns it as
-- Unix seconds. HTTP dates look like "Date: Thu, 22 Oct 2026 15:23:11 GMT".
-- Returns nil if there is no usable Date header.
function TimeUtil.ParseHttpDateHeader(headerText)
    if type(headerText) ~= "string" then
        return nil
    end
    -- Prefix a newline so the pattern only matches "Date:" at the start of a
    -- line (and not, for example, inside "Last-Modified-Date:").
    local day, monthName, year, hour, minute, second = string.match("\n" .. headerText,
        "\n[Dd][Aa][Tt][Ee]:%s*%a+,%s*(%d+)%s+(%a+)%s+(%d+)%s+(%d+):(%d+):(%d+)")
    if not day then
        return nil
    end
    local month = MONTH_NUMBERS[string.lower(string.sub(monthName, 1, 3))]
    if not month then
        return nil
    end
    return TimeUtil.ToUnix(tonumber(year), month, tonumber(day),
        tonumber(hour), tonumber(minute), tonumber(second))
end

-- Returns the Unix time at the start of the hour containing `unixSeconds`.
-- The Voice of Seren changes on the hour, so this identifies "which Voice".
function TimeUtil.HourStart(unixSeconds)
    local whole = math.floor(unixSeconds)
    return whole - (whole % TimeUtil.SECONDS_PER_HOUR)
end

-- Seconds remaining until the next hour begins.
function TimeUtil.SecondsUntilNextHour(unixSeconds)
    return TimeUtil.HourStart(unixSeconds) + TimeUtil.SECONDS_PER_HOUR - unixSeconds
end

-- Formats a duration for display: "less than a minute", "1 min", "37 min",
-- "1 h", "2 h 5 min", "3 days".
function TimeUtil.FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds))
    if seconds < 60 then
        return "less than a minute"
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return minutes .. " min"
    end
    local hours = math.floor(minutes / 60)
    local leftoverMinutes = minutes % 60
    if hours < 48 then
        if leftoverMinutes == 0 then
            return hours .. " h"
        end
        return hours .. " h " .. leftoverMinutes .. " min"
    end
    return math.floor(hours / 24) .. " days"
end

-- Formats how long ago something happened: "just now", "5 min ago", "2 h ago".
function TimeUtil.FormatAgo(seconds)
    if seconds < 60 then
        return "just now"
    end
    return TimeUtil.FormatDuration(seconds) .. " ago"
end

-- Formats the hour that starts at `hourStartUnix` as a 24-hour UTC game-time
-- label, e.g. "14:00 game time". RuneScape's game clock is UTC, which avoids
-- needing the player's time zone.
function TimeUtil.FormatGameHour(hourStartUnix)
    local secondsIntoDay = math.floor(hourStartUnix) % TimeUtil.SECONDS_PER_DAY
    local hour = math.floor(secondsIntoDay / TimeUtil.SECONDS_PER_HOUR)
    return string.format("%02d:00 game time", hour)
end

return TimeUtil
