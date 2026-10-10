#!/bin/bash
# Lay the rebuilt libraries over the stock PlatformIO package and pack it.
# Input:  build/out/tools/sdk/<target>/ (from build-libs.sh)
# Output: dist/framework-arduinoespressif32-<ARDUINO_VERSION>-ps.<PS_REVISION>.tar.gz (+ .sha256)
#
# The lib-builder does not produce bootloaders or optional-component libraries,
# so the stock package is the base: bin/, ld/, libraries and the optional
# components stay as shipped; lib/*.a, the memory variants and sdkconfig are ours.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

NAME=framework-arduinoespressif32
PS_VER="${ARDUINO_VERSION}-ps.${PS_REVISION}"
PKG_VERSION="${STOCK_PKG_VERSION%%+*}-ps.${PS_REVISION}"   # 3.20017.241212-ps.1
SRC=build/out/tools/sdk
STAGE=build/stage
mkdir -p dist build

STOCK=build/stock.tar.gz
if [ ! -f "$STOCK" ]; then curl -fsSL -o "$STOCK" "$STOCK_PKG_URL"; fi
echo "$STOCK_PKG_SHA256  $STOCK" | sha256sum -c -

rm -rf "$STAGE" && mkdir -p "$STAGE/$NAME"
tar -xzf "$STOCK" -C "$STAGE/$NAME"
P=$STAGE/$NAME
[ -f "$P/package.json" ] || { echo "stock package layout unexpected"; exit 1; }

for T in $TARGETS; do
  [ -d "$SRC/$T" ] || { echo "missing rebuilt libraries for $T"; exit 1; }
  cp "$SRC/$T"/lib/*.a "$P/tools/sdk/$T/lib/"
  [ -f "$SRC/$T/sdkconfig" ] && cp "$SRC/$T/sdkconfig" "$P/tools/sdk/$T/sdkconfig"
  for v in "$SRC/$T"/*/; do
    n=$(basename "$v")
    [ "$n" = lib ] || [ "$n" = include ] || [ "$n" = ld ] && continue
    rm -rf "$P/tools/sdk/$T/$n" && cp -r "$v" "$P/tools/sdk/$T/$n"
  done
done

# Our own version, so the package is never mistaken for the stock one, and no
# PlatformIO install metadata (it is written on install).
python3 - "$P/package.json" "$PKG_VERSION" <<'EOF'
import json, sys
p, v = sys.argv[1], sys.argv[2]
d = json.load(open(p)); d["version"] = v
d["description"] = d.get("description", "") + " (power management enabled: CONFIG_PM_ENABLE, tickless idle, BT modem sleep)"
json.dump(d, open(p, "w"), indent=2)
EOF
rm -f "$P/.piopm" "$P/installed.json"
cp README.md "$P/PS-README.md"
cp recipe/defconfig.powersaving "$P/PS-defconfig.powersaving"

OUT=dist/$NAME-$PS_VER.tar.gz
tar -czf "$OUT" -C "$STAGE" "$NAME"
(cd dist && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
echo "=== $OUT"; cat "$OUT.sha256"
