#!/usr/bin/env bash
# Usage: check-taskmodifier2-symbols.sh <built OpenSwiftUI library or object>
# Checks that the symbols apps import for _TaskModifier2/_TaskValueModifier2
# are exported. Needs a built library; not run in CI.
set -euo pipefail
lib=${1:?path to built OpenSwiftUI library}
fail=0
for sym in \
  '$s7SwiftUI14_TaskModifier2V4name18executorPreference8priority6actionACSS_Sch_pSgScPyyYaYAcntcfC' \
  '$s7SwiftUI14_TaskModifier2VAA12ViewModifierAAMc' \
  '$s7SwiftUI14_TaskModifier2VMa' \
  '$s7SwiftUI14_TaskModifier2VMn' \
  '$s7SwiftUI19_TaskValueModifier2V2id4name18executorPreference8priority6actionACyxGx_SSSch_pSgScPyyYaYAcntcfC' \
  '$s7SwiftUI19_TaskValueModifier2VyxGAA12ViewModifierAAMc' \
  '$s7SwiftUI19_TaskValueModifier2VMa' \
  '$s7SwiftUI19_TaskValueModifier2VMn'; do
  # Built module is OpenSwiftUI; compare with the module name substituted.
  want=${sym/7SwiftUI/11OpenSwiftUI}
  if nm -g "$lib" 2>/dev/null | grep -qF -- "$want"; then
    echo "ok       $sym"
  else
    echo "MISSING  $sym"; fail=1
  fi
done
exit $fail
