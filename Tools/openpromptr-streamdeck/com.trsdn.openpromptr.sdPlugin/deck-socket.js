import { Buffer } from "node:buffer";
import { createHash, randomBytes } from "node:crypto";
import net from "node:net";

/**
 * Just enough of RFC 6455 to talk to a Stream Deck.
 *
 * Node grew a global `WebSocket`, but only unflagged from v22.4. OpenDeck runs
 * plugins with whatever `node` is on PATH, while Stream Deck runs them with a
 * Node it bundles itself — and we do not get to pass that one a flag. Relying
 * on the global would mean the plugin works or does not depending on a runtime
 * we neither choose nor can inspect until it fails on someone else's machine.
 *
 * So we bring our own. It is small because the connection is: loopback, no TLS,
 * no proxy, no extensions, no subprotocols, and text frames only. The awkward
 * parts of the protocol — permessage-deflate, redirects, the whole origin
 * dance — are all on the far side of things we never do.
 *
 * The API is the sliver of the WHATWG one the plugin actually uses, so this is
 * a drop-in for the global and the plugin does not know which it has.
 */
export class DeckSocket {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;

    readyState = DeckSocket.CONNECTING;

    #socket;
    #listeners = new Map();

    /** Response bytes before the handshake completes, frame bytes after. */
    #buffered = Buffer.alloc(0);
    #handshakeDone = false;

    /** The accept value the server has to answer our key with. */
    #expectedAccept;

    /** Set while a fragmented message is being reassembled. */
    #fragments = null;
    #fragmentOpcode = 0;

    constructor(url) {
        const { hostname, port, pathname, search } = new URL(url);
        const key = randomBytes(16).toString("base64");
        this.#expectedAccept = accept(key);

        this.#socket = net.connect({ host: hostname, port: Number(port) }, () => {
            this.#socket.write(
                `GET ${pathname}${search} HTTP/1.1\r\n` +
                    `Host: ${hostname}:${port}\r\n` +
                    "Upgrade: websocket\r\n" +
                    "Connection: Upgrade\r\n" +
                    `Sec-WebSocket-Key: ${key}\r\n` +
                    "Sec-WebSocket-Version: 13\r\n" +
                    "\r\n",
            );
        });

        this.#socket.on("data", (chunk) => this.#receive(chunk));
        this.#socket.on("error", (error) => this.#fail(error));

        // A close with no close frame is still a close. Whoever is listening
        // cares that the connection ended, not how politely.
        this.#socket.on("close", () => this.#closed());
    }

    addEventListener(type, listener) {
        if (!this.#listeners.has(type)) this.#listeners.set(type, []);
        this.#listeners.get(type).push(listener);
    }

    send(text) {
        if (this.readyState !== DeckSocket.OPEN) return;
        this.#socket.write(frame(Buffer.from(text, "utf8"), 0x1));
    }

    close() {
        if (this.readyState === DeckSocket.CLOSING || this.readyState === DeckSocket.CLOSED) return;
        if (this.readyState === DeckSocket.OPEN) {
            const payload = Buffer.alloc(2);
            payload.writeUInt16BE(1000);
            this.#socket.write(frame(payload, 0x8));
        }
        this.readyState = DeckSocket.CLOSING;
        this.#socket.end();
    }

    #emit(type, event = {}) {
        for (const listener of this.#listeners.get(type) ?? []) listener(event);
    }

    #fail(error) {
        this.#emit("error", { error, message: error?.message });
        this.#socket.destroy();
    }

    #closed() {
        if (this.readyState === DeckSocket.CLOSED) return;
        this.readyState = DeckSocket.CLOSED;
        this.#emit("close", {});
    }

    #receive(chunk) {
        this.#buffered = Buffer.concat([this.#buffered, chunk]);
        if (!this.#handshakeDone && !this.#completeHandshake()) return;
        this.#readFrames();
    }

    /** True once the response has been seen and accepted. */
    #completeHandshake() {
        const end = this.#buffered.indexOf("\r\n\r\n");
        if (end === -1) return false;

        const head = this.#buffered.subarray(0, end).toString("latin1");
        this.#buffered = this.#buffered.subarray(end + 4);

        if (!/^HTTP\/1\.1 101/.test(head)) {
            this.#fail(new Error(`The server refused to upgrade: ${head.split("\r\n")[0]}`));
            return false;
        }

        const header = /\r\nsec-websocket-accept:\s*(\S+)/i.exec(head);
        if (header?.[1] !== this.#expectedAccept) {
            this.#fail(new Error("The server's handshake did not match our key."));
            return false;
        }

        this.#handshakeDone = true;
        this.readyState = DeckSocket.OPEN;
        this.#emit("open", {});
        return true;
    }

    #readFrames() {
        for (;;) {
            const parsed = parse(this.#buffered);
            if (!parsed) return;
            this.#buffered = parsed.rest;
            this.#dispatch(parsed);
        }
    }

    #dispatch({ fin, opcode, payload }) {
        switch (opcode) {
            case 0x0: // Continuation.
                if (!this.#fragments) return;
                this.#fragments.push(payload);
                if (fin) this.#complete();
                return;

            case 0x1: // Text.
            case 0x2: // Binary.
                if (fin) {
                    if (opcode === 0x1) this.#emit("message", { data: payload.toString("utf8") });
                    return;
                }
                this.#fragments = [payload];
                this.#fragmentOpcode = opcode;
                return;

            case 0x8: // Close.
                this.readyState = DeckSocket.CLOSING;
                this.#socket.end();
                return;

            case 0x9: // Ping. Answer with the same payload, as the RFC asks.
                this.#socket.write(frame(payload, 0xa));
                return;

            default: // Pong, and anything we have no business acting on.
        }
    }

    #complete() {
        const payload = Buffer.concat(this.#fragments);
        this.#fragments = null;
        if (this.#fragmentOpcode === 0x1) this.#emit("message", { data: payload.toString("utf8") });
    }
}

