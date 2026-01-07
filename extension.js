import GObject from 'gi://GObject';
import St from 'gi://St';
import Gio from 'gi://Gio';
import Soup from 'gi://Soup';
import GLib from 'gi://GLib';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as MessageTray from 'resource:///org/gnome/shell/ui/messageTray.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const ApiShortcutIndicator = GObject.registerClass(
class ApiShortcutIndicator extends PanelMenu.Button {
    _init(extension) {
        super._init(0.0, 'API Shortcuts');
        this._extension = extension;
        this._settings = extension.getSettings();

        // Create icon for panel
        let icon = new St.Icon({
            icon_name: 'network-transmit-receive-symbolic',
            style_class: 'system-status-icon',
        });
        this.add_child(icon);

        // Add settings menu item
        this._settingsItem = new PopupMenu.PopupMenuItem('⚙ Settings');
        this._settingsItem.connect('activate', () => {
            this._extension.openPreferences();
        });
        this.menu.addMenuItem(this._settingsItem);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        // Load shortcuts and build menu
        this._buildMenu();

        // Watch for settings changes
        this._settingsChangedId = this._settings.connect('changed::shortcuts', () => {
            this._buildMenu();
        });
    }

    _buildMenu() {
        // Remove all shortcut items (keep settings item and separator)
        let items = this.menu._getMenuItems();
        items.forEach(item => {
            if (item !== this._settingsItem && item._isShortcutItem) {
                item.destroy();
            }
        });

        // Load shortcuts from settings
        let shortcuts = [];
        try {
            let data = this._settings.get_string('shortcuts');
            if (data) {
                shortcuts = JSON.parse(data);
            }
        } catch (e) {
            console.error('Failed to load shortcuts:', e);
        }

        // Add menu items for each shortcut
        shortcuts.forEach((shortcut) => {
            let item = new PopupMenu.PopupMenuItem(shortcut.label);
            item._isShortcutItem = true;
            item.connect('activate', () => {
                this._executeRequest(shortcut);
            });
            this.menu.addMenuItem(item);
        });

        if (shortcuts.length === 0) {
            let emptyItem = new PopupMenu.PopupMenuItem('No shortcuts configured');
            emptyItem.sensitive = false;
            emptyItem._isShortcutItem = true;
            this.menu.addMenuItem(emptyItem);
        }
    }

    async _executeRequest(shortcut) {
        console.log('[API Shortcuts] Executing request for:', shortcut.label);
        console.log('[API Shortcuts] URL:', shortcut.url);
        console.log('[API Shortcuts] Method:', shortcut.method);

        try {
            // Parse headers
            let headers = {};
            if (shortcut.headers) {
                shortcut.headers.split('\n').forEach(line => {
                    let [key, ...valueParts] = line.split(':');
                    if (key && valueParts.length > 0) {
                        headers[key.trim()] = valueParts.join(':').trim();
                    }
                });
            }
            console.log('[API Shortcuts] Headers:', JSON.stringify(headers));

            // Create HTTP session
            let session = new Soup.Session();
            let message = Soup.Message.new(shortcut.method, shortcut.url);

            // Set headers
            Object.keys(headers).forEach(key => {
                message.request_headers.append(key, headers[key]);
            });

            // Set body for POST/PUT/PATCH
            if (['POST', 'PUT', 'PATCH'].includes(shortcut.method) && shortcut.body) {
                console.log('[API Shortcuts] Request body:', shortcut.body);
                message.set_request_body_from_bytes(
                    'application/json',
                    new GLib.Bytes(shortcut.body)
                );
            }

            console.log('[API Shortcuts] Sending request...');
            // Send request
            let bytes = await session.send_and_read_async(
                message,
                GLib.PRIORITY_DEFAULT,
                null
            );

            let decoder = new TextDecoder('utf-8');
            let responseText = decoder.decode(bytes.get_data());

            console.log('[API Shortcuts] Response status:', message.status_code);
            console.log('[API Shortcuts] Response text:', responseText);

            // Check response status
            if (message.status_code >= 200 && message.status_code < 300) {
                // Try to parse response for a message
                let notificationBody = `Status: ${message.status_code}`;
                try {
                    let response = JSON.parse(responseText);
                    if (response.message) {
                        notificationBody = response.message;
                    } else if (responseText.length < 100) {
                        notificationBody = responseText;
                    }
                } catch (e) {
                    if (responseText.length < 100) {
                        notificationBody = responseText;
                    }
                }

                console.log('[API Shortcuts] Success notification:', notificationBody);
                this._showNotification(
                    '✓ ' + shortcut.label,
                    notificationBody
                );
            } else {
                throw new Error(`HTTP ${message.status_code}: ${message.reason_phrase}`);
            }
        } catch (e) {
            console.error('[API Shortcuts] Request failed:', e);
            console.error('[API Shortcuts] Error details:', e.message, e.stack);
            this._showNotification(
                '✗ ' + shortcut.label,
                `Error: ${e.message}`
            );
        }
    }

    _showNotification(title, body) {
        console.log('[API Shortcuts] Showing notification:', title, body);

        try {
            // Use Main.notify for simpler notification in GNOME Shell 48
            Main.notify(title, body);
            console.log('[API Shortcuts] Notification sent successfully');
        } catch (e) {
            console.error('[API Shortcuts] Failed to show notification:', e);

            // Fallback to OSD (on-screen display)
            try {
                Main.osdWindowManager.show(-1,
                    Gio.Icon.new_for_string('network-transmit-receive-symbolic'),
                    title + ': ' + body);
                console.log('[API Shortcuts] Showed OSD instead');
            } catch (e2) {
                console.error('[API Shortcuts] OSD also failed:', e2);
            }
        }
    }

    destroy() {
        if (this._settingsChangedId) {
            this._settings.disconnect(this._settingsChangedId);
        }
        super.destroy();
    }
});

export default class ApiShortcutsExtension extends Extension {
    enable() {
        this._indicator = new ApiShortcutIndicator(this);
        Main.panel.addToStatusArea('api-shortcuts', this._indicator);
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }
    }
}
