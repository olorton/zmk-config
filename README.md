# zmk-config

ZMK firmware config for a wireless Corne using nice!nano v2-compatible (nRF52840 clone) controllers.

- `config/corne.keymap`: layers and key bindings
- `config/corne.conf`: firmware options (sleep, display, etc.)
- `config/west.yml`: pinned ZMK version

## Requirements

Builds run locally in Docker. On macOS, use Colima:

```sh
brew install colima docker
colima start --cpus 4 --memory 4 --mount-inotify=false
```

## Build

```sh
./build.sh            # all targets
./build.sh left       # left | right | reset | all
./build.sh --update   # force a `west update`, e.g. after changing config/west.yml
```

Firmware is written to `firmware/` (git-ignored). The first build downloads the image and ZMK/Zephyr into a Docker volume called `zmk-workspace`, which takes a few minutes. Later builds take seconds.

## Flash

```sh
./flash.sh left       # builds, then waits for the bootloader drive and copies the .uf2
./flash.sh right
./flash.sh reset      # settings_reset: clears pairing/bonds
./flash.sh left --no-build
```

When prompted, put that half into its bootloader. Either:

- Hold **Lower + Raise** and press the top outer key (`BOOT`) on that half, or
- Double-tap the reset button, or short **RST** to **GND** twice. RST is pin 3 of the right-hand column, with the USB port at the top.

The board mounts as a USB drive (`NICENANO`). If your clone uses a different drive name, run `ZMK_VOLUME=<name> ./flash.sh left`.

Usually you only need to flash the **left half** (the central, which talks to the computer). The right half only needs flashing when its own firmware changes (e.g. after a ZMK version bump).

## First-time setup / fixing pairing

1. `./flash.sh reset` on **both** halves.
2. `./flash.sh left`, then `./flash.sh right`.
3. Reset both halves at the same time so they pair with each other.
4. Pair "Corne" in macOS Bluetooth settings.

## Adjust layer (hold Lower + Raise)

| Key | Action |
|---|---|
| Top outer key (each half) | `&bootloader`: enter flashing mode on that half |
| Next key in | `&sys_reset`: restart that half |
| Left home row | `BT_CLR`, `BT_SEL 0–4`: clear or select Bluetooth profiles |
| Left bottom outer | `OUT_TOG`: toggle USB / Bluetooth output |
