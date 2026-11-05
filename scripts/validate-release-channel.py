#!/usr/bin/env python3
"""Require GitHub's prerelease flag to match a supported product tag."""
import json
import re
import sys

def validate(tag, release):
    match = re.fullmatch(r'v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.([1-9][0-9]*))?', tag)
    if not match or len(tag) > 129 or any(int(n) > 65534 for n in match.groups()[:3]):
        return False
    beta = match.group(4)
    if beta is not None and int(beta) > 2147483647:
        return False
    return release.get('tagName') == tag and release.get('isPrerelease') is (beta is not None)

if __name__ == '__main__':
    try:
        ok = len(sys.argv) == 2 and validate(sys.argv[1], json.load(sys.stdin))
    except (ValueError, TypeError, AttributeError):
        ok = False
    if not ok:
        print('Release tag and prerelease flag do not match a supported channel', file=sys.stderr)
        sys.exit(64)
