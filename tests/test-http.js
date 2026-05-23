/**
 * test-http.js — GJS ES-module HTTP connectivity test
 *
 * Exercises the same Soup.Session code-path used by the extension's
 * _executeRequest() method.  Run it inside the gnome-shell-pod container
 * after starting tests/mock-server.py.
 *
 * Usage (inside container):
 *   gjs -m test-http.js <url> <method> [body]
 *
 * Exit codes:
 *   0  – request completed with a 2xx status
 *   1  – any error (network failure, non-2xx status, bad arguments)
 */

import Soup from 'gi://Soup';
import GLib from 'gi://GLib';
import System from 'system';

// ---------------------------------------------------------------------------
// Argument handling
// ---------------------------------------------------------------------------

const [url, method = 'GET', body = ''] = ARGV;

if (!url) {
    printerr('Usage: gjs -m test-http.js <url> <method> [body]');
    System.exit(1);
}

const METHODS_WITH_BODY = ['POST', 'PUT', 'PATCH'];

// ---------------------------------------------------------------------------
// Main async block wrapped in a GLib.MainLoop
// ---------------------------------------------------------------------------

const loop = GLib.MainLoop.new(null, false);
let exitCode = 1;

(async () => {
    try {
        const session = new Soup.Session();
        const message = Soup.Message.new(method, url);

        // Attach a body for methods that carry one (mirrors extension logic)
        if (METHODS_WITH_BODY.includes(method) && body) {
            const encoded = new GLib.Bytes(new TextEncoder().encode(body));
            message.set_request_body_from_bytes('application/json', encoded);
        }

        const responseBytes = await session.send_and_read_async(
            message,
            GLib.PRIORITY_DEFAULT,
            null
        );

        const responseText = new TextDecoder('utf-8').decode(
            responseBytes.get_data()
        );

        const status = message.status_code;

        if (status >= 200 && status < 300) {
            print(`PASS: ${method} ${url} → HTTP ${status}`);
            print(`Response: ${responseText}`);
            exitCode = 0;
        } else {
            printerr(
                `FAIL: ${method} ${url} → HTTP ${status}: ${message.reason_phrase}`
            );
            printerr(`Body: ${responseText}`);
        }
    } catch (e) {
        printerr(`FAIL: ${e.message}`);
        if (e.stack)
            printerr(e.stack);
    } finally {
        loop.quit();
    }
})();

loop.run();
System.exit(exitCode);
