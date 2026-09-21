#!/usr/bin/env python3
"""Stage OpenSwiftUI's two Swift targets as a single module.

Apple mangles every symbol an app binds as module `SwiftUI`, so OpenSwiftUICore
and OpenSwiftUI must compile as one module. Inside one module the cross-target
import is meaningless, so drop it along with any attributes that decorate it.
"""
import os, re, shutil, sys

if len(sys.argv) != 3:
    sys.exit(f'usage: {sys.argv[0]} <OpenSwiftUI/Sources> <staging dir>')
SRC, DST = sys.argv[1], sys.argv[2]
IMPORT = re.compile(r'^\s*(?:@_spi\([^)]*\)\s*)*(?:package|public|internal|fileprivate|private)?\s*import\s+OpenSwiftUICore\s*$')
ATTR = re.compile(r'^\s*@_spi\([^)]*\)\s*$')
# Apple's own Observation module is the ABI-correct source of Observable and
# ObservationRegistrar; OpenObservation is only its open-source twin.
OBS = re.compile(r'(^\s*(?:@_spi\([^)]*\)\s*)*(?:package|public|internal|fileprivate|private)?\s*import\s+)OpenObservation\s*$')
# Both targets become one module named SwiftUI, so a reference qualified by either target's
# module name (OpenSwiftUI.Binding, OpenSwiftUICore.Text) no longer resolves. Requalify them.
# The lookbehind keeps OpenSwiftUICore.X from also matching the OpenSwiftUI.X pattern, and
# stops OpenSwiftUIBridge and friends being rewritten.
QUAL = re.compile(r'(?<![\w.])OpenSwiftUI(?:Core)?\.(?=\w)')

if os.path.exists(DST):
    shutil.rmtree(DST)
stripped = swapped = requalified = files = 0
for target in ('OpenSwiftUICore', 'OpenSwiftUI'):
    for root, _, names in os.walk(os.path.join(SRC, target)):
        for n in sorted(names):
            s = os.path.join(root, n)
            d = os.path.join(DST, os.path.relpath(s, SRC))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            if not n.endswith('.swift'):
                shutil.copy2(s, d); continue
            files += 1
            out = []
            for line in open(s).read().splitlines():
                if IMPORT.match(line):
                    while out and ATTR.match(out[-1]):
                        out.pop()
                    stripped += 1
                    continue
                m = OBS.match(line)
                if m:
                    line = m.group(1) + 'Observation'
                    swapped += 1
                line, n = QUAL.subn('SwiftUI.', line)
                requalified += n
                out.append(line)
            open(d, 'w').write('\n'.join(out) + '\n')
print(f'staged {files} swift files, stripped {stripped} OpenSwiftUICore imports, swapped {swapped} OpenObservation imports, requalified {requalified} module-qualified references -> {DST}')
