#!/usr/bin/env bash
# Build ZMK firmware locally in Docker, using ZMK's official build image.
#
# Usage: ./build.sh [left|right|reset|all|test] [--update]
#   test       run the behavior unit tests in tests/ (ZMK's native_posix test harness)
#   --update   force `west update` (otherwise only run on first build or when config/west.yml changes)
#
# Output: firmware/<shield>-nice_nano_v2-zmk.uf2
set -euo pipefail

IMAGE="zmkfirmware/zmk-build-arm:stable"
VOLUME="zmk-workspace"
BOARD="nice_nano_v2"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { echo "Usage: $0 [left|right|reset|all|test] [--update]" >&2; exit 1; }

target="all"
force_update=0
for arg in "$@"; do
  case "$arg" in
    left|right|reset|all|test) target="$arg" ;;
    --update) force_update=1 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $arg" >&2; usage ;;
  esac
done

# Build targets
run_tests=0
case "$target" in
  left)  shields="corne_left" ;;
  right) shields="corne_right" ;;
  reset) shields="settings_reset" ;;
  all)   shields="corne_left corne_right settings_reset" ;;
  test)  shields=""; run_tests=1 ;;
esac

if ! docker info >/dev/null 2>&1; then
  echo "Docker isn't running. Start it with: colima start" >&2
  exit 1
fi

mkdir -p "$REPO_DIR/firmware"

# The west workspace (zmk, zephyr, modules,
# build dirs) lives in a persistent Docker volume; config/ is copied into it, and the
# repo itself is passed as an extra module (it has zephyr/module.yml for custom boards/shields).
docker run --rm \
  -v "$VOLUME:/workspace" \
  -v "$REPO_DIR:/zmk-config" \
  -w /workspace \
  -e BOARD="$BOARD" \
  -e SHIELDS="$shields" \
  -e FORCE_UPDATE="$force_update" \
  -e RUN_TESTS="$run_tests" \
  -e ZMK_TESTS_VERBOSE="${ZMK_TESTS_VERBOSE:-}" \
  -e HOST_UID="$(id -u)" \
  -e HOST_GID="$(id -g)" \
  "$IMAGE" \
  bash -euo pipefail -c '
    config=/workspace/config
    rm -rf "$config"
    cp -Rp /zmk-config/config "$config"

    if [ ! -d /workspace/.west ]; then
      echo "==> west init (first run)"
      west init -l "$config"
    fi

    manifest_hash=$(sha256sum "$config/west.yml" | cut -d" " -f1)
    if [ "$FORCE_UPDATE" = 1 ] || [ ! -f /workspace/.west-hash ] \
       || [ "$(cat /workspace/.west-hash)" != "$manifest_hash" ]; then
      echo "==> west update (this takes a while the first time)"
      west update --fetch-opt=--filter=tree:0
      echo "$manifest_hash" > /workspace/.west-hash
    fi

    west zephyr-export >/dev/null

    for shield in $SHIELDS; do
      echo "==> Building $shield ($BOARD)"
      west build -s zmk/app -d "build/$shield" -b "$BOARD" -- \
        -DSHIELD="$shield" -DZMK_CONFIG="$config" -DZMK_EXTRA_MODULES=/zmk-config
      out="/zmk-config/firmware/$shield-$BOARD-zmk.uf2"
      cp "build/$shield/zephyr/zmk.uf2" "$out"
      chown "$HOST_UID:$HOST_GID" "$out" 2>/dev/null || true
    done

    if [ "$RUN_TESTS" = 1 ]; then
      echo "==> Running tests in tests/ (each case is a full native build; this takes a few minutes)"
      rm -rf /workspace/build/tests
      ZMK_SRC_DIR=/workspace/zmk/app ZMK_BUILD_DIR=/workspace/build ZMK_EXTRA_MODULES=/zmk-config \
        /workspace/zmk/app/run-test.sh /zmk-config/tests
    fi
  '

[ "$run_tests" = 1 ] && exit 0

echo
echo "Firmware:"
for s in $shields; do echo "  firmware/$s-$BOARD-zmk.uf2"; done
