#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import http from "node:http";
import os from "node:os";
import path from "node:path";
import process from "node:process";

import {
    NotRunningError,
    getState,
    post,
    watch,
} from "../com.trsdn.openpromptr.sdPlugin/client.js";

/**
 * The client against a stand-in for OpenPromptr's local API: the bearer token,
 * the absence of an Origin header, and what each way of the app being away
 * looks like.
 */

const dir = fs.mkdtempSync(path.join(os.tmpdir(), "openpromptr-plugin-"));
const file = path.join(dir, "local-api.json");
const TOKEN = "a".repeat(64);
const seen = [];
let state = { running: false, busy: false, transform: { rotation: 0, mirrorH: false, mirrorV: false } };

const server = http.createServer((request, response) => {
    let body = "";
    request.on("data", (chunk) => (body += chunk));
    request.on("end", () => {
        seen.push({ method: request.method, url: request.url, headers: request.headers, body });
        if (request.headers.authorization !== `Bearer ${TOKEN}`) {
            response.writeHead(401).end("Unauthorized");
        } else if (request.url === "/v1/state") {
            response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(state));
        } else {
            response.writeHead(202).end();
        }
    });
});
await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
const { port } = server.address();
const writeCredentials = (token = TOKEN, at = port) => fs.writeFileSync(file, JSON.stringify({ port: at, token }));

const checks = [];
const check = (name, body) => checks.push([name, body]);

check("without a connection file the app counts as not running", async () => {
    await assert.rejects(getState({ file }), NotRunningError);
});

check("a request carries the bearer token and no Origin", async () => {
    writeCredentials();
    seen.length = 0;
    assert.equal((await getState({ file })).running, false);
    assert.equal(seen[0].headers.authorization, `Bearer ${TOKEN}`);
    assert.equal(seen[0].headers.origin, undefined);
});

check("a command is a POST with a JSON body", async () => {
    seen.length = 0;
    await post("/v1/transform", { rotation: 90 }, { file });
    assert.equal(seen[0].method, "POST");
    assert.equal(seen[0].url, "/v1/transform");
    assert.deepEqual(JSON.parse(seen[0].body), { rotation: 90 });
    assert.equal(seen[0].headers["content-type"], "application/json");
});

check("a token from an earlier launch is refused as not running", async () => {
    writeCredentials("b".repeat(64));
    await assert.rejects(getState({ file }), NotRunningError);
});

check("a file left behind by a crash is not running either", async () => {
    writeCredentials(TOKEN, 1);
    await assert.rejects(getState({ file }), NotRunningError);
});

check("a garbled file is not running, not a crash", async () => {
    fs.writeFileSync(file, "{nope");
    await assert.rejects(getState({ file }), NotRunningError);
});

check("watch reports changes once, and the app going away once", async () => {
    writeCredentials();
    const events = [];
    const stop = watch((s) => events.push(["state", s.running]), {
        onDisconnect: () => events.push(["gone"]),
        intervalMs: 20,
        file,
    });
    const until = async (predicate) => {
        for (let i = 0; i < 100 && !predicate(); i++) await new Promise((r) => setTimeout(r, 20));
    };
    await until(() => events.length >= 1);
    await new Promise((r) => setTimeout(r, 100));
    assert.deepEqual(events, [["state", false]], "no repeat while nothing changed");
    state = { ...state, running: true };
    await until(() => events.length >= 2);
    fs.rmSync(file);
    await until(() => events.length >= 3);
    await new Promise((r) => setTimeout(r, 100));
    stop();
    assert.deepEqual(events, [["state", false], ["state", true], ["gone"]]);
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
server.close();
fs.rmSync(dir, { recursive: true, force: true });
console.log(
    failures.length
        ? `\n${failures.length} of ${checks.length} checks failed`
        : `\n${checks.length}/${checks.length} checks passed`,
);
process.exit(failures.length ? 1 : 0);
