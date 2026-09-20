#!/usr/bin/env node
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

/**
 * The plugin's format and static checks, without a linter to install.
 *
 * The plugin has no dependencies and no build step on purpose, so a check that
 * needs `npm install` would be the only thing that did. This is the small part
 * of one that has caught real problems here: source that does not parse, tabs,
 * trailing whitespace, a missing final newline, and lines too long to read in a
 * diff.
 */

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const MAX_LINE = 120;

function files(dir) {
    return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
        if (entry.name === "node_modules" || entry.name.startsWith(".")) return [];
        const full = path.join(dir, entry.name);
        return entry.isDirectory() ? files(full) : [full];
    });
}

const sources = files(root).filter((file) => /\.(js|json|html|css|sh)$/.test(file));
const scripts = sources.filter((file) => file.endsWith(".js"));

const checks = [];
const check = (name, body) => checks.push([name, body]);
const relative = (file) => path.relative(root, file);

check("every script parses", () => {
    for (const file of scripts) {
        const result = spawnSync(process.execPath, ["--check", file], { encoding: "utf8" });
        assert.equal(result.status, 0, `${relative(file)} does not parse:\n${result.stderr}`);
    }
});

check("no tabs and no trailing whitespace", () => {
    for (const file of sources) {
        fs.readFileSync(file, "utf8")
            .split("\n")
            .forEach((line, index) => {
                assert.ok(!line.includes("\t"), `${relative(file)}:${index + 1} has a tab`);
                assert.ok(!/\s$/.test(line), `${relative(file)}:${index + 1} has trailing whitespace`);
            });
    }
});

check("every file ends with exactly one newline", () => {
    for (const file of sources) {
        const text = fs.readFileSync(file, "utf8");
        const single = text.endsWith("\n") && !text.endsWith("\n\n");
        assert.ok(single, `${relative(file)} does not end in one newline`);
    }
});

check(`no script line is longer than ${MAX_LINE} characters`, () => {
    for (const file of scripts) {
        fs.readFileSync(file, "utf8")
            .split("\n")
            .forEach((line, index) => {
                assert.ok(line.length <= MAX_LINE, `${relative(file)}:${index + 1} is ${line.length} characters`);
            });
    }
});

check("scripts are modules that import only what they use", () => {
    // A cheap stand-in for a no-unused-imports rule: a named import that never
    // appears again in the file is dead weight and usually a leftover.
    for (const file of scripts) {
        const text = fs.readFileSync(file, "utf8");
        for (const match of text.matchAll(/^import\s+(?:(\w+)|\{([^}]+)\})\s+from/gm)) {
            const listed = match[2]?.split(",").map((name) => name.trim().split(/\s+as\s+/).pop());
            const names = match[1] ? [match[1]] : listed;
            for (const name of names.filter(Boolean)) {
                const uses = text.match(new RegExp(`\\b${name}\\b`, "g")).length;
                assert.ok(uses > 1, `${relative(file)} imports ${name} and never uses it`);
            }
        }
    }
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
