#!/usr/bin/env python3
import subprocess,sys
output=subprocess.check_output(['llvm-nm','--undefined-only',sys.argv[1]],text=True)
missing=[name for name in ['__CFDateFormatterCreateSkeletonFromTemplate','__CFCalendarGetUnitsFromDateFormat'] if name in output]
for name in missing:print('FAIL: date update-unit selection requires absent private API '+name)
if not missing:print('PASS: date provider has no private CF pattern dependencies')
sys.exit(bool(missing))
