import { Buffer } from "node:buffer";
import crypto from "node:crypto";

/**
 * The server half of RFC 6455, for tests.
 *
 * Both test files need to stand in for a Stream Deck, which means speaking the
 * protocol from the other side. It lives here rather than in each of them so
 * that the plugin's own client is being checked against one implementation
 * instead of two that could quietly disagree.
 *
 * Only what a loopback test needs: no extensions, no fragmentation on the way
 * out beyond what a test asks for, and no pretence at being a real server.
 */

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

/** Completes an upgrade request. */
export function handshake(request, socket) {
    const accept = crypto
        .createHash("sha1")
        .update(request.headers["sec-websocket-key"] + GUID)
        .digest("base64");
    socket.write(
        "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
            `Sec-WebSocket-Accept: ${accept}\r\n\r\n`,
    );
}

/** One frame off the front of `buffer`, or null while it is still incomplete. */
export function readFrame(buffer) {
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

    const mask = masked ? buffer.subarray(offset, offset + 4) : null;
    if (masked) offset += 4;
    if (buffer.length < offset + length) return null;

    const payload = Buffer.from(buffer.subarray(offset, offset + length));
    if (mask) for (let i = 0; i < payload.length; i += 1) payload[i] ^= mask[i % 4];

    return { length: offset + length, fin, opcode, masked, payload };
}

/** One unmasked server frame, as servers must not mask. */
export function writeFrame(payload, { opcode = 0x1, fin = true } = {}) {
    const body = Buffer.isBuffer(payload) ? payload : Buffer.from(payload, "utf8");

    let header;
    if (body.length < 126) {
        header = Buffer.alloc(2);
        header[1] = body.length;
    } else if (body.length < 65536) {
        header = Buffer.alloc(4);
        header[1] = 126;
        header.writeUInt16BE(body.length, 2);
    } else {
        header = Buffer.alloc(10);
        header[1] = 127;
        header.writeBigUInt64BE(BigInt(body.length), 2);
    }
    header[0] = (fin ? 0x80 : 0x00) | opcode;

    return Buffer.concat([header, body]);
}
