#!/usr/bin/env python3
"""Teach Darling's AvailabilityInternal.h about visionOS.

Darling's copy predates visionOS, so API_AVAILABLE(..., visionos(1.0)) does not
expand and fails to parse. Every modern Apple header uses it. Three macro
families need the platform: available, deprecated, unavailable.
"""
import sys
if len(sys.argv) != 2:
    sys.exit(f'usage: {sys.argv[0]} <sdk>/usr/include/AvailabilityInternal.h')
p = sys.argv[1]
t = open(p).read()
families = [
    ('    #define __API_AVAILABLE_PLATFORM_bridgeos(x) bridgeos,introduced=x\n',
     '    #define __API_AVAILABLE_PLATFORM_visionos(x) visionos,introduced=x\n'),
    ('    #define __API_DEPRECATED_PLATFORM_bridgeos(x,y) bridgeos,introduced=x,deprecated=y\n',
     '    #define __API_DEPRECATED_PLATFORM_visionos(x,y) visionos,introduced=x,deprecated=y\n'),
    ('    #define __API_UNAVAILABLE_PLATFORM_bridgeos bridgeos,unavailable\n',
     '    #define __API_UNAVAILABLE_PLATFORM_visionos visionos,unavailable\n'),
]
for anchor, addition in families:
    if addition.splitlines()[0] + '\n' in t:
        continue
    assert t.count(anchor) == 1, f'anchor not unique: {anchor!r}'
    t = t.replace(anchor, anchor + addition, 1)
open(p, 'w').write(t)
print('patched', p)
