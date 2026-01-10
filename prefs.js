import Gtk from 'gi://Gtk';
import Gio from 'gi://Gio';
import Adw from 'gi://Adw';
import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import {ExtensionPreferences} from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

const ShortcutRow = GObject.registerClass({
    GTypeName: 'ShortcutRow',
}, class ShortcutRow extends Adw.PreferencesRow {
    _init(shortcut, onEdit, onDelete) {
        super._init();

        const box = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            spacing: 12,
            margin_start: 12,
            margin_end: 12,
            margin_top: 12,
            margin_bottom: 12,
        });

        // Label and method
        const labelBox = new Gtk.Box({
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 4,
            hexpand: true,
        });

        const labelText = new Gtk.Label({
            label: shortcut.label,
            halign: Gtk.Align.START,
            css_classes: ['title'],
        });

        const methodUrl = new Gtk.Label({
            label: `${shortcut.method} ${shortcut.url}`,
            halign: Gtk.Align.START,
            css_classes: ['dim-label', 'caption'],
            ellipsize: 3, // PANGO_ELLIPSIZE_END
        });

        labelBox.append(labelText);
        labelBox.append(methodUrl);

        // Edit button
        const editButton = new Gtk.Button({
            icon_name: 'document-edit-symbolic',
            valign: Gtk.Align.CENTER,
        });
        editButton.connect('clicked', () => onEdit());

        // Delete button
        const deleteButton = new Gtk.Button({
            icon_name: 'user-trash-symbolic',
            valign: Gtk.Align.CENTER,
        });
        deleteButton.connect('clicked', () => onDelete());

        box.append(labelBox);
        box.append(editButton);
        box.append(deleteButton);

        this.set_child(box);
    }
});

