# Date update-unit source adaptation

Public source contract: Unicode TR35 date fields and quoting, https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table . This scanner selects the smallest existing NSCalendar unit needed for updates; date rendering remains in NSDateFormatter. Flexible day periods conservatively update each minute. Fractional seconds/milliseconds use the existing nanosecond unit. Time zone fields do not introduce a calendar unit. Unknown reserved letters or unterminated quotes yield no unit.

Compile date-pattern.c as plain C11 and run its 33 cases. Run verify-date-provider-closure.py on the real compiled DateProvider.m object: before the fix it fails for both private CF date-pattern imports; after the fix neither import may remain. This verifies a source dependency replacement, not undocumented private CoreFoundation semantics or actual app rendering.
