#!/bin/bash
# Check a packed core: version, PM in every memory variant, PM libraries present.
# Usage: scripts/verify.sh dist/framework-arduinoespressif32-2.0.17-ps.N.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env
ARCHIVE=$1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
tar -xzf "$ARCHIVE" -C "$T"
P=$T/framework-arduinoespressif32
fail=0

v=$(python3 -c "import json;print(json.load(open('$P/package.json'))['version'])")
echo "version: $v"; [[ "$v" == *-ps.* ]] || { echo "FAIL: version is not a -ps. build"; fail=1; }
[ ! -e "$P/.piopm" ] || { echo "FAIL: .piopm present"; fail=1; }

for t in $TARGETS; do
  for h in "$P/tools/sdk/$t"/*/include/sdkconfig.h; do
    n=$(basename "$(dirname "$(dirname "$h")")")
    if grep -q "define CONFIG_PM_ENABLE 1" "$h"; then echo "  $t/$n: PM on"; else echo "FAIL: $t/$n without CONFIG_PM_ENABLE"; fail=1; fi
    grep -q "define CONFIG_FREERTOS_USE_TICKLESS_IDLE 1" "$h" || { echo "FAIL: $t/$n without tickless idle"; fail=1; }
  done
  [ -f "$P/tools/sdk/$t/lib/libesp_pm.a" ] || { echo "FAIL: $t libesp_pm.a missing"; fail=1; }
done
[ $fail = 0 ] && echo "OK" || { echo "VERIFY FAILED"; exit 1; }
