#!/usr/bin/env bash
# Draw the keymap as a printable SVG with keymap-drawer (https://github.com/caksoylar/keymap-drawer).
#
# Usage: ./draw.sh
# Output: docs/keymap.svg
#
# Needs keymap-drawer installed with pipx (see KEYMAP_DRAWER_VERSION below). The pre-commit hook in .githooks/ runs this
# automatically whenever config/corne.keymap changes; enable it once per clone with:
#   git config core.hooksPath .githooks
set -euo pipefail

KEYMAP_DRAWER_VERSION="0.23.0"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$REPO_DIR/keymap_drawer.config.yaml"
OUT="$REPO_DIR/docs/keymap.svg"

if ! command -v keymap >/dev/null 2>&1; then
  echo "keymap-drawer not found. Install it with: pipx install keymap-drawer==$KEYMAP_DRAWER_VERSION" >&2
  exit 1
fi

# Other versions may draw slightly different SVGs, which makes the pre-commit hook churn the file.
installed="$(pipx list --short 2>/dev/null | awk '$1 == "keymap-drawer" {print $2}' || true)"
if [ -n "$installed" ] && [ "$installed" != "$KEYMAP_DRAWER_VERSION" ]; then
  echo "Warning: keymap-drawer $installed is installed; this repo expects $KEYMAP_DRAWER_VERSION." >&2
  echo "  pipx install --force keymap-drawer==$KEYMAP_DRAWER_VERSION" >&2
fi

keymap() { command keymap -c "$CONFIG" "$@"; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

keymap parse -z "$REPO_DIR/config/corne.keymap" >"$tmp"
mkdir -p "$(dirname "$OUT")"
keymap draw "$tmp" -z corne -l foostan_corne_5col_layout >"$OUT"
echo "Wrote ${OUT#"$REPO_DIR"/}"

if [ "$(git -C "$REPO_DIR" config --get core.hooksPath || true)" != ".githooks" ]; then
  echo "Note: the pre-commit hook isn't enabled. Run: git config core.hooksPath .githooks" >&2
fi
