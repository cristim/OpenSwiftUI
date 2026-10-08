// Date update scheduling from Unicode TR35 date-pattern fields.
// https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table
// This determines an update unit; it does not format dates or implement private CF APIs.
#pragma once
#include <stddef.h>
#include <stdint.h>

typedef enum {
    OpenSwiftUIDatePatternNone = 0,
    OpenSwiftUIDatePatternNanosecond,
    OpenSwiftUIDatePatternSecond,
    OpenSwiftUIDatePatternMinute,
    OpenSwiftUIDatePatternHour,
    OpenSwiftUIDatePatternDay,
    OpenSwiftUIDatePatternWeekday,
    OpenSwiftUIDatePatternWeekdayOrdinal,
    OpenSwiftUIDatePatternWeekOfMonth,
    OpenSwiftUIDatePatternWeekOfYear,
    OpenSwiftUIDatePatternMonth,
    OpenSwiftUIDatePatternQuarter,
    OpenSwiftUIDatePatternYear,
    OpenSwiftUIDatePatternYearForWeekOfYear,
    OpenSwiftUIDatePatternEra,
} OpenSwiftUIDatePatternUnit;

static inline OpenSwiftUIDatePatternUnit OpenSwiftUIDatePatternSmallestUnit(
    const uint16_t *pattern, size_t length
) {
    OpenSwiftUIDatePatternUnit smallest = OpenSwiftUIDatePatternNone;
    int quoted = 0;
    for (size_t i = 0; i < length; ++i) {
        uint16_t c = pattern[i];
        if (c == '\'') {
            if (i + 1 < length && pattern[i + 1] == '\'') { ++i; continue; }
            quoted = !quoted;
            continue;
        }
        if (quoted) continue;
        OpenSwiftUIDatePatternUnit unit = OpenSwiftUIDatePatternNone;
        switch (c) {
            case 'G': unit = OpenSwiftUIDatePatternEra; break;
            case 'y': case 'u': case 'U': case 'r': unit = OpenSwiftUIDatePatternYear; break;
            case 'Y': unit = OpenSwiftUIDatePatternYearForWeekOfYear; break;
            case 'Q': case 'q': unit = OpenSwiftUIDatePatternQuarter; break;
            case 'M': case 'L': unit = OpenSwiftUIDatePatternMonth; break;
            case 'w': unit = OpenSwiftUIDatePatternWeekOfYear; break;
            case 'W': unit = OpenSwiftUIDatePatternWeekOfMonth; break;
            case 'd': case 'D': case 'g': unit = OpenSwiftUIDatePatternDay; break;
            case 'F': unit = OpenSwiftUIDatePatternWeekdayOrdinal; break;
            case 'E': case 'e': case 'c': unit = OpenSwiftUIDatePatternWeekday; break;
            case 'a': case 'b': case 'h': case 'H': case 'K': case 'k':
            case 'j': case 'J': case 'C': unit = OpenSwiftUIDatePatternHour; break;
            // Flexible day-period boundaries may occur within an hour.
            case 'B': case 'm': unit = OpenSwiftUIDatePatternMinute; break;
            case 's': unit = OpenSwiftUIDatePatternSecond; break;
            case 'S': case 'A': unit = OpenSwiftUIDatePatternNanosecond; break;
            case 'z': case 'Z': case 'O': case 'v': case 'V': case 'X': case 'x': break;
            default:
                // Unquoted ASCII letters are reserved by LDML.
                if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z'))
                    return OpenSwiftUIDatePatternNone;
        }
        if (unit && (!smallest || unit < smallest)) smallest = unit;
    }
    return quoted ? OpenSwiftUIDatePatternNone : smallest;
}
