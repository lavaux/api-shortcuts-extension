#!/bin/bash

# SPDX-FileCopyrightText: Guilhem Lavaux <code@guilhem-lavaux.eu>
# SPDX-License-Identifier: MIT

# Automated integration tests for the API Shortcuts GNOME Shell extension.
#
# The extension is installed inside a Fedora-based container running GNOME
# Shell on a virtual display (Xvfb for X11, headless for Wayland).
# Containers are provided by:
#   https://github.com/ddterm/gnome-shell-image
#
# Build the extension ZIP with pack.sh before calling this script.
#
# Arguments:
#   -v <version>  Fedora version (NOT the GNOME Shell version).
#                 The container image is ghcr.io/ddterm/gnome-shell-image:fedora-<version>.
#                   42  →  Fedora 42  =  GNOME Shell 48
#                   43  →  Fedora 43  =  GNOME Shell 49
#                   44  →  Fedora 44  =  GNOME Shell 50
#                   rawhide  →  latest development build
#   -s <session>  Display server: gnome-xsession | gnome-wayland-nested

set -e

usage() {
  echo "Usage: $0 -v fedora_version -s session" >&2
}

FEDORA_VERSION=42
SESSION="gnome-xsession"

while getopts "v:s:h" opt; do
  case $opt in
    v) FEDORA_VERSION="${OPTARG}";;
    s) SESSION="${OPTARG}";;
    h) usage; exit 0;;
    *) usage; exit 1;;
  esac
done

# ── repo root ────────────────────────────────────────────────────────────────

cd "$( cd "$( dirname "$0" )" && pwd )/.." || \
  { echo "ERROR: Could not find the repo root."; exit 1; }

EXTENSION_UUID="api-shortcuts@guilhem-lavaux.eu"
EXTENSION_ZIP="${EXTENSION_UUID}.shell-extension.zip"
IMAGE="ghcr.io/ddterm/gnome-shell-image:fedora-${FEDORA_VERSION}"
MOCK_PORT=18080

# ── container setup ──────────────────────────────────────────────────────────

# Create XDG runtime directory for Wayland/X11 session
XDG_RT_DIR=$(mktemp -d)
chmod 0700 "$XDG_RT_DIR"

# Container capabilities needed for Wayland and X11
CAPS="SYS_ADMIN,SYS_NICE,SYS_PTRACE,SETPCAP,NET_RAW,NET_BIND_SERVICE,IPC_LOCK"

POD=$(podman run --rm --cap-add="$CAPS" --security-opt=label=disable \
  -v "$XDG_RT_DIR:$XDG_RT_DIR" -e XDG_RUNTIME_DIR="$XDG_RT_DIR" \
  --user=0 --userns=keep-id --log-driver=none -td "${IMAGE}")

WORK_DIR=$(mktemp -d)
[[ -d "${WORK_DIR}" ]] || { echo "Failed to create tmp dir!" >&2; exit 1; }

# D-Bus address for session bus
DBUS_ADDR="unix:path=$XDG_RT_DIR/bus"

quit() {
  rm -rf "${WORK_DIR}" "${XDG_RT_DIR}"
  podman kill "${POD}"
  wait
}
trap quit INT TERM EXIT

# ── helpers ──────────────────────────────────────────────────────────────────

# Run a command inside the container as the gnomeshell user.
do_in_pod() {
  podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
    --workdir /home/gnomeshell "${POD}" "$@"
}

# Save a screenshot + full journal on failure, then exit 1.
fail() {
  local name="$1"
  local msg="$2"
  echo ""
  echo "FAIL: ${msg}" >&2
  mkdir -p tests/output
  # Try to capture screenshot based on session type
  if [ "$SESSION" = "gnome-xsession" ]; then
    podman cp "${POD}:/opt/Xvfb_screen0" - 2>/dev/null \
      | tar xf - --to-command "convert xwd:- tests/output/${name}" 2>/dev/null || true
  else
    # Wayland: use gnome-shell screenshot API
    podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
      "${POD}" gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot \
      --method org.gnome.Shell.Screenshot.Screenshot true false "tests/output/${name}" 2>/dev/null || true
  fi
  # Get journal logs
  podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
    "${POD}" journalctl --no-pager > tests/output/fail.log 2>&1 || true
  exit 1
}

# Copy the virtual screen from the container to WORK_DIR/screen.png.
capture_screen() {
  if [ "$SESSION" = "gnome-xsession" ]; then
    podman cp "${POD}:/opt/Xvfb_screen0" - 2>/dev/null \
      | tar xf - --to-command "convert xwd:- ${WORK_DIR}/screen.png" 2>/dev/null || true
  else
    # Wayland: use gnome-shell screenshot API
    podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
      "${POD}" gdbus call --session --dest org.gnome.Shell.Screenshot --object-path /org/gnome/Shell/Screenshot \
      --method org.gnome.Shell.Screenshot.Screenshot true false "${WORK_DIR}/screen.png" 2>/dev/null || true
  fi
}

