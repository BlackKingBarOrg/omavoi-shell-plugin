#!/usr/bin/env bash
#
# The three things a plugin cannot add for itself: the systemd user unit, a
# Hyprland keybinding, and a row in the Omarchy menu.
#
# Omarchy's manifest has no field for any of them, and `omarchy plugin add`
# deliberately runs nothing from inside a plugin -- a plugin lands in a
# trusted directory and is not itself trusted. So this is a command you run
# once, by hand, and it tells you exactly what it changed.
#
#   ~/.config/omarchy/plugins/ai.bkblab.omavoi/install.sh
#   ~/.config/omarchy/plugins/ai.bkblab.omavoi/install.sh --remove
#
# Both files are edited between markers, so running it twice changes nothing
# and --remove takes out exactly what was added.

set -euo pipefail

PLUGIN_ID="ai.bkblab.omavoi"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
BEGIN="-- >>> omavoi"
END="-- <<< omavoi"
REMOVE=0
[[ "${1:-}" == "--remove" ]] && REMOVE=1

say() { printf '  %s\n' "$*"; }

strip_block() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  # `--` before the pattern: BEGIN starts with "--", which grep otherwise
  # reads as an option, so this test silently never matched. The block was
  # never stripped, which made the script append a duplicate every run and
  # left --remove with nothing to remove.
  if grep -qF -- "$BEGIN" "$file"; then
    local tmp; tmp="$(mktemp)"
    awk -v b="$BEGIN" -v e="$END" '
      index($0, b) { skip = 1 } !skip { print } index($0, e) { skip = 0 }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
    say "removed the omavoi block from $file"
  fi
}

if (( REMOVE )); then
  echo "Removing Omavoi shortcuts"
  strip_block "$BINDINGS"
  if systemctl --user list-unit-files omavoid.service &>/dev/null; then
    systemctl --user disable --now omavoid.service 2>/dev/null || true
    say "disabled omavoid.service"
  fi
  rm -f "$UNIT_DIR/omavoid.service" && say "removed the unit file"
  systemctl --user daemon-reload
  echo "Done. The plugin itself is still installed; remove it with:"
  echo "  omarchy plugin remove $PLUGIN_ID"
  exit 0
fi

echo "Installing Omavoi shortcuts"

# 1. The daemon, as a user service.
mkdir -p "$UNIT_DIR"
install -m 0644 "$HERE/omavoid.service" "$UNIT_DIR/omavoid.service"
say "installed $UNIT_DIR/omavoid.service"
systemctl --user daemon-reload

if command -v omavoi >/dev/null; then
  systemctl --user enable --now omavoid.service && say "started omavoid.service"
else
  say "omavoi is not on PATH yet -- install it, then: systemctl --user enable --now omavoid"
fi

# 2. Keybindings. The console gets SUPER+ALT+V.
#
# The dictation key itself is NOT bound here. It is read from evdev inside the
# daemon, because binding a modifier in Hyprland fights itself: pressing one
# changes the modmask, which fires the release binding immediately and records
# a 0.0s take. If you are not in the `input` group yet, uncomment the F9 lines
# below -- a non-modifier key does work through Hyprland.
if [[ -f "$BINDINGS" ]]; then
  strip_block "$BINDINGS"
  cat >> "$BINDINGS" <<'LUA'

-- >>> omavoi
o.bind("SUPER + ALT + V", "Omavoi console", "omarchy-shell shell toggle ai.bkblab.omavoi")
-- Not in the `input` group yet? Uncomment these two for a working key today.
-- Modifier keys cannot be used this way; a plain key like F9 can.
-- o.bind("F9", "Dictate", "omavoi record start")
-- o.bindr("F9", "Dictate (release)", "omavoi record stop")
-- <<< omavoi
LUA
  say "added the omavoi block to $BINDINGS"
else
  say "no $BINDINGS -- skipped the keybinding"
fi

echo
echo "Next:"
echo "  omavoi setup      # shows what is still missing, with the command for each"
