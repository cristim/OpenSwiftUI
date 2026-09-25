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
ATTR = re.compile(r'^\s*@(?:_spi\([^)]*\)|_exported)\s*$')
# Once both targets are one module, a re-export alias of a Core type names itself.
SELF_ALIAS = re.compile(r'^\s*(?:package|public)?\s*typealias\s+(\w+)\s*=\s*OpenSwiftUI(?:Core)?\.\1\s*$')
# Both targets become one module named SwiftUI, so a reference qualified by either target's
# module name (OpenSwiftUI.Binding, OpenSwiftUICore.Text) no longer resolves. Requalify them.
# The lookbehind keeps OpenSwiftUICore.X from also matching the OpenSwiftUI.X pattern, and
# stops OpenSwiftUIBridge and friends being rewritten.
QUAL = re.compile(r'(?<![\w.])OpenSwiftUI(?:Core)?\.(?=\w)')

if os.path.exists(DST):
    shutil.rmtree(DST)
stripped = requalified = files = renamed = dropped = 0
# swiftc rejects two sources with the same file name in one module.
seen = set()
for target in ('OpenSwiftUICore', 'OpenSwiftUI'):
    for root, _, names in os.walk(os.path.join(SRC, target)):
        for n in sorted(names):
            s = os.path.join(root, n)
            d = os.path.join(DST, os.path.relpath(s, SRC))
            os.makedirs(os.path.dirname(d), exist_ok=True)
            if not n.endswith('.swift'):
                shutil.copy2(s, d); continue
            files += 1
            if n in seen:
                d = os.path.join(os.path.dirname(d), f'{n[:-6]}+{target}.swift')
                renamed += 1
            seen.add(n)
            out = []
            for line in open(s).read().splitlines():
                if IMPORT.match(line):
                    while out and ATTR.match(out[-1]):
                        out.pop()
                    stripped += 1
                    continue
                if SELF_ALIAS.match(line):
                    dropped += 1
                    continue
                line, n = QUAL.subn('SwiftUI.', line)
                requalified += n
                out.append(line)
            open(d, 'w').write('\n'.join(out) + '\n')
print(f'staged {files} swift files, stripped {stripped} OpenSwiftUICore imports, requalified {requalified} module-qualified references, renamed {renamed} duplicate file names, dropped {dropped} self-aliases -> {DST}')
