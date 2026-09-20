#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { Buffer } from "node:buffer";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

import { handshake, readFrame, writeFrame } from "./websocket.js";

/**
 * Runs plugin.js as the deck app would, against a stand-in deck and a
 * stand-in OpenPromptr, and watches what the keys are told.
 *
 * The pieces are tested on their own elsewhere; this is the one place that
 * shows they are joined up: a state change repaints a key, a press reaches the
 * API as the right request, and the app going away is shown.
 */

const here = path.dirname(fileURLToPath(import.meta.url));
const pluginDir = path.join(here, "..", "com.trsdn.openpromptr.sdPlugin");

const home = fs.mkdtempSync(path.join(os.tmpdir(), "openpromptr-smoke-"));
const credentials = path.join(
    home,
    "Library",
    "Application Support",
    "com.github.trsdn.OpenPromptr",
    "local-api.json",
);
fs.mkdirSync(path.dirname(credentials), { recursive: true });

const TOKEN = "c".repeat(64);
let state = {
    running: false,
    busy: false,
    status: "Ready",
    error: false,
    permissionGranted: true,
    source: "Virtual display",
    display: { id: 3, name: "AAA" },
    transform: { rotation: 0, mirrorH: false, mirrorV: false },
};
const requests = [];

const api = http.createServer((request, response) => {
    requests.push(`${request.method} ${request.url}`);
    if (request.url === "/v1/state") {
        response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(state));
    } else {
        response.writeHead(202).end();
    }
});
await new Promise((resolve) => api.listen(0, "127.0.0.1", resolve));
fs.writeFileSync(credentials, JSON.stringify({ port: api.address().port, token: TOKEN }));

const sent = []; // what the plugin told the deck
let deckSocket;
const deck = http.createServer();
deck.on("upgrade", (request, socket) => {
    handshake(request, socket);
    deckSocket = socket;
    let buffer = Buffer.alloc(0);
    socket.on("data", (chunk) => {
        buffer = Buffer.concat([buffer, chunk]);
        let frame;
        while ((frame = readFrame(buffer))) {
            buffer = buffer.subarray(frame.length);
            sent.push(JSON.parse(frame.payload.toString()));
        }
    });
    socket.on("error", () => {});
});
await new Promise((resolve) => deck.listen(0, "127.0.0.1", resolve));

const plugin = spawn(
    process.execPath,
    [
        path.join(pluginDir, "plugin.js"),
        "-port", String(deck.address().port),
        "-pluginUUID", "test-uuid",
        "-registerEvent", "registerPlugin",
    ],
    { env: { ...process.env, HOME: home }, stdio: ["ignore", "ignore", "inherit"] },
);

const tell = (message) => deckSocket.write(writeFrame(JSON.stringify(message)));
const until = async (predicate, what) => {
    for (let i = 0; i < 150; i++) {
        if (predicate()) return;
        await new Promise((r) => setTimeout(r, 20));
    }
    throw new Error(`timed out waiting for ${what}; got ${JSON.stringify(sent.slice(-6))}`);
};
const last = (event, context) => [...sent].reverse().find((m) => m.event === event && m.context === context);

const checks = [];
const check = (name, body) => checks.push([name, body]);

check("the plugin registers with the deck app", async () => {
    await until(() => sent.some((m) => m.event === "registerPlugin"), "registration");
    assert.equal(sent.find((m) => m.event === "registerPlugin").uuid, "test-uuid");
});

check("a key that appears is painted from the app's state, with a custom label", async () => {
    const output = "com.trsdn.openpromptr.output";
    const rotation = "com.trsdn.openpromptr.rotation";
    tell({ event: "willAppear", context: "out", action: output, payload: { settings: { title: "Prompter" } } });
    tell({ event: "willAppear", context: "rot", action: rotation, payload: { settings: {} } });
    await until(() => last("setTitle", "out") && last("setTitle", "rot"), "first paint");
    assert.equal(last("setTitle", "out").payload.title, "Prompter");
    assert.equal(last("setState", "out").payload.state, 0);
    assert.equal(last("setTitle", "rot").payload.title, "0°");
});

check("a change in the app repaints the key", async () => {
    state = { ...state, running: true };
    await until(() => last("setState", "out").payload.state === 1, "a lit key");
});

check("a press becomes the matching request", async () => {
    requests.length = 0;
    const output = "com.trsdn.openpromptr.output";
    tell({ event: "keyDown", context: "out", action: output, payload: { settings: { title: "Prompter" } } });
    await until(() => requests.includes("POST /v1/output/stop"), "the stop request");
    const rotation = "com.trsdn.openpromptr.rotation";
    tell({ event: "keyDown", context: "rot", action: rotation, payload: { settings: {} } });
    await until(() => requests.filter((r) => r === "POST /v1/transform").length === 1, "the transform request");
});

check("settings passed straight through repaint without waiting for the deck app", async () => {
    tell({ event: "sendToPlugin", context: "out", payload: { settings: { showTitle: false } } });
    await until(() => last("setTitle", "out").payload.title === "", "a cleared title");
});

check("the app going away shows on the keys", async () => {
    fs.rmSync(credentials);
    await until(() => last("setTitle", "rot").payload.title === "—", "dashes");
    assert.equal(last("setState", "rot").payload.state, 0);
});

const failures = [];
for (const [name, body] of checks) {
    try {
        await body();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures.push(name);
        console.log(`  FAIL ${name}\n       ${error.message}`);
    }
}
plugin.kill();
api.close();
deck.close();
deckSocket?.destroy();
fs.rmSync(home, { recursive: true, force: true });
console.log(
    failures.length
        ? `\n${failures.length} of ${checks.length} checks failed`
        : `\n${checks.length}/${checks.length} checks passed`,
);
process.exit(failures.length ? 1 : 0);
