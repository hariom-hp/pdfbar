#!/bin/bash
#
# PDFBar installer — one command, no dependencies, fully local afterwards.
#
#   curl -fsSL https://raw.githubusercontent.com/hariom-hp/pdfbar/main/install.sh | bash
#
# Options (pass after `bash -s --` when piping):
#   --from-source   compile locally instead of downloading the release
#   --no-login      don't register the menu bar app to start at login
#   --uninstall     remove the app, login item and support files
#   --verify        run the built-in self-test after installing
#
set -euo pipefail

APP_NAME="PDFBar"
BUNDLE_ID="dev.pdfbar.app"
REPO="hariom-hp/pdfbar"
ASSET_URL="https://github.com/${REPO}/releases/latest/download/${APP_NAME}.zip"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${BUNDLE_ID}.plist"

WANT_LOGIN=1
WANT_VERIFY=0
FROM_SOURCE=0
UNINSTALL=0

for arg in "$@"; do
  case "${arg}" in
    --from-source) FROM_SOURCE=1 ;;
    --no-login)    WANT_LOGIN=0 ;;
    --uninstall)   UNINSTALL=1 ;;
    --verify)      WANT_VERIFY=1 ;;
    -h|--help)
      sed -n '2,14p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  \033[34m→\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

unload_agent() {
  launchctl bootout "gui/$(id -u)/${BUNDLE_ID}" >/dev/null 2>&1 || \
    launchctl unload "${AGENT_PLIST}" >/dev/null 2>&1 || true
}

stop_app() {
  pkill -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------ uninstall
if [ "${UNINSTALL}" -eq 1 ]; then
  bold "Uninstalling ${APP_NAME}"
  stop_app
  unload_agent
  rm -f "${AGENT_PLIST}"
  for candidate in "/Applications/${APP_NAME}.app" "${HOME}/Applications/${APP_NAME}.app"; do
    [ -d "${candidate}" ] && rm -rf "${candidate}" && ok "Removed ${candidate}"
  done
  [ -d "${HOME}/Downloads/PDFBar" ] && warn "Left your output folder at ~/Downloads/PDFBar"
  ok "Done."
  exit 0
fi

bold "Installing ${APP_NAME}"

# ------------------------------------------------------------------ pre-flight
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "${MACOS_MAJOR}" -ge 14 ] || die "macOS 14 (Sonoma) or newer is required — this Mac runs $(sw_vers -productVersion)."
ok "macOS $(sw_vers -productVersion) · $(uname -m)"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
STAGE="${WORK}/${APP_NAME}.app"

# ------------------------------------------------------------------ acquire
if [ "${FROM_SOURCE}" -eq 1 ]; then
  command -v swift >/dev/null 2>&1 || die "Swift is missing. Install it with: xcode-select --install"
  SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
  [ -f "${SRC_DIR}/build.sh" ] || die "--from-source must be run from a checkout of the repo."
  info "Compiling from source…"
  "${SRC_DIR}/build.sh" >/dev/null
  cp -R "${SRC_DIR}/${APP_NAME}.app" "${STAGE}"
  ok "Built locally"
else
  info "Downloading the latest release…"
  if ! curl -fsSL --retry 2 --connect-timeout 15 -o "${WORK}/${APP_NAME}.zip" "${ASSET_URL}"; then
    warn "Download failed."
    if command -v swift >/dev/null 2>&1; then
      die "No release asset found. Clone the repo and run: ./install.sh --from-source"
    fi
    die "No release asset found and Swift is not installed, so this Mac cannot build from source."
  fi
  ditto -x -k "${WORK}/${APP_NAME}.zip" "${WORK}/extracted" || die "The download was not a valid archive."
  [ -d "${WORK}/extracted/${APP_NAME}.app" ] || die "The archive did not contain ${APP_NAME}.app."
  cp -R "${WORK}/extracted/${APP_NAME}.app" "${STAGE}"
  ok "Downloaded $(du -sh "${WORK}/${APP_NAME}.zip" | cut -f1 | tr -d ' ')"
fi

# ------------------------------------------------------------------ install
DEST="/Applications/${APP_NAME}.app"
if [ ! -w "/Applications" ]; then
  DEST="${HOME}/Applications/${APP_NAME}.app"
  mkdir -p "${HOME}/Applications"
  warn "/Applications is read-only here — installing to ~/Applications instead."
fi

stop_app
rm -rf "${DEST}"
cp -R "${STAGE}" "${DEST}"
# The download carries a quarantine flag; an ad-hoc signed app cannot pass
# Gatekeeper's notarisation check, so clear it.
xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true
codesign --force --deep --sign - "${DEST}" >/dev/null 2>&1 || \
  warn "Ad-hoc re-signing failed — the app should still launch."
ok "Installed to ${DEST}"

# ------------------------------------------------------------------ login item
if [ "${WANT_LOGIN}" -eq 1 ]; then
  mkdir -p "$(dirname "${AGENT_PLIST}")"
  cat > "${AGENT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${BUNDLE_ID}</string>
	<key>ProgramArguments</key>
	<array>
		<string>${DEST}/Contents/MacOS/${APP_NAME}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST
  unload_agent
  if launchctl bootstrap "gui/$(id -u)" "${AGENT_PLIST}" >/dev/null 2>&1; then
    ok "Starts automatically at login"
  else
    warn "Could not add the login item — add PDFBar under System Settings › General › Login Items."
  fi
fi

# ------------------------------------------------------------------ verify
if [ "${WANT_VERIFY}" -eq 1 ]; then
  info "Running the self-test…"
  if "${DEST}/Contents/MacOS/${APP_NAME}" --selftest 2>/dev/null | tail -2; then
    ok "Self-test passed"
  else
    warn "Self-test reported a failure — see the output above."
  fi
fi

# ------------------------------------------------------------------ launch
mkdir -p "${HOME}/Downloads/PDFBar"
if pgrep -f "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" >/dev/null 2>&1; then
  ok "Running"
else
  open "${DEST}"
  ok "Launched"
fi

bold ""
bold "PDFBar is in your menu bar."
echo "  • Left-click  → the full tool window"
echo "  • Right-click → every tool, grouped by category"
echo "  • Results     → ~/Downloads/PDFBar"
echo ""
echo "  Uninstall:  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --uninstall"
