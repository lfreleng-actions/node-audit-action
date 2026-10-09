<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
-->

# 🛡️ Node.js Dependency Audit Action

<!-- prettier-ignore-start -->
<!-- markdownlint-disable-next-line MD013 -->
[![Linux Foundation](https://img.shields.io/badge/Linux-Foundation-blue)](https://linuxfoundation.org/) [![Source Code](https://img.shields.io/badge/GitHub-100000?logo=github&logoColor=white&color=blue)](https://github.com/lfreleng-actions/node-audit-action) [![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![pre-commit.ci status badge]][pre-commit.ci results page] [![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/lfreleng-actions/node-audit-action/badge)](https://scorecard.dev/viewer/?uri=github.com/lfreleng-actions/node-audit-action)
<!-- prettier-ignore-end -->

Audits Node.js project dependencies for known vulnerabilities with
the package manager that owns the project's lockfile: npm, Yarn
(classic or Berry), pnpm or Bun.

## node-audit-action

The action runs the package manager's own audit against the lockfile
the project installs from, captures the full report to a file
regardless of the outcome, then evaluates the severity threshold from
the report metadata. The interface mirrors
[python-audit-action](https://github.com/lfreleng-actions/python-audit-action),
giving callers one contract across the actions estate.

## Usage Example

<!-- markdownlint-disable MD046 -->

```yaml
steps:
  - name: "Audit Node.js dependencies"
    id: audit
    uses: lfreleng-actions/node-audit-action@main
    with:
      path_prefix: '.'
      audit_level: high
```

<!-- markdownlint-enable MD046 -->

## Requirements

The action needs `jq` and `realpath` (GNU coreutils, including `-m`
support) on the runner. GitHub-hosted Ubuntu runners
include these tools; minimal self-hosted or non-Linux runners must
provide them. The action checks for them up front and fails with a
clear error naming any missing tool. It installs Node.js and npm via
the pinned `actions/setup-node` action, without dependency caching:
it passes `package-manager-cache: false`, so a `packageManager` or
`devEngines.packageManager` field naming npm does not switch on
setup-node's automatic npm cache.
Yarn and pnpm come from Corepack, which the action installs into the
runner's temporary directory with `npm ci` from its own lockfile
(`scripts/tools`). That Corepack release supports Node.js
`^20.10.0`, `^22.11.0` or `>=24.0.0`; with an older Node.js, Yarn
and pnpm audits fail with an error naming the supported range. Bun
comes from the pinned `oven-sh/setup-bun` action, with its cache
disabled.

Each audit needs egress to its tool and advisory endpoints:

<!-- markdownlint-disable MD013 -->

| Package manager | Hosts                                                                                               |
| --------------- | --------------------------------------------------------------------------------------------------- |
| npm             | `registry.npmjs.org`                                                                                |
| Yarn classic    | `registry.npmjs.org` (Corepack), `registry.yarnpkg.com` (Yarn download and audit)                   |
| Yarn Berry      | `registry.npmjs.org` (Corepack), `repo.yarnpkg.com` (Yarn download), `registry.yarnpkg.com` (audit) |
| pnpm            | `registry.npmjs.org`                                                                                |
| Bun             | `github.com` and `release-assets.githubusercontent.com` (download), `registry.npmjs.org`            |

<!-- markdownlint-enable MD013 -->

Runners under a `harden-runner` block policy must allow these hosts.
Registry settings in a project's `.npmrc`, `.yarnrc.yml` or
`bunfig.toml` redirect the npm, pnpm, Yarn Berry and Bun advisory
queries, for example to a Nexus proxy. Yarn classic always sends its
audit to `registry.yarnpkg.com`, whatever the registry settings say.
Set `COREPACK_NPM_REGISTRY` in the job environment to fetch Yarn and
pnpm releases through a proxy too.

## Inputs

<!-- markdownlint-disable MD013 -->

| Name              | Required | Default | Description                                                                       |
| ----------------- | -------- | ------- | --------------------------------------------------------------------------------- |
| path_prefix       | False    | `.`     | Project directory; must resolve within the workspace                              |
| node_version      | False    | `22`    | Node.js version to set up, such as `22`, `22.x` or `lts/*`                        |
| node_version_file | False    | `''`    | File containing the Node.js version, such as `.nvmrc`; overrides `node_version`   |
| audit_level       | False    | `high`  | Fail threshold severity: `info`, `low`, `moderate`, `high` or `critical`          |
| production_only   | False    | `false` | Restrict the audit to production dependencies (see Native Audits)                 |
| permit_fail       | False    | `false` | Report vulnerabilities at/above the threshold without failing                     |
| output_directory  | False    | `.`     | JSON report directory, within workspace or runner temp                            |
| package_manager   | False    | `auto`  | `auto` (detect from the lockfile), `npm`, `yarn`, `pnpm` or `bun`                 |

<!-- markdownlint-enable MD013 -->

The `node_version` input accepts the characters `A-Z a-z 0-9 . * / _ -`
and the `node_version_file` input accepts `A-Z a-z 0-9 . / _ -`; the
version file must resolve to a file within the workspace.

## Outputs

<!-- markdownlint-disable MD013 -->

| Name                | Description                                                      |
| ------------------- | ---------------------------------------------------------------- |
| audit_passed        | `true` when no vulnerabilities at/above the threshold exist      |
| vulnerability_count | Total vulnerabilities reported across all severities             |
| report_path         | Path to the JSON audit report (`<manager>-audit-report.json`)    |
| package_manager     | Package manager that ran the audit: `npm`, `yarn`, `pnpm`, `bun` |

<!-- markdownlint-enable MD013 -->

The `vulnerability_count` output reports the total across every
severity, independent of the configured threshold; `audit_passed`
reflects the threshold evaluation. Every package manager counts
vulnerable packages, each at the highest severity among its
advisories, as npm does; npm also counts a package whose advisory
lies in a dependency when fixing it needs that package to change.

## Package Manager Detection

With `package_manager: auto` the action audits with the package
manager whose lockfile the project directory holds:

| Lockfile                                   | Package manager |
| ------------------------------------------ | --------------- |
| `package-lock.json`, `npm-shrinkwrap.json` | npm             |
| `pnpm-lock.yaml`                           | pnpm            |
| `yarn.lock`                                | Yarn            |
| `bun.lock`, `bun.lockb`                    | Bun             |

When `package.json` names a package manager in `packageManager` and
its lockfile exists, that one wins. Otherwise the first lockfile in
the table order decides, so a project that npm audited before keeps
npm. A project with no lockfile at all gets the npm lockfile
synthesis described below.

An explicit `yarn`, `pnpm` or `bun` requires that tool's lockfile and
fails without it. An explicit `npm` on a project without an npm
lockfile audits a synthesized npm resolution, as before native
support existed.

Yarn Berry (Yarn 2 and later) applies when `packageManager` names
Yarn 2 or later, or, without a declared release, when the project has
a `.yarnrc.yml` or a Berry-format `yarn.lock`. Otherwise Yarn classic
applies.

## Native Audits

<!-- markdownlint-disable MD013 -->

| Package manager | Command                                                     | `production_only: 'true'` adds                 |
| --------------- | ----------------------------------------------------------- | ---------------------------------------------- |
| npm             | `npm audit --json`                                          | `--omit=dev`                                   |
| Yarn classic    | `yarn audit --json`                                         | `--groups "dependencies optionalDependencies"` |
| Yarn Berry      | `yarn npm audit --json --recursive --all --no-deprecations` | `--environment production`                     |
| pnpm            | `pnpm audit --json`                                         | `--prod`                                       |
| Bun             | `bun audit --json`                                          | `--prod`                                       |

<!-- markdownlint-enable MD013 -->

Corepack runs the Yarn or pnpm release `package.json` declares in
`packageManager`. Without one, the action uses Yarn 1.22.22, Yarn
4.18.1 or pnpm 10.34.6. Declare the release the lockfile came from:
a different Yarn Berry release can reject the lockfile, which fails
the audit. Corepack never writes `packageManager` into `package.json`
here. Bun runs the action's pinned release (1.4.2), since
`bun audit` needs Bun 1.2.15 or later.

Yarn 2 and 3 do not report deprecations and reject
`--no-deprecations`, so the action omits it for them. The audit
settings each tool reads from the project still apply, such as
pnpm's `auditConfig` or Yarn's `npmAuditIgnoreAdvisories`.

Yarn classic, Yarn 2 and 3, and pnpm 10 and earlier query the npm
registry's original audit endpoint (`/-/npm/v1/security/audits`)
rather than its bulk advisory endpoint. Should a registry withdraw
that endpoint, those audits fail with the registry's error rather
than reporting a clean result.

### Untrusted Projects

The audit never runs code from the project, which makes it safe on
an untrusted checkout such as a pull request from a fork. Some
package manager settings would otherwise run repository code even
without an install, so the action disables them:

- Corepack ignores the project's `.corepack.env`, and runs official
  Yarn and pnpm releases alone.
- Yarn ignores a committed release (`yarnPath`, `yarn-path`).
- Yarn Berry reads a sanitised copy of each `.yarnrc.yml` from the
  project directory up to the workspace root, and of the user's own,
  without `plugins`, `yarnPath` and `injectEnvironmentFiles`. It runs
  with `HOME` set to a temporary folder holding the user's sanitised
  copy, since Yarn reads the home file whatever its configured name.
  Configuration files above the workspace go unread. A project whose
  audit depends on a Yarn plugin fails rather than running it.
- pnpm skips `.pnpmfile.cjs` hooks, and the action learns the pnpm
  version from Corepack instead of running `pnpm --version`, which
  loads them.

The action writes npm's JSON report unchanged. It normalises the other
tools' output into the same shape: `.metadata.vulnerabilities` holds
the vulnerable package count per severity and the total,
`.advisories` lists each advisory and affected package, and
`.nativeReport` keeps the tool's own output, with NDJSON streams
collected into an array. `packageManager` and `packageManagerVersion`
record the tool that ran. Output the tool would not produce from a
completed audit (empty output with a non-zero exit, an error event, a
registry error) fails the action rather than passing as clean. So
does a Bun audit that skipped a registry: Bun audits each scoped
registry separately, and when one answers with an error it warns on
stderr and reports the rest as if complete.

The action builds the report in the runner's temporary directory,
then publishes it by replacing the file at `report_path` rather than
writing through it, so a symlink planted in the checkout cannot
redirect the write. Yarn's install state, cache and global folders
also go to the temporary directory, whatever the project's
configuration says, and the npm lockfile synthesis refuses a
`package-lock.json` or `npm-shrinkwrap.json` that is not a regular
file, such as a dangling symlink or a directory.

## Threshold Evaluation

The `audit_level` input maps to the `npm audit --audit-level` concept:
vulnerabilities at or above the configured severity fail the audit.
The action evaluates the threshold itself from the report's
`.metadata.vulnerabilities` counts rather than relying on exit codes,
keeping the full JSON report for every outcome. With
`permit_fail: 'true'` the action reports the findings, emits a
warning and succeeds, which suits informational audit jobs.

## Missing Lockfile Handling

`npm audit` requires a lockfile and fails with `ENOLOCK` when one is
missing, a common state in legacy Linux Foundation projects that
installed from `package.json` alone. When the project has no lockfile
of any supported package manager (or the caller selects npm for a
project without `package-lock.json` or `npm-shrinkwrap.json`), the
action synthesizes one first: it runs `npm install` in lockfile-write
mode (the
`package-lock` flag family), passing `--ignore-scripts` so no
install scripts execute, plus `--no-audit` and `--no-fund` to skip
the audit and funding checks during resolution. This resolves the
dependency tree against the
registry without installing packages or running scripts; the exact
command appears in `action.yaml`. The action removes the synthesized
lockfile when the audit step exits, leaving the workspace as found.
Lockfiles record every dependency scope, so the synthesis needs no
production filtering; the audit itself applies `--omit=dev` when
`production_only` is `'true'`.

## Path Constraints

Relative values for `path_prefix` and `output_directory` resolve
against `GITHUB_WORKSPACE`, not the current working directory, so
behaviour stays deterministic when a calling workflow sets a custom
working directory. The action checks both directory inputs against
the runner filesystem before use: `path_prefix` must resolve within
`GITHUB_WORKSPACE`, and `output_directory` must resolve within
`GITHUB_WORKSPACE` or `RUNNER_TEMP`. Paths that escape these
locations fail the action.

## Step Summary

The action writes a severity breakdown table to the workflow step
summary:

| Severity  | Count |
| --------- | ----- |
| Critical  | 0     |
| High      | 2     |
| Moderate  | 5     |
| Low       | 1     |
| Info      | 0     |
| **Total** | **8** |

## Implementation Details

<!-- markdownlint-disable MD013 -->

1. **Input Validation**: Validates the severity enum, boolean flags, package manager and version specifiers (restricted character sets) before use; verifies the project directory exists within the workspace and contains a `package.json`, then selects the package manager
2. **Node.js Setup**: Installs Node.js via the pinned `actions/setup-node` action; `node_version_file` takes precedence over `node_version` when both have values. Bun projects also get Bun via the pinned `oven-sh/setup-bun` action
3. **Lockfile Synthesis**: Creates a transient `package-lock.json` when the project lacks any lockfile, removed on step exit
4. **Audit and Evaluation**: Runs the native audit (Yarn and pnpm through Corepack), normalises the report where needed, evaluates the threshold from the report metadata and emits outputs plus a step summary

<!-- markdownlint-enable MD013 -->

## Notes

- The action performs no dependency caching, in line with the
  organisation's cache-poisoning stance (CWE-349); it disables
  setup-node's automatic npm cache explicitly
- Fresh lockfile synthesis resolves the newest versions the project's
  version ranges permit, so results for lockfile-free projects reflect
  the tree a fresh install would produce, not a historical install

[pre-commit.ci results page]: https://results.pre-commit.ci/latest/github/lfreleng-actions/node-audit-action/main
[pre-commit.ci status badge]: https://results.pre-commit.ci/badge/github/lfreleng-actions/node-audit-action/main.svg
