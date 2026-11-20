#!/usr/bin/env bash
# Build (optional) and flash one half of the Corne via the UF2 bootloader.
#
# Usage: ./flash.sh left|right|reset [--no-build]
#   ZMK_VOLUME=<name>  bootloader drive name (default: NICENANO; some clones differ)
set -euo pipefail

BOARD="nice_nano_v2"
VOLUME_NAME="${ZMK_VOLUME:-NICENANO}"
TIMEOUT=120
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "Usage: $0 left|right|reset [--no-build]" >&2; exit 1; }

target=""
build=1
for arg in "$@"; do
  case "$arg" in
    left|right|reset) target="$arg" ;;
    --no-build) build=0 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $arg" >&2; usage ;;
  esac
done
[ -n "$target" ] || usage

case "$target" in
  left)  shield="corne_left";     label="LEFT half" ;;
  right) shield="corne_right";    label="RIGHT half" ;;
  reset) shield="settings_reset"; label="half to reset" ;;
esac

if [ "$build" = 1 ]; then
  "$REPO_DIR/build.sh" "$target"
fi

uf2="$REPO_DIR/firmware/$shield-$BOARD-zmk.uf2"
if [ ! -f "$uf2" ]; then
  echo "Firmware not found: $uf2 (run ./build.sh $target)" >&2
  exit 1
fi

mount="/Volumes/$VOLUME_NAME"
echo
echo "Connect the $label via USB and double-tap its reset button."
echo "Waiting for $mount ... (Ctrl-C to cancel)"

elapsed=0
while [ ! -d "$mount" ]; do
  if [ "$elapsed" -ge "$TIMEOUT" ]; then
    echo "Timed out waiting for $mount." >&2
    echo "Drives currently mounted:" >&2
    ls /Volumes >&2
    echo "If your board uses a different name, rerun with ZMK_VOLUME=<name>." >&2
    exit 1
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done
sleep 1 # let the mount settle

echo "Flashing $(basename "$uf2") ..."
# The board reboots as soon as it receives the file, so cp may report an error; that's expected.
cp -X "$uf2" "$mount/" 2>/dev/null || true

for _ in $(seq 1 15); do
  [ -d "$mount" ] || break
  sleep 1
done

if [ -d "$mount" ]; then
  echo "Warning: $mount is still mounted; the flash may not have completed." >&2
  exit 1
fi
echo "Done. The $label has rebooted with the new firmware."
