/**
 * What each key does and says, kept apart from the sockets so that it can be
 * tested with plain objects.
 *
 * `state` is the body of `GET /v1/state`, or null while OpenPromptr is away.
 */

export const OUTPUT = "com.trsdn.openpromptr.output";
export const ROTATION = "com.trsdn.openpromptr.rotation";
export const FLIP = "com.trsdn.openpromptr.flip";

const isActive = (state) => Boolean(state?.running || state?.busy);
const axisOf = (settings) => (settings.axis === "v" ? "mirrorV" : "mirrorH");
const normalize = (degrees) => ((degrees % 360) + 360) % 360;

/** The rotation a Rotate key leads to, given the current one. */
export function targetRotation(settings, current = 0) {
    switch (settings.mode) {
        case "set":
            return normalize(Number(settings.degrees ?? 0));
        case "ccw":
            return normalize(current - 90);
        default:
            return normalize(current + 90);
    }
}

/** The request a press turns into, as `{route, body?}`. */
export function commandFor(action, settings, state) {
    switch (action) {
        case OUTPUT:
            // Stopping while busy cancels a start that is still under way.
            return { route: isActive(state) ? "/v1/output/stop" : "/v1/output/start" };
        case ROTATION:
            return {
                route: "/v1/transform",
                body: { rotation: targetRotation(settings, state?.transform?.rotation ?? 0) },
            };
        case FLIP: {
            const axis = axisOf(settings);
            return { route: "/v1/transform", body: { [axis]: !state?.transform?.[axis] } };
        }
        default:
            return null;
    }
}

/** Which of the key's two states to show. */
export function isLit(action, settings, state) {
    if (!state) return false;
    switch (action) {
        case OUTPUT:
            return state.running;
        case ROTATION:
            return settings.mode === "set" && state.transform.rotation === targetRotation(settings);
        case FLIP:
            return state.transform[axisOf(settings)];
        default:
            return false;
    }
}

/** The values a label's `{placeholders}` stand for. */
export function labelValues(action, settings, state) {
    const rotation = state?.transform?.rotation;
    const flipped = state?.transform?.[axisOf(settings)];
    return {
        state: !state ? "?" : state.running ? "Running" : state.busy ? "Starting" : "Stopped",
        status: state?.status ?? "?",
        display: state?.display?.name ?? "—",
        source: state?.source ?? "?",
        rotation: rotation === undefined ? "?" : `${rotation}°`,
        target: `${targetRotation(settings, rotation ?? 0)}°`,
        axis: settings.axis === "v" ? "V" : "H",
        flipped: flipped === undefined ? "?" : flipped ? "On" : "Off",
    };
}

/**
 * What a key's label says before its placeholders are filled in, or null to
 * leave the title the deck app shows alone.
 *
 * A switched-off label is an empty string rather than null: the plugin set a
 * title before, and only an explicit empty one clears it.
 */
export function titleTemplate(action, settings) {
    if (settings.showTitle === false) return "";
    if (typeof settings.title === "string" && settings.title.trim()) return settings.title;
    switch (action) {
        case OUTPUT:
            return "{state}";
        case ROTATION:
            return settings.mode === "set" ? "{target}" : "{rotation}";
        case FLIP:
            return "Flip {axis}\\n{flipped}";
        default:
            return null;
    }
}

/** `\n` typed in a one-line field becomes a line break; unknown placeholders stay as typed. */
export function fillTemplate(template, values) {
    return template
        .replace(/\\n/g, "\n")
        .replace(/\{(\w+)\}/g, (match, name) => (name in values ? String(values[name]) : match));
}

/** The picture a Rotate key swaps to by its settings. */
export function rotationIcon(settings) {
    return { cw: "rotate-cw", ccw: "rotate-ccw" }[settings.mode ?? "cw"] ?? "rotate";
}
