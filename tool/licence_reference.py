#!/usr/bin/env python3
"""The Dart licence filter, transcribed.

Used only by tool/verify_licence_parity.sh to compare against the Rust
implementation. Transcribed rather than invoked because the point is to check
two independent implementations of the same rules, and asking one of them what
it thinks defeats the purpose.
"""
import re, sys

ALLOWED = ['public domain', 'cc0', 'cc by 2.0', 'cc by 3.0', 'cc by 4.0', 'cc by']

def allows(licence: str) -> bool:
    low = licence.lower().strip()
    if not low:
        return False
    if re.search(r'share[\s_-]?alike|sharealike|-sa\b|sa\s*\d|\bsa\b', low):
        return False
    if re.search(r'-nc\b|non[\s-]?commercial', low):
        return False
    if re.search(r'-nd\b|noderiv|no[\s-]?derivative', low):
        return False
    if 'fair use' in low or 'non-free' in low:
        return False
    return any(a in low for a in ALLOWED)

for line in sys.stdin:
    line = line.rstrip('\n')
    if line.strip():
        print(f"{allows(line)}\t{line}")
