#!/usr/bin/env node
import assert from "node:assert/strict";
import process from "node:process";

import {
    FLIP,
    OUTPUT,
    ROTATION,
    commandFor,
    fillTemplate,
    isLit,
    labelValues,
    rotationIcon,
    targetRotation,
    titleTemplate,
} from "../com.trsdn.openpromptr.sdPlugin/logic.js";

/** What each key does and says, checked against plain state objects. */

const state = (over = {}) => ({
    running: false,
    busy: false,
    status: "Ready",
    error: false,
    permissionGranted: true,
    source: "Virtual display",
    display: { id: 3, name: "AAA" },
    transform: { rotation: 0, mirrorH: false, mirrorV: false },
    ...over,
});

const checks = [];
const check = (name, body) => checks.push([name, body]);

check("the output key starts when idle and stops when running or starting", () => {
    assert.deepEqual(commandFor(OUTPUT, {}, state()), { route: "/v1/output/start" });
    assert.deepEqual(commandFor(OUTPUT, {}, state({ running: true })), { route: "/v1/output/stop" });
    assert.deepEqual(commandFor(OUTPUT, {}, state({ busy: true })), { route: "/v1/output/stop" });
    assert.deepEqual(commandFor(OUTPUT, {}, null), { route: "/v1/output/start" });
});

check("the rotate key steps clockwise by default and wraps around", () => {
    const at = (rotation) => state({ transform: { rotation, mirrorH: false, mirrorV: false } });
    assert.equal(commandFor(ROTATION, {}, at(0)).body.rotation, 90);
    assert.equal(commandFor(ROTATION, {}, at(270)).body.rotation, 0);
    assert.equal(commandFor(ROTATION, { mode: "ccw" }, at(0)).body.rotation, 270);
});

check("a fixed rotation ignores where the image is now", () => {
    assert.equal(targetRotation({ mode: "set", degrees: 180 }, 90), 180);
    assert.equal(targetRotation({ mode: "set" }, 90), 0);
    assert.equal(targetRotation({ mode: "set", degrees: -90 }, 0), 270);
});

check("the flip key toggles just its own axis", () => {
    const flipped = state({ transform: { rotation: 0, mirrorH: true, mirrorV: false } });
    assert.deepEqual(commandFor(FLIP, {}, flipped).body, { mirrorH: false });
    assert.deepEqual(commandFor(FLIP, { axis: "v" }, flipped).body, { mirrorV: true });
});

check("keys light up by what is true, not by what was pressed", () => {
    assert.equal(isLit(OUTPUT, {}, state({ running: true })), true);
    assert.equal(isLit(OUTPUT, {}, state({ busy: true })), false);
    assert.equal(isLit(OUTPUT, {}, null), false);
    assert.equal(isLit(ROTATION, { mode: "set", degrees: 90 }, state({ transform: { rotation: 90 } })), true);
    assert.equal(isLit(ROTATION, { mode: "cw" }, state()), false);
    assert.equal(isLit(FLIP, { axis: "v" }, state({ transform: { mirrorV: true } })), true);
});

check("a label the person wrote wins; an empty one falls back to the default", () => {
    assert.equal(titleTemplate(OUTPUT, { title: "Prompter" }), "Prompter");
    assert.equal(titleTemplate(OUTPUT, { title: "   " }), "{state}");
    assert.equal(titleTemplate(ROTATION, { mode: "set" }), "{target}");
    assert.equal(titleTemplate(ROTATION, {}), "{rotation}");
});

check("switching the label off gives an empty string, which clears an earlier title", () => {
    assert.equal(titleTemplate(FLIP, { showTitle: false, title: "x" }), "");
});

check("placeholders are filled in, newlines expand, unknown ones stay as typed", () => {
    const values = labelValues(FLIP, { axis: "v" }, state({ transform: { rotation: 90, mirrorV: true } }));
    assert.equal(fillTemplate("Flip {axis}\\n{flipped}", values), "Flip V\nOn");
    assert.equal(fillTemplate("{rotation} {nope}", values), "90° {nope}");
    assert.equal(fillTemplate("{display} · {source}", values), "AAA · Virtual display");
});

check("without the app the placeholders say so rather than guessing", () => {
    const values = labelValues(OUTPUT, {}, null);
    assert.equal(values.state, "?");
    assert.equal(values.rotation, "?");
    assert.equal(values.display, "—");
});

check("output state names starting separately from running", () => {
    assert.equal(labelValues(OUTPUT, {}, state({ busy: true })).state, "Starting");
    assert.equal(labelValues(OUTPUT, {}, state({ running: true })).state, "Running");
    assert.equal(labelValues(OUTPUT, {}, state()).state, "Stopped");
});

check("the rotate key's picture follows its mode", () => {
    assert.equal(rotationIcon({}), "rotate-cw");
    assert.equal(rotationIcon({ mode: "ccw" }), "rotate-ccw");
    assert.equal(rotationIcon({ mode: "set" }), "rotate");
});

const failures = [];
for (const [name, body] of checks) {
    try {
        body();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures.push(name);
        console.log(`  FAIL ${name}\n       ${error.message}`);
    }
}
console.log(
    failures.length
        ? `\n${failures.length} of ${checks.length} checks failed`
        : `\n${checks.length}/${checks.length} checks passed`,
);
process.exit(failures.length ? 1 : 0);
