#!/usr/bin/env bash
# Usage: check-taskmodifier2-symbols.sh <built SwiftUI library or object>
# Checks that the symbols apps import for _TaskModifier2/_TaskValueModifier2
# are exported. The Darling build compiles as module SwiftUI, so the names are
# matched literally. Needs a built artifact; not run in CI.
set -euo pipefail
lib=${1:?path to built SwiftUI library or object}
syms=$(nm -g "$lib")
fail=0
check() {
  # Here-string, not a pipe: no SIGPIPE under pipefail.
  grep -qF -- "$1" <<<"$syms"
}
# Negative control: a bogus name must be reported missing.
if check '$s7SwiftUI14_TaskModifier2V_bogus_control_symbol'; then
  echo "BROKEN   negative control matched"; exit 2
fi
echo "ok       negative control reports MISSING for a bogus name"
for sym in \
  '$s7SwiftUI14_TaskModifier2V4name18executorPreference8priority6actionACSS_Sch_pSgScPyyYaYAcntcfC' \
  '$s7SwiftUI14_TaskModifier2VAA12ViewModifierAAMc' \
  '$s7SwiftUI14_TaskModifier2VMa' \
  '$s7SwiftUI14_TaskModifier2VMn' \
  '$s7SwiftUI19_TaskValueModifier2V2id4name18executorPreference8priority6actionACyxGx_SSSch_pSgScPyyYaYAcntcfC' \
  '$s7SwiftUI19_TaskValueModifier2VyxGAA12ViewModifierAAMc' \
  '$s7SwiftUI19_TaskValueModifier2VMa' \
  '$s7SwiftUI19_TaskValueModifier2VMn'; do
  if check "$sym"; then
    echo "ok       $sym"
  else
    echo "MISSING  $sym"; fail=1
  fi
done
exit $fail