# Press a key slowly enough for GNOME Shell to register it.
send_keystroke() {
  do_in_pod xdotool keydown "${1}"
  sleep 0.5
  do_in_pod xdotool keyup "${1}"
}

# Set an extension GSetting.
set_setting() {
  do_in_pod gsettings \
    --schemadir "/home/gnomeshell/.local/share/gnome-shell/extensions/${EXTENSION_UUID}/schemas" \
    set org.gnome.shell.extensions.api-shortcuts "${1}" "${2}"
}

# Start GNOME Shell session (X11 or Wayland)
start_gnome_session() {
  local session="$1"
  
  # Start D-Bus session bus
  podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
    "${POD}" dbus-daemon --session --nopidfile --syslog --fork "--address=$DBUS_ADDR"
  
  # Wait for dbus to be ready
  for i in $(seq 1 10); do
    if podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
      "${POD}" dbus-send --session --print-reply --dest=org.freedesktop.DBus \
      /org/freedesktop/DBus org.freedesktop.DBus.Peer.Ping 2>/dev/null; then
      break
    fi
    sleep 1
  done
  
  if [ "$session" = "gnome-xsession" ]; then
    # X11 with Xvfb
    mkfifo "$XDG_RT_DIR/display_pipe"
    podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" \
      "${POD}" sh -c "Xvfb -screen 0 1600x960x24 -nolisten tcp -displayfd 3 3>'${XDG_RT_DIR}/display_pipe'" &
    read -r DISPLAY_NUMBER <"$XDG_RT_DIR/display_pipe"
    podman exec --user=1000 -e DISPLAY=":$DISPLAY_NUMBER" -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
      "${POD}" gnome-shell --x11 --unsafe-mode &
  else
    # Wayland nested
    podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
      "${POD}" gnome-shell --wayland --headless --unsafe-mode --virtual-monitor 1600x960 &
  fi
  
  # Wait for GNOME Shell to start
  echo "Starting GNOME Shell..."
  for i in $(seq 1 60); do
    if podman exec --user=1000 -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
      "${POD}" gdbus wait --session --timeout=1 org.gnome.Shell 2>/dev/null; then
      break
    fi
    sleep 1
  done
  sleep 5
}

# ── container bootstrap ──────────────────────────────────────────────────────

echo "Forcing Cairo GTK rendering backend."
do_in_pod bash -c 'echo "export GSK_RENDERER=cairo" >> ~/.bash_profile'

# ── install extension ────────────────────────────────────────────────────────

echo "Installing ${EXTENSION_ZIP}."
podman cp "${EXTENSION_ZIP}" "${POD}:/home/gnomeshell"
do_in_pod gnome-extensions install "${EXTENSION_ZIP}"

# ── start GNOME Shell ────────────────────────────────────────────────────────

echo "Disabling welcome tour."
do_in_pod gsettings set org.gnome.shell welcome-dialog-last-shown-version "999" || true

do_in_pod gsettings set org.gnome.mutter center-new-windows true

echo "Starting GNOME Shell with ${SESSION} session."
start_gnome_session "$SESSION"

do_in_pod gnome-extensions enable "${EXTENSION_UUID}"

echo "Closing overview."
send_keystroke "super"
sleep 3

# ────────────────────────────────────────────────────────────────────────────
# TEST 1 – Extension enables cleanly
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "TEST 1: Extension enables without errors."

ENABLED=$(do_in_pod gnome-extensions list --enabled 2>&1)
if ! grep -q "${EXTENSION_UUID}" <<< "${ENABLED}"; then
  fail "not-enabled.png" \
    "Extension ${EXTENSION_UUID} is not in the enabled list!"
fi

JOURNAL=$(do_in_pod journalctl --no-pager -n 300 2>&1)
if echo "${JOURNAL}" | grep -q "api-shortcuts.*[Ee]rror\|${EXTENSION_UUID}.*[Ee]rror"; then
  fail "startup-error.png" \
    "Extension logged errors at startup — check tests/output/fail.log"
fi

echo "PASS: Extension is enabled and started without logged errors."

# ────────────────────────────────────────────────────────────────────────────
# TEST 2 – Preferences dialog (UI smoke test)
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "TEST 2: Preferences dialog opens without crashing."

do_in_pod gnome-extensions prefs "${EXTENSION_UUID}"
sleep 8