export default class ApiShortcutsPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        this._settings = this.getSettings();

        const page = new Adw.PreferencesPage();
        window.add(page);

        // Import/Export group
        const importExportGroup = new Adw.PreferencesGroup({
            title: 'Import/Export',
            description: 'Backup and restore your shortcuts',
        });
        page.add(importExportGroup);

        // Export button
        const exportRow = new Adw.ActionRow({
            title: 'Export Shortcuts',
            subtitle: 'Save shortcuts to a JSON file',
        });
        const exportButton = new Gtk.Button({
            icon_name: 'document-save-symbolic',
            valign: Gtk.Align.CENTER,
        });
        exportButton.connect('clicked', () => {
            this._exportShortcuts(window);
        });
        exportRow.add_suffix(exportButton);
        importExportGroup.add(exportRow);

        // Import button
        const importRow = new Adw.ActionRow({
            title: 'Import Shortcuts',
            subtitle: 'Load shortcuts from a JSON file',
        });
        const importButton = new Gtk.Button({
            icon_name: 'document-open-symbolic',
            valign: Gtk.Align.CENTER,
        });
        importButton.connect('clicked', () => {
            this._importShortcuts(window);
        });
        importRow.add_suffix(importButton);
        importExportGroup.add(importRow);

        // Shortcuts group
        const group = new Adw.PreferencesGroup({
            title: 'API Shortcuts',
            description: 'Configure your API shortcuts',
        });
        page.add(group);

        // Add button
        const addRow = new Adw.ActionRow({
            title: 'Add New Shortcut',
        });

        const addButton = new Gtk.Button({
            icon_name: 'list-add-symbolic',
            valign: Gtk.Align.CENTER,
        });
        addButton.connect('clicked', () => {
            this._showEditDialog(window, null);
        });
        addRow.add_suffix(addButton);
        group.add(addRow);

        // List container
        this._listBox = new Gtk.ListBox({
            selection_mode: Gtk.SelectionMode.NONE,
            css_classes: ['boxed-list'],
        });
        group.add(this._listBox);

        // Load shortcuts
        this._loadShortcuts();

        // Watch for changes
        this._settingsChangedId = this._settings.connect('changed::shortcuts', () => {
            this._loadShortcuts();
        });
    }

    _loadShortcuts() {
        // Clear existing rows
        let child = this._listBox.get_first_child();
        while (child) {
            const next = child.get_next_sibling();
            this._listBox.remove(child);
            child = next;
        }

        // Load shortcuts from settings
        let shortcuts = [];
        try {
            const data = this._settings.get_string('shortcuts');
            if (data)
                shortcuts = JSON.parse(data);
        } catch (e) {
            console.error('Failed to load shortcuts:', e);
        }

        // Add rows
        shortcuts.forEach((shortcut, index) => {
            const row = new ShortcutRow(
                shortcut,
                () => this._showEditDialog(this._listBox.get_root(), shortcut, index),
                () => this._deleteShortcut(index)
            );
            this._listBox.append(row);
        });

        if (shortcuts.length === 0) {
            const emptyLabel = new Gtk.Label({
                label: 'No shortcuts configured yet',
                margin_top: 24,
                margin_bottom: 24,
                css_classes: ['dim-label'],
            });
            this._listBox.append(emptyLabel);
        }
    }

    _showEditDialog(parent, shortcut, index) {
        const dialog = new Adw.Dialog({
            title: shortcut ? 'Edit Shortcut' : 'New Shortcut',
            content_width: 600,
            content_height: 700,
        });

        const toolbar = new Adw.ToolbarView();
        const header = new Adw.HeaderBar();
        toolbar.add_top_bar(header);

        const content = new Adw.PreferencesPage();
        const group = new Adw.PreferencesGroup();
        content.add(group);

        // Label entry
        const labelRow = new Adw.EntryRow({
            title: 'Label',
        });
        if (shortcut)
            labelRow.text = shortcut.label;
        group.add(labelRow);

        // URL entry
        const urlRow = new Adw.EntryRow({
            title: 'URL',
        });
        if (shortcut)
            urlRow.text = shortcut.url;
        group.add(urlRow);

        // Method dropdown
        const methodRow = new Adw.ComboRow({
            title: 'HTTP Method',
        });
        const methodModel = Gtk.StringList.new(['GET', 'POST', 'PUT', 'PATCH', 'DELETE']);
        methodRow.model = methodModel;
        if (shortcut) {
            const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
            methodRow.selected = methods.indexOf(shortcut.method);
        }
        group.add(methodRow);

        // Headers
        const headersExpander = new Adw.ExpanderRow({
            title: 'HTTP Headers',
            subtitle: 'One per line: Header-Name: value',
        });
        group.add(headersExpander);

        const headersBuffer = new Gtk.TextBuffer();
        if (shortcut && shortcut.headers)
            headersBuffer.set_text(shortcut.headers, -1);

        const headersView = new Gtk.TextView({
            buffer: headersBuffer,
            top_margin: 12,
            bottom_margin: 12,
            left_margin: 12,
            right_margin: 12,
            height_request: 120,
        });
        const headersScroll = new Gtk.ScrolledWindow({
            child: headersView,
            vexpand: true,
        });
        headersExpander.add_row(new Adw.PreferencesRow({child: headersScroll}));

        // Body
        const bodyExpander = new Adw.ExpanderRow({
            title: 'Request Body (JSON)',
            subtitle: 'For POST/PUT/PATCH requests',
        });
        group.add(bodyExpander);

        const bodyBuffer = new Gtk.TextBuffer();
        if (shortcut && shortcut.body)
            bodyBuffer.set_text(shortcut.body, -1);

        const bodyView = new Gtk.TextView({
            buffer: bodyBuffer,
            top_margin: 12,
            bottom_margin: 12,
            left_margin: 12,
            right_margin: 12,
            height_request: 120,
            monospace: true,
        });
        const bodyScroll = new Gtk.ScrolledWindow({
            child: bodyView,
            vexpand: true,
        });
        bodyExpander.add_row(new Adw.PreferencesRow({child: bodyScroll}));

        // Buttons
        const buttonBox = new Gtk.Box({
            orientation: Gtk.Orientation.HORIZONTAL,
            spacing: 6,
            margin_top: 24,
            margin_bottom: 12,
            margin_start: 12,
            margin_end: 12,
            halign: Gtk.Align.END,
        });

        const cancelButton = new Gtk.Button({
            label: 'Cancel',
        });
        cancelButton.connect('clicked', () => dialog.close());

        const saveButton = new Gtk.Button({
            label: 'Save',
            css_classes: ['suggested-action'],
        });
        saveButton.connect('clicked', () => {
            const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];
            const newShortcut = {
                label: labelRow.text,
                url: urlRow.text,
                method: methods[methodRow.selected],
                headers: headersBuffer.text,
                body: bodyBuffer.text,
            };

            this._saveShortcut(newShortcut, index);
            dialog.close();
        });

        buttonBox.append(cancelButton);
        buttonBox.append(saveButton);
        group.add(new Adw.PreferencesRow({child: buttonBox}));

        toolbar.set_content(content);
        dialog.set_child(toolbar);
        dialog.present(parent);
    }

    _saveShortcut(shortcut, index) {
        let shortcuts = [];
        try {
            const data = this._settings.get_string('shortcuts');
            if (data)
                shortcuts = JSON.parse(data);
        } catch (e) {
            console.error('Failed to load shortcuts:', e);
        }

        if (index !== null && index !== undefined)
            shortcuts[index] = shortcut;
        else
            shortcuts.push(shortcut);


        this._settings.set_string('shortcuts', JSON.stringify(shortcuts));
    }

    _deleteShortcut(index) {
        let shortcuts = [];
        try {
            const data = this._settings.get_string('shortcuts');
            if (data)
                shortcuts = JSON.parse(data);
        } catch (e) {
            console.error('Failed to load shortcuts:', e);
        }

        shortcuts.splice(index, 1);
        this._settings.set_string('shortcuts', JSON.stringify(shortcuts));
    }

    _exportShortcuts(window) {
        console.log('[API Shortcuts] Starting export');

        let shortcuts = [];
        try {
            const data = this._settings.get_string('shortcuts');
            if (data)
                shortcuts = JSON.parse(data);
        } catch (e) {
            console.error('[API Shortcuts] Failed to load shortcuts for export:', e);
            this._showErrorDialog(window, 'Export Failed', 'Could not load shortcuts');
            return;
        }

        if (shortcuts.length === 0) {
            this._showErrorDialog(window, 'No Shortcuts', 'There are no shortcuts to export');
            return;
        }

        // Create file chooser dialog
        const dialog = new Gtk.FileDialog({
            title: 'Export Shortcuts',
            modal: true,
        });

        // Set default filename
        const timestamp = new Date().toISOString().split('T')[0];
        dialog.set_initial_name(`api-shortcuts-${timestamp}.json`);

        // Show save dialog
        dialog.save(window, null, (source, result) => {
            try {
                const file = dialog.save_finish(result);
                if (file) {
                    const path = file.get_path();
                    console.log('[API Shortcuts] Exporting to:', path);

                    // Write shortcuts to file
                    const contents = JSON.stringify(shortcuts, null, 2);
                    const success = GLib.file_set_contents(path, contents);

                    if (success) {
                        console.log('[API Shortcuts] Export successful');
                        this._showInfoDialog(window, 'Export Successful',
                            `Shortcuts exported to:\n${path}`);
                    } else {
                        throw new Error('Failed to write file');
                    }
                }
            } catch (e) {
                console.error('[API Shortcuts] Export failed:', e);
                this._showErrorDialog(window, 'Export Failed', e.message);
            }
        });
    }



    _importShortcuts(window) {
        // Create file chooser dialog
        const fileFilter = new Gtk.FileFilter();
        fileFilter.set_name('JSON Files');
        fileFilter.add_mime_type('application/json');
        fileFilter.add_pattern('*.json');

        const filterList = Gio.ListStore.new(Gtk.FileFilter);
        filterList.append(fileFilter);

        const dialog = new Gtk.FileDialog({
            title: 'Import Shortcuts',
            modal: true,
            filters: filterList,
            default_filter: fileFilter,
        });

        // Show open dialog with proper async handling
        dialog.open(window, null, (fileDialog, result) => {
            try {
                const file = fileDialog.open_finish(result);
                console.log('[API Shortcuts] File selected:', file ? file.get_path() : 'none');

                if (file) {
                    const path = file.get_path();
                    console.log('[API Shortcuts] Importing from:', path);

                    // Read file contents
                    const [success, contents] = GLib.file_get_contents(path);

                    if (!success)
                        throw new Error('Failed to read file');


                    // Parse JSON
                    const decoder = new TextDecoder('utf-8');
                    const text = decoder.decode(contents);

                    const importedShortcuts = JSON.parse(text);
                    console.log('[API Shortcuts] Parsed shortcuts:', importedShortcuts.length);

                    // Validate shortcuts structure
                    if (!Array.isArray(importedShortcuts))
                        throw new Error('Invalid file format: expected array of shortcuts');


                    for (const shortcut of importedShortcuts) {
                        if (!shortcut.label || !shortcut.url || !shortcut.method)
                            throw new Error('Invalid shortcut format: missing required fields (label, url, or method)');
                    }

                    // Show confirmation dialog
                    this._showImportConfirmDialog(window, importedShortcuts);
                }
            } catch (e) {
                console.error('[API Shortcuts] Import failed:', e);
                console.error('[API Shortcuts] Error stack:', e.stack);
                this._showErrorDialog(window, 'Import Failed', e.message);
            }
        });
    }

    _showImportConfirmDialog(window, importedShortcuts) {
        const dialog = new Adw.AlertDialog({
            heading: 'Import Shortcuts',
            body: `Found ${importedShortcuts.length} shortcut(s).\n\nHow would you like to import them?`,
        });

        dialog.add_response('cancel', 'Cancel');
        dialog.add_response('replace', 'Replace All');
        dialog.add_response('append', 'Add to Existing');

        dialog.set_response_appearance('replace', Adw.ResponseAppearance.DESTRUCTIVE);
        dialog.set_response_appearance('append', Adw.ResponseAppearance.SUGGESTED);
        dialog.set_default_response('cancel');
        dialog.set_close_response('cancel');

        dialog.connect('response', (dlg, response) => {
            if (response === 'replace') {
                console.log('[API Shortcuts] Replacing all shortcuts');
                this._settings.set_string('shortcuts', JSON.stringify(importedShortcuts));
                this._showInfoDialog(window, 'Import Complete',
                    `Imported ${importedShortcuts.length} shortcut(s)`);
            } else if (response === 'append') {
                console.log('[API Shortcuts] Appending shortcuts');
                let existing = [];
                try {
                    const data = this._settings.get_string('shortcuts');
                    if (data)
                        existing = JSON.parse(data);
                } catch (e) {
                    console.error('[API Shortcuts] Failed to load existing shortcuts:', e);
                }

                const combined = existing.concat(importedShortcuts);
                this._settings.set_string('shortcuts', JSON.stringify(combined));
                this._showInfoDialog(window, 'Import Complete',
                    `Added ${importedShortcuts.length} shortcut(s). Total: ${combined.length}`);
            }
        });

        dialog.present(window);
    }

    _showErrorDialog(window, heading, body) {
        const dialog = new Adw.AlertDialog({
            heading,
            body,
        });
        dialog.add_response('ok', 'OK');
        dialog.set_default_response('ok');
        dialog.present(window);
    }

    _showInfoDialog(window, heading, body) {
        const dialog = new Adw.AlertDialog({
            heading,
            body,
        });
        dialog.add_response('ok', 'OK');
        dialog.set_default_response('ok');
        dialog.present(window);
    }
}
