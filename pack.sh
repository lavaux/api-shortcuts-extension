#!/bin/bash

set -e

EXTENSION_UUID="api-shortcuts@guilhem-lavaux.eu"
OUTPUT_FILE="$EXTENSION_UUID.shell-extension.zip"

echo "Packing API Shortcuts extension..."

# Remove old package if exists
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing old package..."
    rm "$OUTPUT_FILE"
fi

# Create temporary directory
TEMP_DIR=$(mktemp -d)
PACK_DIR="$TEMP_DIR/$EXTENSION_UUID"
mkdir -p "$PACK_DIR/schemas"

echo "Copying files..."
cp extension.js "$PACK_DIR/"
cp prefs.js "$PACK_DIR/"
cp metadata.json "$PACK_DIR/"
cp schemas/org.gnome.shell.extensions.api-shortcuts.gschema.xml "$PACK_DIR/schemas/"

# Compile schema
echo "Compiling schema..."
glib-compile-schemas "$PACK_DIR/schemas/"

# Create zip package
echo "Creating package..."
cd "$PACK_DIR"
zip -r "$OUTPUT_FILE" ./*

# Move package to current directory
mv "$OUTPUT_FILE" "$OLDPWD/"

# Cleanup
cd "$OLDPWD"
rm -rf "$TEMP_DIR"

echo ""
echo "✓ Package created: $OUTPUT_FILE"
echo ""
echo "To install on another system:"
echo "  gnome-extensions install $OUTPUT_FILE"
echo ""
echo "Or manually extract to:"
echo "  ~/.local/share/gnome-shell/extensions/$EXTENSION_UUID/"