JOURNAL=$(do_in_pod journalctl --no-pager -n 300 2>&1)
if echo "${JOURNAL}" | grep -qi "gjs-CRITICAL\|extension.*crashed\|GNOME Shell.*crashed"; then
  fail "prefs-crash.png" \
    "GNOME Shell or the extension crashed while opening the preferences dialog!"
fi

# Save screenshot to tests/output/ for manual review / future references.
mkdir -p tests/output
capture_screen
cp "${WORK_DIR}/screen.png" \
   "tests/output/prefs-${SESSION}-${FEDORA_VERSION}.png"

echo "PASS: Preferences dialog opened (screenshot saved to tests/output/)."

send_keystroke "alt+F4"
sleep 2

# ────────────────────────────────────────────────────────────────────────────
# TEST 3 – HTTP GET via mock server (GJS Soup.Session)
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "TEST 3: HTTP GET request via Soup.Session."

# Start mock server (detached — stays alive until the pod is killed)
podman cp tests/mock-server.py "${POD}:/home/gnomeshell/mock-server.py"
podman exec --user=1000 -d -e XDG_RUNTIME_DIR="$XDG_RT_DIR" -e DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDR" \
  "${POD}" python3 /home/gnomeshell/mock-server.py "${MOCK_PORT}"
sleep 2

# Copy GJS test script
podman cp tests/test-http.js "${POD}:/home/gnomeshell/test-http.js"

# Run: non-zero exit propagates via set -e → fail
do_in_pod gjs -m /home/gnomeshell/test-http.js \
  "http://127.0.0.1:${MOCK_PORT}/api/test" "GET" "" \
  || fail "http-get-failed.png" "HTTP GET test via Soup.Session failed!"

echo "PASS: HTTP GET request succeeded."

# ────────────────────────────────────────────────────────────────────────────
# TEST 4 – HTTP POST via mock server (GJS Soup.Session)
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "TEST 4: HTTP POST request via Soup.Session."

do_in_pod gjs -m /home/gnomeshell/test-http.js \
  "http://127.0.0.1:${MOCK_PORT}/api/test" "POST" '{"key":"value"}' \
  || fail "http-post-failed.png" "HTTP POST test via Soup.Session failed!"

echo "PASS: HTTP POST request succeeded."

# ────────────────────────────────────────────────────────────────────────────
# TEST 5 – End-to-end: extension menu item triggers an HTTP request
# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "TEST 5: Extension menu item triggers HTTP request end-to-end."

# Configure one shortcut pointing at the mock server
TEST_SHORTCUT='[{"label":"Test GET","url":"http://127.0.0.1:'"${MOCK_PORT}"'/api/test","method":"GET","headers":"","body":""}]'
set_setting "shortcuts" "'${TEST_SHORTCUT}'"
sleep 2

# ── attempt A: trigger via GNOME Shell D-Bus eval ─────────────────────────
# org.gnome.Shell.Eval works when the shell is in development / test mode
# (the gnome-shell-pod containers enable this).  On failure we fall through
# to the xdotool approach.
DBUS_OK=false
do_in_pod gdbus call --session \
  --dest org.gnome.Shell \
  --object-path /org/gnome/Shell \
  --method org.gnome.Shell.Eval \
  "Main.panel.statusArea['api-shortcuts']._executeRequest({label:'Test GET',url:'http://127.0.0.1:${MOCK_PORT}/api/test',method:'GET',headers:'',body:''});" \
  2>/dev/null && DBUS_OK=true || true

if [[ "${DBUS_OK}" != "true" ]]; then
  echo "D-Bus eval not available; falling back to xdotool."

  # ── attempt B: click the panel button + navigate menu via keyboard ──────
  # The API shortcuts button lives in the system-status area on the right
  # side of the top bar.  In a typical 1280-wide virtual display it is
  # around x=1250; y=15 is safely within the 28-px-tall panel.
  do_in_pod bash -c 'xdotool mousemove 1250 15 && sleep 0.3 && xdotool click 1'
  sleep 1
  # "⚙ Settings" is the first item; separator is skipped automatically;
  # the first shortcut ("Test GET") is then one more Down press away.
  do_in_pod xdotool key Down
  sleep 0.3
  do_in_pod xdotool key Down
  sleep 0.3
  do_in_pod xdotool key Return
fi

sleep 4

# Verify that the extension's success-notification branch was reached
JOURNAL=$(do_in_pod journalctl --no-pager -n 400 2>&1)
if ! echo "${JOURNAL}" | grep -q "\[API Shortcuts\] Success notification"; then
  fail "e2e-failed.png" \
    "End-to-end test failed: no '[API Shortcuts] Success notification' in journal!"
fi

echo "PASS: Extension menu item triggered HTTP request successfully."

# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "All tests passed successfully."