/** The `Sec-WebSocket-Accept` a server must answer `key` with. */
function accept(key) {
    return createHash("sha1")
        .update(key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")
        .digest("base64");
}

/** One masked client frame. Clients must mask; servers must not. */
function frame(payload, opcode) {
    const mask = randomBytes(4);
    const length = payload.length;

    let header;
    if (length < 126) {
        header = Buffer.alloc(2);
        header[1] = 0x80 | length;
    } else if (length < 65536) {
        header = Buffer.alloc(4);
        header[1] = 0x80 | 126;
        header.writeUInt16BE(length, 2);
    } else {
        header = Buffer.alloc(10);
        header[1] = 0x80 | 127;
        header.writeBigUInt64BE(BigInt(length), 2);
    }
    header[0] = 0x80 | opcode;

    const masked = Buffer.allocUnsafe(length);
    for (let i = 0; i < length; i++) masked[i] = payload[i] ^ mask[i % 4];

    return Buffer.concat([header, mask, masked]);
}

/** One frame off the front of `buffer`, or null while it is still incomplete. */
function parse(buffer) {
    if (buffer.length < 2) return null;

    const fin = (buffer[0] & 0x80) !== 0;
    const opcode = buffer[0] & 0x0f;
    const masked = (buffer[1] & 0x80) !== 0;

    let length = buffer[1] & 0x7f;
    let offset = 2;

    if (length === 126) {
        if (buffer.length < offset + 2) return null;
        length = buffer.readUInt16BE(offset);
        offset += 2;
    } else if (length === 127) {
        if (buffer.length < offset + 8) return null;
        length = Number(buffer.readBigUInt64BE(offset));
        offset += 8;
    }

    // A server should never mask, but reading it costs four bytes of care and
    // saves us from silently handing the plugin scrambled JSON.
    let mask;
    if (masked) {
        if (buffer.length < offset + 4) return null;
        mask = buffer.subarray(offset, offset + 4);
        offset += 4;
    }

    if (buffer.length < offset + length) return null;

    const payload = Buffer.from(buffer.subarray(offset, offset + length));
    if (mask) for (let i = 0; i < length; i++) payload[i] ^= mask[i % 4];

    return { fin, opcode, payload, rest: buffer.subarray(offset + length) };
}
