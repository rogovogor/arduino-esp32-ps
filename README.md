# arduino-esp32 2.0.17 with power management

The stock arduino-esp32 2.0.17 core for PlatformIO (`framework-arduinoespressif32`),
with the prebuilt ESP-IDF 4.4.7 libraries rebuilt so that **automatic light sleep
works**: `CONFIG_PM_ENABLE`, FreeRTOS tickless idle and Bluetooth modem sleep.

The stock libraries are built without `CONFIG_PM_ENABLE`, so `esp_pm_configure()`
returns `ESP_ERR_NOT_SUPPORTED` and an ESP32 BLE node cannot sleep between
connection events. This holds for the newest official libraries too (pioarduino,
IDF 5.3). The only way around it is to rebuild the libraries — this repository is
the recipe and the build for that.

Used by [MeshCore](https://github.com/rogovogor/MeshCore) companion and repeater
firmware built with `WITH_ESP32_POWER_SAVING`.

## What is changed

Only configuration. The input for every target is the **stock** `tools/sdk/<target>/sdkconfig`
of arduino-esp32 2.0.17 plus [`recipe/defconfig.powersaving`](recipe/defconfig.powersaving):

```
CONFIG_PM_ENABLE=y
CONFIG_FREERTOS_USE_TICKLESS_IDLE=y
CONFIG_FREERTOS_IDLE_TIME_BEFORE_SLEEP=3
CONFIG_PM_SLP_IRAM_OPT=y
CONFIG_BT_CTRL_MODEM_SLEEP=y
CONFIG_BT_CTRL_MODEM_SLEEP_MODE_1=y
CONFIG_BT_CTRL_LPCLK_SEL_MAIN_XTAL=y
CONFIG_BT_CTRL_MAIN_XTAL_PU_DURING_LIGHT_SLEEP=y
```

Octal-PSRAM variants additionally get [`recipe/defconfig.opi_psram_fix`](recipe/defconfig.opi_psram_fix):
the stock config explicitly selects QUAD, so OCT alone would leave it as is.

Nothing else is touched. Bootloaders, linker scripts, Arduino libraries and the
optional components (camera, esp-dl, esp-sr, esp-dsp, littlefs) are those of the
stock PlatformIO package.

## Targets

| Target | Memory variants |
|---|---|
| esp32s3 | qio_qspi, qio_opi, dio_qspi, dio_opi, opi_opi, opi_qspi |
| esp32 | dio, dout, qio, qout |
| esp32c3 | dio, dout, qio, qout |

On the classic ESP32 the BLE controller cannot keep a connection through light
sleep without an external 32.768 kHz crystal; the libraries are built anyway.

## Using it with PlatformIO

Releases carry `framework-arduinoespressif32-2.0.17-ps.N.tar.gz` and its `.sha256`.
The package version is `3.20017.241212-ps.N`, never the stock one.

Do **not** put the release URL straight into `platform_packages`: PlatformIO keeps
one `framework-arduinoespressif32` per core directory, so the PS core would replace
the stock one and every other ESP32 build would silently link against it. Instead:

1. unpack the archive once into `<core_dir>/ps/framework-arduinoespressif32-2.0.17-ps.N`
   (MeshCore does it with `tools/ps_framework.py`);
2. pin the stock core in the normal environments and link the PS core in the PS ones:

```ini
[esp32_base]
platform_packages = platformio/framework-arduinoespressif32 @ 3.20017.241212+sha.dcc1105b

[esp32_ps]
platform_packages =
  framework-arduinoespressif32 @ symlink://${platformio.core_dir}/ps/framework-arduinoespressif32-2.0.17-ps.1
```

Both cores then live side by side and builds switch without reinstalling.

## Building

Everything that decides the result is pinned in [`versions.env`](versions.env):
arduino-esp32, ESP-IDF, the `esp32-arduino-lib-builder` commit, the component
commits from the stock `versions.txt`, and the stock PlatformIO package with its sha256.

```
docker build -t ps-builder .
docker run --rm -v "$PWD:/work" -w /work ps-builder bash scripts/build-libs.sh
bash scripts/assemble.sh
bash scripts/verify.sh dist/framework-arduinoespressif32-*.tar.gz
```

Without Docker, run `scripts/build-libs.sh` in a shell where ESP-IDF 4.4.7 is
exported (`. $IDF_PATH/export.sh`). CI does the same on GitHub Actions; a tag
`2.0.17-ps.N` publishes a draft release.

## Licenses

arduino-esp32 is LGPL-2.1-or-later, ESP-IDF is Apache-2.0; the Bluetooth and
Wi-Fi controller blobs are redistributed unchanged from Espressif. The
corresponding sources are the upstream projects at the revisions pinned in
`versions.env`, built with the configuration in `recipe/`. The scripts in this
repository are MIT (see [LICENSE](LICENSE)).
