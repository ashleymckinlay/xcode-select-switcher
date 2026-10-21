#!/bin/zsh
# swiftDialog front end for xcode-select: lists every installed Xcode and the
# Command Line Tools, and switches the active developer directory.
#
# Works as a user (prompts for an admin password to switch) or as root, e.g.
# from Self Service, where the dialog appears for the logged-in user.
#
# Requires swiftDialog: https://github.com/swiftDialog/swiftDialog
#
# Usage: xcode-select-switcher.sh

set -euo pipefail

DIALOG="/usr/local/bin/dialog"
CLT="/Library/Developer/CommandLineTools"
TITLE="Xcode Switcher"
ICON="SF=hammer.circle.fill"
FIRST_LAUNCH="Run first launch tasks"

log() { /usr/bin/logger -t xcode-select-switcher "$*"; print -r -- "$*" >&2; }

if [[ ! -x "$DIALOG" ]]; then
  log "swiftDialog not found at ${DIALOG}"
  exit 1
fi

# Runs a command as root, asking for an admin password when we aren't root.
privileged() {
  if (( EUID == 0 )); then
    "$@"
    return
  fi
  /usr/bin/osascript - "$@" <<'OSA'
on run argv
  set cmd to ""
  repeat with a in argv
    set cmd to cmd & quoted form of (a as text) & " "
  end repeat
  do shell script cmd with administrator privileges
end run
OSA
}

plist_value() { /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true; }

# Finds Xcode bundles in the usual places plus anywhere Spotlight knows about.
typeset -U apps
apps=(
  /Applications/Xcode*.app(N)
  ${(f)"$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null)"}
)
apps=(${apps:#*/.Trash/*})

current="$(/usr/bin/xcode-select -p 2>/dev/null || true)"

# Parallel arrays: label shown in the dialog, developer dir it selects.
typeset -a labels devdirs
default_label=""

for app in $apps; do
  [[ -d "$app/Contents/Developer" ]] || continue
  version="$(plist_value "$app/Contents/Info.plist" CFBundleShortVersionString)"
  build="$(plist_value "$app/Contents/version.plist" ProductBuildVersion)"
  label="Xcode ${version:-?}${build:+ ($build)} - $app"
  labels+=("${label//,/}")   # swiftDialog splits select values on commas
  devdirs+=("$app/Contents/Developer")
done

if [[ -d "$CLT" ]]; then
  version="$(/usr/sbin/pkgutil --pkg-info com.apple.pkg.CLTools_Executables 2>/dev/null \
    | /usr/bin/awk '/^version:/ {print $2}')"
  labels+=("Command Line Tools ${version:-?} - $CLT")
  devdirs+=("$CLT")
fi

for i in {1..$#devdirs}; do
  [[ "${devdirs[i]}" == "$current" ]] && default_label="${labels[i]}"
done

if (( $#devdirs == 0 )); then
  "$DIALOG" --title "$TITLE" --icon "$ICON" --mini \
    --message "No Xcode or Command Line Tools installation was found." \
    --button1text "OK" || true
  exit 1
fi

message="Choose the developer directory used by \`xcodebuild\`, \`clang\`, \`git\` and other developer tools.

**Current:** \`${current:-not set}\`"

dialog_args=(
  --title "$TITLE"
  --icon "$ICON"
  --message "$message"
  --selecttitle "Developer directory"
  --selectvalues "${(j:,:)labels}"
  --selectstyle radio
  --checkbox "$FIRST_LAUNCH"
  --button1text "Switch"
  --button2text "Cancel"
  --infobuttontext "Reset to Default"
  --json
  --moveable
  --height 380
)
[[ -n "$default_label" ]] && dialog_args+=(--selectdefault "$default_label")

rc=0
result="$("$DIALOG" "${dialog_args[@]}")" || rc=$?

case $rc in
  0) ;;
  3)
    privileged /usr/bin/xcode-select --reset
    log "Reset developer directory to $(/usr/bin/xcode-select -p)"
    "$DIALOG" --title "$TITLE" --icon "$ICON" --mini \
      --message "Developer directory reset to \`$(/usr/bin/xcode-select -p)\`" || true
    exit 0
    ;;
  *) exit 0 ;;   # Cancel, closed or timed out
esac

index="$(print -r -- "$result" | /usr/bin/plutil -extract SelectedIndex raw -o - - 2>/dev/null || true)"
run_first_launch="$(print -r -- "$result" | /usr/bin/plutil -extract "$FIRST_LAUNCH" raw -o - - 2>/dev/null || true)"

if [[ "$index" != <-> ]] || (( index >= $#devdirs )); then
  log "No developer directory selected"
  exit 1
fi
target="${devdirs[index + 1]}"

# Switch, and optionally install the bundled packages, under one password prompt.
if [[ "$run_first_launch" == true && "$target" != "$CLT" ]]; then
  cmd=(/bin/sh -c '/usr/bin/xcode-select -s "$1" && /usr/bin/xcodebuild -runFirstLaunch' sh "$target")
else
  cmd=(/usr/bin/xcode-select -s "$target")
fi

if ! err="$(privileged "${cmd[@]}" 2>&1)"; then
  log "Failed to switch to ${target}: ${err}"
  "$DIALOG" --title "$TITLE" --icon "$ICON" --overlayicon caution --mini \
    --message "Could not switch to \`$target\`.

${err}" || true
  exit 1
fi

active="$(/usr/bin/xcode-select -p)"
details="$(/usr/bin/xcrun xcodebuild -version 2>/dev/null | /usr/bin/paste -sd ' ' - || true)"
log "Switched developer directory to ${active}"

"$DIALOG" --title "$TITLE" --icon "$ICON" --overlayicon SF=checkmark.circle.fill,colour=green --mini \
  --message "Now using \`$active\`${details:+

$details}" || true
