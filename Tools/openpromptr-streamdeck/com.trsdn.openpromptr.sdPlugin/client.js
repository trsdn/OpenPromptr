import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";

/**
 * The plugin's side of OpenPromptr's local HTTP API.
 *
 * OpenPromptr publishes `{port, token}` to a 0600 file in its Application
 * Support folder on every launch, with a fresh token each time, and removes it
 * on a clean quit. So nothing here is cached for long: a missing file, a
 * refused connection and a rejected token all mean the same thing to a key —
 * the app is not there, or is not the one we last talked to — and the next
 * poll reads the file again.
 *
 * The requests carry no `Origin` header, which is what the server insists on.
 * Node's fetch adds none.
 */

export class NotRunningError extends Error {
    constructor(message = "OpenPromptr is not running, or its local API is switched off") {
        super(message);
        this.name = "NotRunningError";
    }
}

export function credentialsPath() {
    return path.join(
        os.homedir(),
        "Library",
        "Application Support",
        "com.github.trsdn.OpenPromptr",
        "local-api.json",
    );
}

async function readCredentials(file) {
    let raw;
    try {
        raw = await fs.readFile(file, "utf8");
    } catch {
        throw new NotRunningError();
    }
    try {
        const { port, token } = JSON.parse(raw);
        if (Number.isInteger(port) && typeof token === "string" && token) return { port, token };
    } catch {
        // falls through
    }
    throw new NotRunningError("OpenPromptr's connection file is unreadable");
}

/** One request. Rejects with NotRunningError when the app cannot be reached or does not accept us. */
export async function request(method, route, body, { file = credentialsPath() } = {}) {
    const { port, token } = await readCredentials(file);
    let response;
    try {
        response = await fetch(`http://127.0.0.1:${port}${route}`, {
            method,
            headers: {
                authorization: `Bearer ${token}`,
                ...(body === undefined ? {} : { "content-type": "application/json" }),
            },
            body: body === undefined ? undefined : JSON.stringify(body),
            signal: AbortSignal.timeout(3000),
        });
    } catch {
        // A file left behind by a crash names a port nobody listens on.
        throw new NotRunningError();
    }
    if (response.status === 401) throw new NotRunningError("OpenPromptr rejected the token");
    if (!response.ok) throw new Error(`OpenPromptr answered ${response.status} to ${method} ${route}`);
    const text = await response.text();
    return text ? JSON.parse(text) : null;
}

export const getState = (options) => request("GET", "/v1/state", undefined, options);
export const post = (route, body, options) => request("POST", route, body ?? {}, options);

/**
 * Polls the state and calls `onState` whenever it changes, and `onDisconnect`
 * once when the app goes away. A plugin cannot subscribe — the API has no
 * stream — so a key that follows a hotkey press or a change in the window has
 * to ask, and a second is quick enough to feel live.
 */
export function watch(onState, { onError, onDisconnect, intervalMs = 1000, file } = {}) {
    let last;
    let connected = null;
    let stopped = false;
    let timer;

    const tick = async () => {
        try {
            const state = await getState({ file });
            const serialized = JSON.stringify(state);
            if (serialized !== last || connected !== true) {
                last = serialized;
                connected = true;
                onState(state);
            }
        } catch (error) {
            if (connected !== false) {
                connected = false;
                last = undefined;
                onDisconnect?.();
            }
            if (!(error instanceof NotRunningError)) onError?.(error);
        }
        if (!stopped) timer = setTimeout(tick, intervalMs);
    };
    tick();

    return () => {
        stopped = true;
        clearTimeout(timer);
    };
}
