/**
 * The half of a property inspector that is the same for every action:
 * the handshake, the settings round-trip, and the label controls.
 *
 * A page includes this, then calls `OpenPromptrPI.ready(...)` and gets handed
 * the key's settings.
 */

const OpenPromptrPI = (() => {
    let socket;
    let context;
    let settings = {};
    const listeners = [];
    const onReady = (state) => listeners.forEach((listener) => listener(state));

    // Called by OpenDeck (and by Elgato's software) once the page is loaded.
    window.connectElgatoStreamDeckSocket = (port, uuid, registerEvent, _info, actionInfo) => {
        context = uuid;
        settings = JSON.parse(actionInfo).payload.settings ?? {};
        socket = new WebSocket(`ws://127.0.0.1:${port}`);

        socket.addEventListener("open", () => {
            socket.send(JSON.stringify({ event: registerEvent, uuid }));
            onReady({ settings });
        });

        socket.addEventListener("message", ({ data }) => {
            const message = JSON.parse(data);
            if (message.event === "didReceiveSettings") {
                settings = message.payload.settings ?? {};
                onReady({ settings });
            }
        });
    };

    function save(patch) {
        settings = { ...settings, ...patch };
        socket.send(JSON.stringify({ event: "setSettings", context, payload: settings }));
        // OpenDeck stores the settings but does not pass them on to the plugin
        // until the key next appears, so a changed label would wait for a
        // profile switch. Telling the plugin directly repaints the key now.
        socket.send(JSON.stringify({ event: "sendToPlugin", context, payload: { settings } }));
    }

    /**
     * The "what does the key say" controls every action shares: a switch, and
     * a template whose `{placeholders}` the plugin fills in. An empty template
     * means the action's own default, so a key never has to be configured to
     * be useful.
     */
    function labelControls({ defaultText, placeholders }) {
        const section = document.createElement("div");
        section.innerHTML = `
            <label class="check"><input id="show-label" type="checkbox"> Show label</label>
            <div id="label-fields">
                <label for="label">Label</label>
                <input id="label" type="text" spellcheck="false">
                <p class="note">Placeholders: ${placeholders.map((p) => `<code>{${p}}</code>`).join(" ")}.
                    <code>\\n</code> starts a new line. Leave empty for the default.</p>
            </div>`;
        document.body.insertBefore(section, document.querySelector("script"));

        const show = section.querySelector("#show-label");
        const label = section.querySelector("#label");
        const fields = section.querySelector("#label-fields");
        label.placeholder = defaultText || "(the title set in the deck app)";

        const write = () => {
            fields.hidden = !show.checked;
            save({ showTitle: show.checked, title: label.value });
        };
        listeners.push(({ settings }) => {
            show.checked = settings.showTitle !== false;
            label.value = settings.title ?? "";
            fields.hidden = !show.checked;
            show.onchange = write;
            label.onchange = write;
        });
    }

    return {
        ready(callback) {
            listeners.push(callback);
        },
        save,
        labelControls,
    };
})();
