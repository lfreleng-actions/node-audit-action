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
`npm audit`.

## node-audit-action

The action runs `npm audit --json`, captures the full report to a file
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
the pinned `actions/setup-node` action, without dependency caching.
`npm audit` needs egress to the npm registry
(`registry.npmjs.org`).

## Inputs

<!-- markdownlint-disable MD013 -->

| Name              | Required | Default | Description                                                                       |
| ----------------- | -------- | ------- | --------------------------------------------------------------------------------- |
| path_prefix       | False    | `.`     | Project directory; must resolve within the workspace                              |
| node_version      | False    | `22`    | Node.js version to set up, such as `22`, `22.x` or `lts/*`                        |
| node_version_file | False    | `''`    | File containing the Node.js version, such as `.nvmrc`; overrides `node_version`   |
| audit_level       | False    | `high`  | Fail threshold severity: `info`, `low`, `moderate`, `high` or `critical`          |
| production_only   | False    | `false` | Restrict the audit to production dependencies (`--omit=dev`)                      |
| permit_fail       | False    | `false` | Report vulnerabilities at/above the threshold without failing                     |
| output_directory  | False    | `.`     | JSON report directory, within workspace or runner temp                            |

<!-- markdownlint-enable MD013 -->

The `node_version` input accepts the characters `A-Z a-z 0-9 . * / _ -`
and the `node_version_file` input accepts `A-Z a-z 0-9 . / _ -`; the
version file must resolve to a file within the workspace.

## Outputs

<!-- markdownlint-disable MD013 -->

| Name                | Description                                                    |
| ------------------- | -------------------------------------------------------------- |
| audit_passed        | `true` when no vulnerabilities at/above the threshold exist    |
| vulnerability_count | Total vulnerabilities reported across all severities           |
| report_path         | Path to the JSON audit report (`npm-audit-report.json`)        |

<!-- markdownlint-enable MD013 -->

The `vulnerability_count` output reports the total across every
severity, independent of the configured threshold; `audit_passed`
reflects the threshold evaluation.

## Threshold Evaluation

The `audit_level` input maps to the `npm audit --audit-level` concept:
vulnerabilities at or above the configured severity fail the audit.
The action evaluates the threshold itself from the report's
`.metadata.vulnerabilities` counts rather than relying on npm exit
codes, so the JSON report persists in full for every outcome. With
`permit_fail: 'true'` the action reports the findings, emits a
warning and succeeds, which suits informational audit jobs.

## Missing Lockfile Handling

`npm audit` requires a lockfile and fails with `ENOLOCK` when one is
missing, a common state in legacy Linux Foundation projects that
installed from `package.json` alone. When the project has neither
`package-lock.json` nor `npm-shrinkwrap.json`, the action synthesizes
one first: it runs `npm install` in lockfile-write mode (the
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

1. **Input Validation**: Validates the severity enum, boolean flags and version specifiers (restricted character sets) before use; verifies the project directory exists within the workspace and contains a `package.json`
2. **Node.js Setup**: Installs Node.js via the pinned `actions/setup-node` action; `node_version_file` takes precedence over `node_version` when both have values
3. **Lockfile Synthesis**: Creates a transient `package-lock.json` when the project lacks a lockfile, removed on step exit
4. **Audit and Evaluation**: Runs `npm audit --json`, captures the report, evaluates the threshold from the report metadata and emits outputs plus a step summary

<!-- markdownlint-enable MD013 -->

## Notes

- The action performs no dependency caching, in line with the
  organisation's cache-poisoning stance
- Fresh lockfile synthesis resolves the newest versions the project's
  version ranges permit, so results for lockfile-free projects reflect
  the tree a fresh install would produce, not a historical install

[pre-commit.ci results page]: https://results.pre-commit.ci/latest/github/lfreleng-actions/node-audit-action/main
[pre-commit.ci status badge]: https://results.pre-commit.ci/badge/github/lfreleng-actions/node-audit-action/main.svg
