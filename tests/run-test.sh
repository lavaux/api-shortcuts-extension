#!/bin/bash

# SPDX-FileCopyrightText: Guilhem Lavaux <code@guilhem-lavaux.eu>
# SPDX-License-Identifier: MIT

# Automated integration tests for the API Shortcuts GNOME Shell extension.
#
# The extension is installed inside a Fedora-based container running GNOME
# Shell on a virtual display (Xvfb).  Containers are provided by:
#   https://github.com/Schneegans/gnome-shell-pod
#
# Build the extension ZIP with pack.sh before calling this script.
#
# Arguments:
#   -v <version>  Fedora version (NOT the GNOME Shell version).
#                 The container image is ghcr.io/schneegans/gnome-shell-pod-<version>.
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
IMAGE="ghcr.io/schneegans/gnome-shell-pod-${FEDORA_VERSION}"
MOCK_PORT=18080

# ── container setup ──────────────────────────────────────────────────────────

POD=$(podman run --rm --cap-add=SYS_NICE --cap-add=IPC_LOCK -td "${IMAGE}")

WORK_DIR=$(mktemp -d)
[[ -d "${WORK_DIR}" ]] || { echo "Failed to create tmp dir!" >&2; exit 1; }

quit() {
  rm -rf "${WORK_DIR}"
  podman kill "${POD}"
  wait
}
trap quit INT TERM EXIT

# ── helpers ──────────────────────────────────────────────────────────────────

# Run a command inside the container as the gnomeshell user.
do_in_pod() {
  podman exec --user gnomeshell --workdir /home/gnomeshell "${POD}" set-env.sh "$@"
}

# Save a screenshot + full journal on failure, then exit 1.
fail() {
  local name="$1"
  local msg="$2"
  echo ""
  echo "FAIL: ${msg}" >&2
  mkdir -p tests/output
  podman cp "${POD}:/opt/Xvfb_screen0" - 2>/dev/null \
    | tar xf - --to-command "convert xwd:- tests/output/${name}" 2>/dev/null || true
  do_in_pod sudo journalctl --no-pager > tests/output/fail.log 2>&1 || true
  exit 1
}

# Copy the virtual screen from the container to WORK_DIR/screen.png.
capture_screen() {
  podman cp "${POD}:/opt/Xvfb_screen0" - \
    | tar xf - --to-command "convert xwd:- ${WORK_DIR}/screen.png"
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

# ── container bootstrap ──────────────────────────────────────────────────────

echo "Forcing Cairo GTK rendering backend."
do_in_pod bash -c 'echo "export GSK_RENDERER=cairo" >> ~/.bash_profile'

echo "Waiting for D-Bus."
sleep 5

# ── install extension ────────────────────────────────────────────────────────

echo "Installing ${EXTENSION_ZIP}."
podman cp "${EXTENSION_ZIP}" "${POD}:/home/gnomeshell"
do_in_pod gnome-extensions install "${EXTENSION_ZIP}"

# ── start GNOME Shell ────────────────────────────────────────────────────────

echo "Disabling welcome tour."
do_in_pod gsettings set org.gnome.shell welcome-dialog-last-shown-version "999" || true

do_in_pod gsettings set org.gnome.mutter center-new-windows true

echo "Starting $(do_in_pod gnome-shell --version)."
do_in_pod systemctl --user start "${SESSION}@:99"
sleep 10

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

JOURNAL=$(do_in_pod sudo journalctl --no-pager -n 300 2>&1)
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

JOURNAL=$(do_in_pod sudo journalctl --no-pager -n 300 2>&1)
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
podman exec --user gnomeshell -d "${POD}" \
  python3 /home/gnomeshell/mock-server.py "${MOCK_PORT}"
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
JOURNAL=$(do_in_pod sudo journalctl --no-pager -n 400 2>&1)
if ! echo "${JOURNAL}" | grep -q "\[API Shortcuts\] Success notification"; then
  fail "e2e-failed.png" \
    "End-to-end test failed: no '[API Shortcuts] Success notification' in journal!"
fi

echo "PASS: Extension menu item triggered HTTP request successfully."

# ────────────────────────────────────────────────────────────────────────────

echo ""
echo "All tests passed successfully."
