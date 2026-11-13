#!/usr/bin/env node
import fs from "node:fs";
import process from "node:process";

import { DeckSocket } from "./deck-socket.js";
import { NotRunningError, getState, post, watch } from "./client.js";
import {
    ROTATION,
    commandFor,
    fillTemplate,
    isLit,
    labelValues,
    rotationIcon,
    titleTemplate,
} from "./logic.js";

/**
 * An OpenDeck / Stream Deck plugin for OpenPromptr.
 *
 * Two connections in opposite directions: the deck app says which keys exist
 * and when one is pressed, OpenPromptr says what is true right now. A press
 * becomes a request; a change in the app becomes a repaint of every key that
 * shows it — so a key follows the menu bar and the ⌘. shortcut instead of
 * remembering what it last sent.
 *
 * The same file runs on OpenDeck (system `node`) and Stream Deck (its own).
 * There are no dependencies and no build step.
 */

const args = process.argv.slice(2);
const argument = (flag) => args[args.indexOf(flag) + 1];

const port = argument("-port");
const pluginUUID = argument("-pluginUUID");
const registerEvent = argument("-registerEvent");

const pluginVersion = (() => {
    try {
        return JSON.parse(fs.readFileSync(new URL("./manifest.json", import.meta.url), "utf8")).Version;
    } catch {
        return "unknown";
    }
})();

/** Every key of ours currently on a device, by context. */
const keys = new Map();

/** The last state OpenPromptr sent, or null while it is not reachable. */
let app = null;

let deck;

// MARK: - Deck app

function connectToDeck() {
    deck = new DeckSocket(`ws://127.0.0.1:${port}`);

    deck.addEventListener("open", () => {
        deck.send(JSON.stringify({ event: registerEvent, uuid: pluginUUID }));
        // The deck app runs a copy made by install.sh, which goes stale
        // silently; naming the version makes an old copy visible in the log.
        log(`plugin ${pluginVersion} started`);
    });

    deck.addEventListener("message", ({ data }) => {
        try {
            handle(JSON.parse(data));
        } catch {
            // A malformed message from the deck app is not ours to crash on.
        }
    });

    // The deck app kills the plugin when it unloads it, so a closed socket
    // means we are on our way out.
    deck.addEventListener("close", () => process.exit(0));
    deck.addEventListener("error", () => process.exit(1));
}

function toDeck(event, context, payload) {
    if (deck?.readyState !== DeckSocket.OPEN) return;
    deck.send(JSON.stringify(payload ? { event, context, payload } : { event, context }));
}

function log(message) {
    if (deck?.readyState === DeckSocket.OPEN) {
        deck.send(JSON.stringify({ event: "logMessage", payload: { message: `OpenPromptr: ${message}` } }));
    }
}

function handle({ event, context, action, payload }) {
    switch (event) {
        case "willAppear":
            keys.set(context, { action, settings: payload?.settings ?? {} });
            render(context);
            break;

        case "willDisappear":
            keys.delete(context);
            break;

        case "didReceiveSettings":
            if (keys.has(context)) keys.get(context).settings = payload?.settings ?? {};
            render(context);
            break;

        case "keyDown":
            // A press carries the key's stored settings; trusting them over a
            // copy from when the key appeared means a change always applies.
            if (payload?.settings && keys.has(context)) keys.get(context).settings = payload.settings;
            press(context).catch((error) => {
                // The person pressing is looking at the device, not a log.
                toDeck("showAlert", context);
                log(error instanceof NotRunningError ? error.message : `press failed: ${error.message}`);
            });
            break;

        case "sendToPlugin":
            // The inspector hands changed settings straight over, because not
            // every deck app forwards them on its own.
            if (payload?.settings && keys.has(context)) {
                keys.get(context).settings = payload.settings;
                render(context);
            }
            break;
    }
}

// MARK: - Presses

async function press(context) {
    const key = keys.get(context);
    if (!key) return;
    const command = commandFor(key.action, key.settings, app);
    if (!command) return;
    await post(command.route, command.body);
    // Do not wait out the poll interval to show the result; the app applies a
    // command a moment after it answers.
    setTimeout(async () => {
        try {
            app = await getState();
            renderAll();
        } catch {
            // The regular poll reports it.
        }
    }, 200);
}

// MARK: - Painting

const iconNames = ["rotate", "rotate-cw", "rotate-ccw"];

/** Icons a key swaps to by its settings, as data URLs both deck apps accept. */
const icons = Object.fromEntries(
    iconNames.map((name) => [
        name,
        "data:image/svg+xml;base64," +
            fs.readFileSync(new URL(`./icons/${name}.svg`, import.meta.url)).toString("base64"),
    ])
);

/** Sends an image only when it differs from the key's last one; state pushes are frequent. */
function setImage(context, name) {
    const key = keys.get(context);
    if (!key || key.image === name) return;
    key.image = name;
    toDeck("setImage", context, { image: icons[name] });
}

function render(context) {
    const key = keys.get(context);
    if (!key) return;
    const { action, settings } = key;

    // The picture depends only on the key's own settings, so it is right even
    // while the app is away.
    if (action === ROTATION) setImage(context, rotationIcon(settings));

    toDeck("setState", context, { state: isLit(action, settings, app) ? 1 : 0 });

    const template = titleTemplate(action, settings);
    if (template === null) return;

    // While the app is away the label stays, so the layout still reads as
    // something that will work once it is back.
    const title = app
        ? fillTemplate(template, labelValues(action, settings, app))
        : template === ""
          ? ""
          : "—";
    toDeck("setTitle", context, { title });
}

const renderAll = () => {
    for (const context of keys.keys()) render(context);
};

// MARK: - OpenPromptr

connectToDeck();

const stop = watch(
    (state) => {
        app = state;
        renderAll();
    },
    {
        onError: (error) => log(error.message),
        onDisconnect: () => {
            app = null;
            renderAll();
        },
    }
);
process.on("exit", stop);
