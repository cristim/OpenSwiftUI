#include "../../Sources/OpenSwiftUI_SPI/Overlay/Foundation/DatePattern.h"
#include <stdio.h>
#include <string.h>

int main(void) {
    const struct { const char *pattern; OpenSwiftUIDatePatternUnit expected; } cases[] = {
        {"", 0}, {"yyyy-MM-dd HH:mm:ss", OpenSwiftUIDatePatternSecond},
        {"yyyy-MM-dd", OpenSwiftUIDatePatternDay}, {"yyyy-MM", OpenSwiftUIDatePatternMonth},
        {"yyyy", OpenSwiftUIDatePatternYear}, {"G", OpenSwiftUIDatePatternEra},
        {"QQQ", OpenSwiftUIDatePatternQuarter}, {"LLLL", OpenSwiftUIDatePatternMonth},
        {"YYYY-'W'ww", OpenSwiftUIDatePatternWeekOfYear}, {"Y", OpenSwiftUIDatePatternYearForWeekOfYear},
        {"W", OpenSwiftUIDatePatternWeekOfMonth}, {"F", OpenSwiftUIDatePatternWeekdayOrdinal},
        {"EEE", OpenSwiftUIDatePatternWeekday}, {"ccccc d", OpenSwiftUIDatePatternDay},
        {"D", OpenSwiftUIDatePatternDay}, {"g", OpenSwiftUIDatePatternDay},
        {"a", OpenSwiftUIDatePatternHour}, {"b", OpenSwiftUIDatePatternHour},
        {"B", OpenSwiftUIDatePatternMinute}, {"jjmm", OpenSwiftUIDatePatternMinute},
        {"HH", OpenSwiftUIDatePatternHour}, {"K", OpenSwiftUIDatePatternHour},
        {"kk:mm", OpenSwiftUIDatePatternMinute}, {"mm:ss.SSS", OpenSwiftUIDatePatternNanosecond},
        {"A", OpenSwiftUIDatePatternNanosecond}, {"O XXX VV", 0},
        {"yyyy 'seconds s'", OpenSwiftUIDatePatternYear}, {"'it''s m'", 0},
        {"''s", OpenSwiftUIDatePatternSecond}, {"yyyy''", OpenSwiftUIDatePatternYear},
        {"yyyy 'unterminated", 0}, {"yyyy p", 0},
    };
    unsigned failures = 0;
    for (size_t i = 0; i < sizeof(cases)/sizeof(cases[0]); ++i) {
        uint16_t text[256]; size_t n = strlen(cases[i].pattern);
        for (size_t j = 0; j < n; ++j) text[j] = (unsigned char)cases[i].pattern[j];
        OpenSwiftUIDatePatternUnit got = OpenSwiftUIDatePatternSmallestUnit(text,n);
        if (got != cases[i].expected) {
            ++failures; printf("FAIL %s: got %d expected %d\n",cases[i].pattern,got,cases[i].expected);
        }
    }
    // Non-ASCII literals and embedded NUL must not truncate subsequent fields.
    const uint16_t unicode[] = {0x5e74, ' ', 'y', 0, 's'};
    if (OpenSwiftUIDatePatternSmallestUnit(unicode,5) != OpenSwiftUIDatePatternSecond) ++failures;
    printf("Date-pattern regression: %zu cases, %u failures\n",sizeof(cases)/sizeof(cases[0])+1,failures);
    return failures != 0;
}
