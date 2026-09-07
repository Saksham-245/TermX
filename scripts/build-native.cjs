"use strict"

const { spawnSync } = require("node:child_process")

const npm = process.platform === "win32" ? "npm.cwd" : "npm";

const script = {
    darwin: "build:native:macos",
    linux: "build:native:linux"
}[process.platform];

if (!script) {
    throw new Error(`Native build is unsupported on ${process.platform}`);
}

const result = spawnSync(
    npm,
    ["run", script],
    {
        stdio: "inherit"
    }
);

if (result.error) {
    throw result.error;
}

process.exit(result.status ?? 1);