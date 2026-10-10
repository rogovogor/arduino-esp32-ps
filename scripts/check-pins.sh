#!/bin/bash
# Verify that the component pins in versions.env still resolve to commits.
# Optional components are not built by this recipe but their stock commits are
# recorded here, so a vanished pin is worth knowing about.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

fail=0
check() { # <owner/repo> <sha> <label>
  local slug=$1 sha=$2 label=$3 full
  if full=$(curl -fsSL "https://api.github.com/repos/$slug/commits/$sha" 2>/dev/null \
            | python3 -c 'import sys,json; print(json.load(sys.stdin)["sha"])' 2>/dev/null); then
    printf 'OK    %-14s %s -> %s\n' "$label" "$sha" "$full"
  else
    printf 'MISS  %-14s %s\n' "$label" "$sha"
    fail=1
  fi
}

check espressif/arduino-esp32 "$ARDUINO_COMPONENT_REF" arduino
check hathach/tinyusb         "$TINYUSB_COMMIT"        tinyusb
check espressif/esp32-camera  "$ESP32_CAMERA_COMMIT"   esp32-camera
check espressif/esp-dl        "$ESP_DL_COMMIT"         esp-dl
check joltwallet/esp_littlefs "$ESP_LITTLEFS_COMMIT"   esp_littlefs
check espressif/esp-rainmaker "$ESP_RAINMAKER_COMMIT"  esp-rainmaker
check espressif/esp-dsp       "$ESP_DSP_COMMIT"        esp-dsp

if [ "$fail" = 0 ]; then
  echo "all component pins resolve"
else
  echo "some component pins did not resolve" >&2
  exit 1
fi
