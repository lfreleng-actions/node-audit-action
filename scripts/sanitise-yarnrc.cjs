// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 The Linux Foundation

// Copy a Yarn Berry rc file without the settings that make Yarn run
// code the repository supplies: plugins, a committed release
// (yarnPath, and ignorePath, which would re-enable it) and the files
// injectEnvironmentFiles loads into the environment, where they could
// set NODE_OPTIONS. Plugins can define settings of their own, so
// strict settings go off rather than failing on those.
//
// Usage: node sanitise-yarnrc.cjs <source> <destination>
//
// The failsafe schema reads every scalar as a string, as Yarn's own
// parser does, so values such as tokens round-trip unchanged.

"use strict";

const fs = require("node:fs");
const YAML = require("yaml");

const UNTRUSTED_SETTINGS = [
  "enableStrictSettings",
  "ignorePath",
  "injectEnvironmentFiles",
  "plugins",
  "yarnPath",
];

const [source, destination] = process.argv.slice(2);
if (!source || !destination) {
  console.error("Usage: sanitise-yarnrc.cjs <source> <destination>");
  process.exit(64);
}

const document = YAML.parseDocument(fs.readFileSync(source, "utf8"), {
  schema: "failsafe",
});
if (document.errors.length > 0) {
  console.error(`${source}: ${document.errors[0].message}`);
  process.exit(1);
}

const settings = document.toJS() ?? {};
if (typeof settings !== "object" || Array.isArray(settings)) {
  console.error(`${source}: expected a mapping of settings`);
  process.exit(1);
}
for (const key of UNTRUSTED_SETTINGS) {
  delete settings[key];
}
settings.enableStrictSettings = "false";

fs.writeFileSync(destination, YAML.stringify(settings), {
  flag: "wx",
  mode: 0o600,
});
