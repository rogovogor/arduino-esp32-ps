#!/bin/bash
# Rebuild the arduino-esp32 2.0.17 IDF libraries with power management enabled.
# Runs inside the IDF 4.4.7 container (see Dockerfile) or after
# scripts/setup-idf-noroot.sh. Output: build/out/tools/sdk/<target>/
#
# The input sdkconfig is the stock one shipped with arduino-esp32 2.0.17 plus our
# delta (recipe/defconfig.powersaving), not the lib-builder's generic defconfigs:
# that keeps the result as close to stock as possible.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
source versions.env
: "${IDF_PATH:?run inside the IDF container, or source build/env-noroot.sh first}"

WORK=$ROOT/build
LB=$WORK/lib-builder
mkdir -p "$WORK"

# Stock arduino-esp32 tree: the source of the per-target stock sdkconfig
if [ ! -d "$WORK/arduino-esp32/.git" ]; then
  git clone --depth 1 --branch "$ARDUINO_VERSION" https://github.com/espressif/arduino-esp32 "$WORK/arduino-esp32"
fi

# Library builder at the pinned commit. The pin is a full commit id that is not
# reachable from any branch (it is the commit the stock 2.0.17 libraries were
# built with), so plain "clone && checkout" fails on a fresh checkout: fetch it
# explicitly by SHA first.
if [ ! -d "$LB/.git" ]; then
  git clone https://github.com/espressif/esp32-arduino-lib-builder "$LB"
fi
if ! git -C "$LB" cat-file -e "${LIB_BUILDER_COMMIT}^{commit}" 2>/dev/null; then
  git -C "$LB" fetch -q origin "$LIB_BUILDER_COMMIT"
fi
git -C "$LB" checkout -q --detach "$LIB_BUILDER_COMMIT"
cp recipe/defconfig.powersaving "$LB/configs/defconfig.powersaving"

cd "$LB"

# Only the two external components the core needs. The optional components
# (camera, esp-dl, esp_littlefs, esp-rainmaker, esp-dsp) are deliberately NOT
# built: the stock PlatformIO package this build is laid over already ships
# them, and pulling them into the project would replace their lib/*.a and add
# their Kconfig symbols to sdkconfig.h. Their stock commits stay in versions.env
# and are checked by scripts/check-pins.sh.
if [ ! -d components/arduino/.git ]; then
  git clone -q --depth 1 --branch "$ARDUINO_COMPONENT_REF" \
    https://github.com/espressif/arduino-esp32.git components/arduino
fi
if [ ! -d components/arduino_tinyusb/tinyusb/.git ]; then
  git clone -q https://github.com/hathach/tinyusb.git components/arduino_tinyusb/tinyusb
fi

pin() {   # <component-dir> <ref>
  [ -d "$1/.git" ] || return 0
  if ! git -C "$1" rev-parse --verify -q "$2^{commit}" >/dev/null 2>&1; then
    git -C "$1" fetch -q origin
    git -C "$1" fetch -q --tags origin
  fi
  git -C "$1" checkout -q --detach "$2"
}
pin components/arduino                 "$ARDUINO_COMPONENT_REF"
pin components/arduino_tinyusb/tinyusb "$TINYUSB_COMMIT"
# Optional components: pinned only if a caller pre-populated them. This recipe
# does not clone them (see above).
pin components/esp32-camera            "$ESP32_CAMERA_COMMIT"
pin components/esp-dl                  "$ESP_DL_COMMIT"
pin components/esp_littlefs            "$ESP_LITTLEFS_COMMIT"
pin components/esp-rainmaker           "$ESP_RAINMAKER_COMMIT"
pin components/espressif__esp-dsp      "$ESP_DSP_COMMIT"

defaults_for() {   # <target> <out-file> [extra defconfig files...]
  local t=$1 out=$2; shift 2
  cat "$WORK/arduino-esp32/tools/sdk/$t/sdkconfig" "$ROOT/recipe/defconfig.powersaving" "$@" > "$out"
}

for T in $TARGETS; do
  echo "=== $T: base libraries (idf_libs)"
  DEF=$WORK/$T-defaults.txt
  defaults_for "$T" "$DEF"
  rm -rf build sdkconfig
  idf.py -DIDF_TARGET="$T" -DSDKCONFIG_DEFAULTS="$DEF" idf_libs > "$WORK/$T-libs.log" 2>&1 \
    || { echo "FAILED: $T idf_libs, see build/$T-libs.log"; tail -30 "$WORK/$T-libs.log"; exit 1; }

  var="VARIANTS_$T"
  for spec in ${!var}; do
    IFS=: read -r flash freq ram <<< "$spec"
    extra=("configs/defconfig.$flash" "configs/defconfig.$freq")
    [ "$ram" != none ] && extra+=("configs/defconfig.$ram")
    # Octal PSRAM: the stock config explicitly picks QUAD, so OCT alone is not enough.
    [ "$ram" = opi_ram ] && extra+=("$ROOT/recipe/defconfig.opi_psram_fix")
    D=$WORK/$T-def-$flash-$freq-$ram.txt
    defaults_for "$T" "$D" "${extra[@]}"
    echo "=== $T: memory variant $flash $freq $ram"
    rm -rf build sdkconfig
    idf.py -DIDF_TARGET="$T" -DSDKCONFIG_DEFAULTS="$D" mem_variant > "$WORK/$T-mem-$flash-$ram.log" 2>&1 \
      || { echo "FAILED: $T mem_variant $spec, see build/$T-mem-$flash-$ram.log"; tail -30 "$WORK/$T-mem-$flash-$ram.log"; exit 1; }
  done
done

rm -rf "$WORK/out" && cp -r "$LB/out" "$WORK/out"
echo "=== done: build/out/tools/sdk"
for T in $TARGETS; do
  for v in "$WORK/out/tools/sdk/$T"/*/; do
    [ -f "$v/include/sdkconfig.h" ] && echo "  $T/$(basename "$v"): PM=$(grep -c 'define CONFIG_PM_ENABLE 1' "$v/include/sdkconfig.h")"
  done
done
