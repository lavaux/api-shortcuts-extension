# API Shortcuts for GNOME Shell

A GNOME Shell extension that allows you to execute HTTP/HTTPS REST API requests directly from the top bar menu.

## Features

- 🚀 Quick access to API endpoints from the GNOME Shell top bar
- 🔧 Full HTTP method support (GET, POST, PUT, PATCH, DELETE)
- 🔐 Custom HTTP headers for authentication
- 📝 JSON request body support for POST/PUT/PATCH
- 🔔 Desktop notifications for success/failure responses
- ⚙️ Easy-to-use settings dialog
- 💾 Import/Export shortcuts for backup and sharing
- 📊 Debug logging for troubleshooting

## Installation

### From Source

1. Clone or download this repository

2. Run the installation script:
```bash
./install.sh
```

3. Restart GNOME Shell:
   - On X11: Press `Alt+F2`, type `r`, and press Enter
   - On Wayland: Log out and log back in

4. Enable the extension:
```bash
gnome-extensions enable api-shortcuts@your-domain.com
```

### Manual Installation

1. Create the extension directory:
```bash
mkdir -p ~/.local/share/gnome-shell/extensions/api-shortcuts@your-domain.com
```

2. Copy all files to the extension directory:
```bash
cp -r * ~/.local/share/gnome-shell/extensions/api-shortcuts@your-domain.com/
```

3. Compile the GSettings schema:
```bash
glib-compile-schemas ~/.local/share/gnome-shell/extensions/api-shortcuts@your-domain.com/schemas/
```

4. Restart GNOME Shell and enable the extension

## Usage

### Creating a Shortcut

1. Click the network icon in the top bar
2. Select "⚙ Settings"
3. Click "Add New Shortcut"
4. Fill in the details:
   - **Label**: Display name for the menu
   - **URL**: Full API endpoint URL
   - **HTTP Method**: GET, POST, PUT, PATCH, or DELETE
   - **HTTP Headers** (optional): One per line in format `Header-Name: value`
   - **Request Body** (optional): JSON body for POST/PUT/PATCH requests

5. Click "Save"

### Example Configuration

**Simple GET request:**
- Label: `Check API Status`
- URL: `https://api.example.com/status`
- Method: `GET`

**POST with authentication:**
- Label: `Create User`
- URL: `https://api.example.com/users`
- Method: `POST`
- Headers:
  ```
  Content-Type: application/json
  Authorization: Bearer your-token-here
  ```
- Body:
  ```json
  {
    "name": "John Doe",
    "email": "john@example.com"
  }
  ```

### Import/Export

**Export shortcuts:**
1. Open Settings
2. Click "Export Shortcuts"
3. Choose where to save the JSON file

**Import shortcuts:**
1. Open Settings
2. Click "Import Shortcuts"
3. Select a JSON file
4. Choose to either replace all shortcuts or add to existing ones

## Troubleshooting

### View Extension Logs

```bash
# View extension logs (API requests, notifications)
journalctl -f -o cat /usr/bin/gnome-shell | grep "API Shortcuts"

# View preferences logs (import/export, settings)
gnome-extensions prefs api-shortcuts@your-domain.com
```

### Common Issues

**No notifications appear:**
- Check the logs for error messages
- Verify your API endpoint is accessible
- Check that the URL includes the protocol (http:// or https://)

**Extension doesn't appear in top bar:**
- Ensure the extension is enabled: `gnome-extensions list`
- Check for errors: `journalctl -f -o cat /usr/bin/gnome-shell`
- Try restarting GNOME Shell

**Import doesn't work:**
- Verify the JSON file has the correct format (see exported file for reference)
- Check the terminal output when running: `gnome-extensions prefs api-shortcuts@your-domain.com`

## Development

### File Structure

```
api-shortcuts@your-domain.com/
├── extension.js           # Main extension code
├── prefs.js              # Preferences/settings UI
├── metadata.json         # Extension metadata
├── schemas/
│   └── org.gnome.shell.extensions.api-shortcuts.gschema.xml
├── README.md
├── install.sh            # Installation script
└── pack.sh              # Packaging script
```

### Building a Distribution Package

```bash
./pack.sh
```

This creates `api-shortcuts@your-domain.com.shell-extension.zip` ready for distribution.

## Requirements

- GNOME Shell 48 or later
- GLib 2.0
- Soup 3.0

## License

This extension is provided as-is for personal and commercial use.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Changelog

### Version 1.0
- Initial release
- HTTP/HTTPS REST API support
- All HTTP methods (GET, POST, PUT, PATCH, DELETE)
- Custom headers support
- JSON request body support
- Desktop notifications
- Import/Export functionality
- Debug logging

