#!/bin/bash
# Rebuild the arduino-esp32 2.0.17 IDF libraries with power management enabled.
# Runs inside the IDF 4.4.7 container (see Dockerfile). Output: build/out/tools/sdk/<target>/
#
# The input sdkconfig is the stock one shipped with arduino-esp32 2.0.17 plus our
# delta (recipe/defconfig.powersaving), not the lib-builder's generic defconfigs:
# that keeps the result as close to stock as possible.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
source versions.env
: "${IDF_PATH:?run inside the IDF container}"

WORK=$ROOT/build
LB=$WORK/lib-builder
mkdir -p "$WORK"

# Stock arduino-esp32 tree: the source of the per-target stock sdkconfig
if [ ! -d "$WORK/arduino-esp32" ]; then
  git clone --depth 1 --branch "$ARDUINO_VERSION" https://github.com/espressif/arduino-esp32 "$WORK/arduino-esp32"
fi

# Library builder at the pinned commit
if [ ! -d "$LB" ]; then
  git clone https://github.com/espressif/esp32-arduino-lib-builder "$LB"
fi
git -C "$LB" checkout -q "$LIB_BUILDER_COMMIT"
cp recipe/defconfig.powersaving "$LB/configs/defconfig.powersaving"

# Components, pinned to what the stock 2.0.17 libraries were built from
cd "$LB"
if [ ! -d components/arduino ]; then
  bash tools/update-components.sh
fi
pin() { [ -d "$1" ] && git -C "$1" fetch -q --all --tags && git -C "$1" checkout -q "$2"; }
pin components/arduino                 "$ARDUINO_COMPONENT_REF"
pin components/arduino_tinyusb/tinyusb "$TINYUSB_COMMIT"
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
