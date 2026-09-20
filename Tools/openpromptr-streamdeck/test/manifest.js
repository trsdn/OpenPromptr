#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

/**
 * Checks the manifest against the rules the two deck apps disagree about.
 *
 * One manifest serves both, which is only worth having if it keeps satisfying
 * the stricter of the two. OpenDeck ignores most of what Elgato insists on —
 * an uppercase letter in a UUID, a three-part version, an SVG where only a PNG
 * will do — so every one of those mistakes would work perfectly here and be
 * rejected on the way to a Stream Deck.
 *
 * The rules are Elgato's, from
 * https://docs.elgato.com/streamdeck/sdk/references/manifest/. Their published
 * schema is the real authority and is worth running against
 * `com.trsdn.openpromptr.sdPlugin/manifest.json` when this changes, but it lives
 * on the network, and a check that needs the network is a check that gets
 * skipped.
 *
 * The most valuable of these is the dullest: that every file the manifest names
 * actually exists. Renaming an icon breaks nothing until a key is blank.
 */

const here = path.dirname(fileURLToPath(import.meta.url));
const plugin = path.join(here, "..", "com.trsdn.openpromptr.sdPlugin");
const manifest = JSON.parse(fs.readFileSync(path.join(plugin, "manifest.json"), "utf8"));

const checks = [];
const check = (name, body) => checks.push([name, body]);

/** Resolves an extension-less image path the way a deck app does. */
function resolveImage(reference) {
    for (const extension of [".svg", ".png", ".gif"]) {
        const candidate = path.join(plugin, reference + extension);
        if (fs.existsSync(candidate)) return candidate;
    }
    return null;
}

check("every file the manifest names is actually there", () => {
    const images = [manifest.Icon, manifest.CategoryIcon];
    for (const action of manifest.Actions) {
        images.push(action.Icon, ...action.States.map((state) => state.Image));
        if (action.PropertyInspectorPath) {
            const inspector = path.join(plugin, action.PropertyInspectorPath);
            assert.ok(fs.existsSync(inspector), `${action.PropertyInspectorPath} is missing`);
        }
    }
    for (const image of images.filter(Boolean)) {
        assert.ok(resolveImage(image), `${image} has no file in any supported format`);
        assert.ok(
            !path.extname(image),
            `${image} must be given without its extension; the app picks the format`,
        );
    }
    assert.ok(fs.existsSync(path.join(plugin, manifest.CodePath)), "CodePath does not exist");
});

check("the plugin icon is a PNG, the one place an SVG is refused", () => {
    // Elgato takes SVG for action and state images, but not for the plugin icon
    // shown in its store and settings.
    const icon = resolveImage(manifest.Icon);
    assert.equal(path.extname(icon), ".png", "the plugin Icon has to be a PNG");
    assert.ok(
        fs.existsSync(path.join(plugin, `${manifest.Icon}@2x.png`)),
        "the plugin Icon needs a @2x companion",
    );
});

check("the version has the four parts Elgato requires", () => {
    assert.match(manifest.Version, /^\d+\.\d+\.\d+\.\d+$/, "Elgato wants major.minor.patch.build");
});

check("every uuid is lowercase, as Elgato refuses anything else", () => {
    const uuids = [manifest.UUID, ...manifest.Actions.map((action) => action.UUID)];
    for (const uuid of uuids) {
        assert.match(uuid, /^[a-z0-9.-]+$/, `${uuid} may only hold a-z, 0-9, a dot or a hyphen`);
    }
});

check("the folder is named after the uuid, which is how both apps find it", () => {
    assert.equal(path.basename(plugin), `${manifest.UUID}.sdPlugin`);
});

check("it asks for a node both apps can give it", () => {
    // Stream Deck bundles its own; "20" is the oldest it offers and so the
    // widest net. It only works because the plugin brings its own WebSocket:
    // Node grew a global one unflagged in 22.4, which Stream Deck only reaches
    // from 7.1 with "24".
    assert.equal(manifest.Nodejs?.Version, "20");
    assert.equal(manifest.Software?.MinimumVersion, "6.4");
});

check("the plugin folder declares itself a module, or nothing will load it", () => {
    // Node only guesses at module syntax from 22.7. Stream Deck's is older, and
    // the deck apps run the folder on its own, away from any package.json above
    // it in the repository.
    const own = JSON.parse(fs.readFileSync(path.join(plugin, "package.json"), "utf8"));
    assert.equal(own.type, "module");
});

check("it claims no dependencies, because nothing installs them", () => {
    const own = JSON.parse(fs.readFileSync(path.join(plugin, "package.json"), "utf8"));
    assert.ok(!own.dependencies, "a deck app copies the folder and runs it; npm never sees it");
});

// MARK: - Running

const failures = [];
for (const [name, body] of checks) {
    try {
        body();
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
