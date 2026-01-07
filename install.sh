#!/bin/bash

set -e

EXTENSION_UUID="api-shortcuts@guilhem-lavaux.eu"
EXTENSION_DIR="$HOME/.local/share/gnome-shell/extensions/$EXTENSION_UUID"

echo "Installing API Shortcuts extension..."

# Create extension directory
echo "Creating extension directory..."
mkdir -p "$EXTENSION_DIR/schemas"

# Copy files
echo "Copying files..."
cp extension.js "$EXTENSION_DIR/"
cp prefs.js "$EXTENSION_DIR/"
cp metadata.json "$EXTENSION_DIR/"
cp schemas/org.gnome.shell.extensions.api-shortcuts.gschema.xml "$EXTENSION_DIR/schemas/"

# Compile schema
echo "Compiling GSettings schema..."
glib-compile-schemas "$EXTENSION_DIR/schemas/"

echo ""
echo "✓ Installation complete!"
echo ""
echo "Next steps:"
echo "1. Restart GNOME Shell:"
echo "   - On X11: Press Alt+F2, type 'r', and press Enter"
echo "   - On Wayland: Log out and log back in"
echo ""
echo "2. Enable the extension:"
echo "   gnome-extensions enable $EXTENSION_UUID"
echo ""
echo "3. Click the network icon in the top bar to access your API shortcuts"

