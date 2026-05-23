# API Shortcuts — GNOME Shell Extension

Execute HTTP/REST API requests directly from the GNOME top-panel menu.

## Key facts

| Item | Value |
|------|-------|
| Extension UUID | `api-shortcuts@guilhem-lavaux.eu` |
| Settings schema | `org.gnome.shell.extensions.api-shortcuts` |
| Supported GNOME Shell | 48, 49, 50 |
| Main source files | `extension.js`, `prefs.js` |

## Build & install

```bash
# Pack into a distributable ZIP (requires gettext for glib-compile-schemas)
bash pack.sh
# → api-shortcuts@guilhem-lavaux.eu.shell-extension.zip

# Install directly into your user profile
bash install.sh
# Re-login or: gnome-extensions enable api-shortcuts@guilhem-lavaux.eu
```

## Running tests

Tests run the extension inside a [gnome-shell-pod](https://github.com/Schneegans/gnome-shell-pod)
container via **Podman**.  Build the ZIP first, then:

```bash
bash pack.sh
bash tests/run-test.sh -v 42 -s gnome-xsession
# -v  Fedora version — NOT the GNOME Shell version:
#       42 = GNOME Shell 48 | 43 = GNOME Shell 49 | 44 = GNOME Shell 50
# -s  Display server (gnome-xsession | gnome-wayland-nested)
```

On failure, screenshots and the full `journalctl` log are written to
`tests/output/`.

### What the test suite covers

| # | Test | Mechanism |
|---|------|-----------|
| 1 | Extension enables cleanly | `gnome-extensions list --enabled` + journal check |
| 2 | Preferences dialog (UI) | `gnome-extensions prefs` + crash journal check + screenshot |
| 3 | HTTP GET via `Soup.Session` | GJS standalone script (`tests/test-http.js`) against mock server |
| 4 | HTTP POST via `Soup.Session` | Same GJS script, POST method with JSON body |
| 5 | End-to-end menu → HTTP request | D-Bus `Shell.Eval` (with xdotool fallback) + journal assertion |

### Supporting test files

- **`tests/mock-server.py`** — Python 3 HTTP server (stdlib only) that returns
  JSON for GET / POST / PUT / PATCH / DELETE.  Started detached inside the
  container; killed automatically when the pod is torn down.
- **`tests/test-http.js`** — GJS ES-module (`gjs -m`) that mirrors the
  extension's `_executeRequest()` logic.  Exits 0 on 2xx, 1 otherwise.

## Linting

```bash
cd tools && npm install   # first time only
bash tools/run-eslint.sh
```

Uses [`eslint-config-gnome`](https://gitlab.gnome.org/GNOME/eslint-config-gnome)
with strict JSDoc rules for public APIs.

## CI / CD

GitHub Actions (`.github/workflows/tests.yml`) runs the full matrix on:
- every PR
- pushes to `main` (unless the commit message contains `[no-ci]`)
- any branch when the commit message contains `[run-ci]`

Matrix: GNOME Shell versions **48 × 49 × 50** × sessions **gnome-xsession ×
gnome-wayland-nested** (6 jobs total).

Failure artifacts (screenshots + journal log) are uploaded under
`test-output_<version>_<session>`.

## Release

Releases use [semantic-release](https://semantic-release.gitbook.io/) with
conventional commits:

```bash
npm run release          # dry-run
bash new-release.sh --force   # actual release (updates metadata.json + CHANGELOG.md)
```

Release rules: `feat` → minor, `fix` → patch, `docs`/`refactor`/`style` → patch.

## Architecture notes

- **`extension.js`** — `ApiShortcutIndicator` (`PanelMenu.Button` subclass).
  Reads shortcuts from GSettings as a JSON string, builds a `PopupMenu`, and
  sends HTTP requests with `Soup.Session` (async/await pattern).
  Notifications via `Main.notify()` with OSD fallback.
- **`prefs.js`** — `ApiShortcutsPreferences` (`ExtensionPreferences` subclass).
  Full Adwaita UI for adding/editing/deleting shortcuts with per-shortcut
  label, URL, HTTP method, headers, and JSON body.  Import/Export via
  `Gtk.FileDialog`.
- **`schemas/`** — Single GSettings key `shortcuts` (type `s`, default `'[]'`)
  storing the shortcuts as a serialised JSON array.
