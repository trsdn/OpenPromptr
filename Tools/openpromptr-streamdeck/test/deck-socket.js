#!/usr/bin/env node
import assert from "node:assert/strict";
import { Buffer } from "node:buffer";
import http from "node:http";
import process from "node:process";

import { DeckSocket } from "../com.trsdn.openpromptr.sdPlugin/deck-socket.js";
import { handshake, readFrame, writeFrame } from "./websocket.js";

/**
 * Checks the plugin's own WebSocket client against a stand-in server.
 *
 * The plugin brings its own client because the runtime Stream Deck hands it
 * cannot be relied on to have a global `WebSocket`. That trade only pays off if
 * the thing we wrote is actually correct, and the parts most likely to be
 * wrong are the ones a normal session never reaches: a message split across
 * frames, a length that needs more than seven bits, a handshake that should
 * have been refused. None of those show up in the plugin's own smoke test,
 * because a Stream Deck on loopback never does them.
 *
 * Run with `npm test`.
 */

const checks = [];
const check = (name, body) => checks.push([name, body]);

/**
 * Runs `body` against a server that hands it every frame the client sent.
 *
 * `serve` gets the raw socket, so a check can write whatever malformed or
 * awkward thing it wants to prove the client survives.
 */
async function withServer(body, { serve } = {}) {
    const received = [];
    const server = http.createServer();
    let clientSocket = null;

    server.on("upgrade", (request, socket) => {
        clientSocket = socket;
        if (serve) {
            serve(request, socket);
            return;
        }
        handshake(request, socket);

        let buffer = Buffer.alloc(0);
        socket.on("data", (chunk) => {
            buffer = Buffer.concat([buffer, chunk]);
            let frame;
            while ((frame = readFrame(buffer))) {
                buffer = buffer.subarray(frame.length);
                received.push(frame);
            }
        });
        socket.on("error", () => {});
    });

    await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
    const socket = new DeckSocket(`ws://127.0.0.1:${server.address().port}/`);

    const messages = [];
    const errors = [];
    let closed = false;
    socket.addEventListener("message", ({ data }) => messages.push(data));
    socket.addEventListener("error", ({ error }) => errors.push(error));
    socket.addEventListener("close", () => (closed = true));

    const opened = new Promise((resolve) => socket.addEventListener("open", resolve));

    try {
        await body({
            socket,
            opened,
            messages,
            errors,
            received,
            closed: () => closed,
            write: (buffer) => clientSocket.write(buffer),
            hangUp: () => clientSocket.destroy(),
        });
    } finally {
        socket.close();
        // Destroying the connection first: close() waits for open ones.
        clientSocket?.destroy();
        await new Promise((resolve) => server.close(resolve));
    }
}

/** Long enough for a round trip over loopback. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 100));

// MARK: - Checks

check("it opens once the server has answered the handshake", async () => {
    await withServer(async ({ opened, socket }) => {
        await opened;
        assert.equal(socket.readyState, DeckSocket.OPEN);
    });
});

check("every frame it sends is masked, as the protocol demands of a client", async () => {
    await withServer(async ({ opened, socket, received }) => {
        await opened;
        socket.send("hello");
        await settle();
        assert.equal(received.length, 1);
        assert.equal(received[0].masked, true, "an unmasked client frame is a protocol error");
        assert.equal(received[0].payload.toString("utf8"), "hello");
    });
});

check("a payload too long for seven bits still arrives whole", async () => {
    await withServer(async ({ opened, socket, received }) => {
        await opened;
        const text = "x".repeat(1000);
        socket.send(text);
        await settle();
        assert.equal(received[0].payload.toString("utf8"), text);
    });
});

check("a payload too long for sixteen bits still arrives whole", async () => {
    await withServer(async ({ opened, socket, received }) => {
        await opened;
        // A setImage with a large base64 icon really does reach this size.
        const text = "y".repeat(70000);
        socket.send(text);
        await settle();
        assert.equal(received[0].payload.length, 70000);
        assert.equal(received[0].payload.toString("utf8"), text);
    });
});

check("a message split across frames is delivered as one", async () => {
    await withServer(async ({ opened, messages, write }) => {
        await opened;
        write(writeFrame("{\"event\":", { fin: false }));
        write(writeFrame("\"willAppear\"", { opcode: 0x0, fin: false }));
        write(writeFrame("}", { opcode: 0x0, fin: true }));
        await settle();
        assert.deepEqual(messages, ['{"event":"willAppear"}']);
    });
});

check("a message split across packets is delivered as one", async () => {
    await withServer(async ({ opened, messages, write }) => {
        await opened;
        const frame = writeFrame("{\"event\":\"keyDown\"}");
        // TCP is a stream: a frame can arrive in as many pieces as it likes.
        write(frame.subarray(0, 3));
        await settle();
        assert.deepEqual(messages, [], "half a frame is not a message");
        write(frame.subarray(3));
        await settle();
        assert.deepEqual(messages, ['{"event":"keyDown"}']);
    });
});

check("two frames in one packet are two messages", async () => {
    await withServer(async ({ opened, messages, write }) => {
        await opened;
        write(Buffer.concat([writeFrame("one"), writeFrame("two")]));
        await settle();
        assert.deepEqual(messages, ["one", "two"]);
    });
});

check("it answers a ping with the same payload, so the deck keeps it", async () => {
    await withServer(async ({ opened, received, write }) => {
        await opened;
        write(writeFrame(Buffer.from("keepalive"), { opcode: 0x9 }));
        await settle();
        const pong = received.find((frame) => frame.opcode === 0xa);
        assert.ok(pong, "a ping went unanswered");
        assert.equal(pong.payload.toString("utf8"), "keepalive");
    });
});

check("a handshake that does not match our key is refused", async () => {
    await withServer(
        async ({ errors, socket }) => {
            await settle();
            assert.equal(errors.length, 1);
            assert.match(errors[0].message, /handshake/);
            assert.notEqual(socket.readyState, DeckSocket.OPEN, "it must not consider itself open");
        },
        {
            serve: (request, socket) =>
                socket.write(
                    "HTTP/1.1 101 Switching Protocols\r\n" +
                        "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
                        "Sec-WebSocket-Accept: not-the-right-value\r\n\r\n",
                ),
        },
    );
});

check("a server that refuses to upgrade is an error rather than a hang", async () => {
    await withServer(
        async ({ errors }) => {
            await settle();
            assert.equal(errors.length, 1);
            assert.match(errors[0].message, /refused to upgrade/);
        },
        { serve: (request, socket) => socket.write("HTTP/1.1 404 Not Found\r\n\r\n") },
    );
});

check("the deck going away closes the socket rather than leaving it open", async () => {
    await withServer(async ({ opened, hangUp, closed, socket }) => {
        await opened;
        hangUp();
        await settle();
        assert.equal(closed(), true, "nothing told the plugin the deck was gone");
        assert.equal(socket.readyState, DeckSocket.CLOSED);
    });
});

// MARK: - Running

const failures = [];
for (const [name, body] of checks) {
    try {
        await body();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures.push(name);
        console.log(`  FAIL ${name}`);
        console.log(`       ${error.message}`);
    }
}

console.log(
    failures.length
        ? `\n${failures.length} of ${checks.length} checks failed`
        : `\n${checks.length}/${checks.length} checks passed`,
);
process.exit(failures.length ? 1 : 0);
