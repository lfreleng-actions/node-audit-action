# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation

# Normalise a native Yarn, pnpm or Bun audit into the report shape the
# action evaluates for npm: .metadata.vulnerabilities counts vulnerable
# packages per severity plus a total. .advisories lists each advisory
# once per package, and .nativeReport keeps the tool's own output (NDJSON
# streams become an array of their events).
#
# Input: the tool's raw stdout as one string (jq --raw-input --slurp)
# Arguments:
#   $tool       yarn-classic, yarn-berry, pnpm or bun
#   $version    the package manager version that ran the audit
#   $exit_code  the audit command's exit status
#   $errors     the audit command's stderr (jq --rawfile)
#
# Output the tool cannot have produced from a completed audit yields
# .error.summary in place of .metadata, which the action reports as a
# tool failure rather than as a clean result.

def severities: ["info", "low", "moderate", "high", "critical"];

# Registries report npm's five severities; GitHub's advisory database
# names the middle one 'medium'. Anything else fails closed rather
# than dropping out of the threshold evaluation
def severity:
  (if type == "string" then ascii_downcase else "" end) as $raw
  | (if $raw == "medium" then "moderate" else $raw end) as $level
  | if any(severities[]; . == $level) then $level
    else error("unrecognised severity: \($raw)")
    end;

def advisory($advisory_id; $package_name; $level; $title_text; $link):
  {
    id: $advisory_id,
    package: $package_name,
    severity: ($level | severity),
    title: $title_text,
    url: $link
  };

def nonblank: test("\\S");

def no_output:
  error("no audit output (exit code \($exit_code))");

def parse_json:
  . as $text
  | try fromjson
    catch error("unexpected output: \($text | .[0:200])");

def ndjson:
  [splits("\r?\n") | select(nonblank) | parse_json];

# The npm v1 audit format, emitted by pnpm and by 'yarn npm audit' in
# Yarn 2 and 3
def from_v1:
  if type != "object" then
    error("unexpected report type: \(type)")
  elif (.error | type) == "object" then
    error(.error.message // .error.summary // (.error | tojson))
  elif (.advisories | type) != "object" then
    error("report carries no advisories object")
  else
    [.advisories[]
      | advisory(.id; .module_name; .severity; .title; .url)]
  end;

# 'yarn audit --json' streams events; a completed audit always ends
# with an auditSummary, and failures arrive as error events
def yarn_classic:
  ndjson as $events
  | [$events[] | select(.type == "error") | .data | tostring] as $errors
  | if ($errors | length) > 0 then
      error($errors | join("; "))
    elif (any($events[]; .type == "auditSummary") | not) then
      error("no auditSummary event in the output")
    else
      {
        native: $events,
        advisories: [$events[]
          | select(.type == "auditAdvisory")
          | .data.advisory
          | advisory(.id; .module_name; .severity; .title; .url)]
      }
    end;

# Yarn 4 prints one advisory per line and nothing at all when clean,
# so empty output only counts as clean with a zero exit status. Yarn
# 2 and 3 print a single npm v1 document instead
def yarn_berry:
  if nonblank | not then
    if $exit_code == "0" then {native: [], advisories: []}
    else no_output
    end
  else
    ndjson as $docs
    | if ($docs | length) == 1
        and ($docs[0] | type) == "object"
        and ($docs[0] | has("advisories") or has("error")) then
        {native: $docs[0], advisories: ($docs[0] | from_v1)}
      else
        {
          native: $docs,
          advisories: [$docs[]
            | if type == "object" and (.children | type) == "object" then
                advisory(.children.ID; .value; .children.Severity;
                  .children.Issue; .children.URL)
              else
                error("unexpected output: \(tojson | .[0:200])")
              end]
        }
      end
  end;

def pnpm:
  if nonblank | not then no_output
  else parse_json as $doc | {native: $doc, advisories: ($doc | from_v1)}
  end;

# 'bun audit --json' maps each package to its advisories and prints
# {} when clean; failures leave stdout empty. Keys are package names,
# so none is reserved: an entry that is not an advisory list fails.
# A registry answering the audit request with an error status is
# skipped, its packages unaudited, with a stderr warning alone and
# the exit status of a complete audit
def bun:
  [$errors | splits("\n")
    | select(test("did not answer the audit request"))
    | sub("^\\s*warn:\\s*"; "")] as $skipped
  | if ($skipped | length) > 0 then
    error("incomplete audit: \($skipped | join("; "))")
  elif nonblank | not then no_output
  else
    parse_json as $doc
    | if ($doc | type) != "object" then
        error("unexpected report type: \($doc | type)")
      else
        {
          native: $doc,
          advisories: [$doc
            | to_entries[]
            | .key as $package
            | if (.value | type) == "array" then
                .value[]
                | advisory(.id; $package; .severity; .title; .url)
              else
                error("unexpected entry for \($package)")
              end]
        }
      end
  end;

# npm counts vulnerable packages rather than advisories: each package
# once, at the highest severity among its advisories
def counts:
  [group_by(.package)[]
    | map(.severity as $level | severities | index($level))
    | severities[max]]
  | reduce .[] as $level
      ({info: 0, low: 0, moderate: 0, high: 0, critical: 0};
        .[$level] += 1)
  | .total = ([.[]] | add);

try (
  if $tool == "yarn-classic" then yarn_classic
  elif $tool == "yarn-berry" then yarn_berry
  elif $tool == "pnpm" then pnpm
  elif $tool == "bun" then bun
  else error("unsupported tool: \($tool)")
  end
  # Yarn classic repeats an advisory for every dependency path
  | .advisories |= unique_by([.package, (.id | tostring)])
  | {
      packageManager: $tool,
      packageManagerVersion: $version,
      metadata: {vulnerabilities: (.advisories | counts)},
      advisories,
      nativeReport: .native
    }
) catch {
  packageManager: $tool,
  packageManagerVersion: $version,
  error: {
    summary: (if type == "string" then . else tojson end
      | gsub("\u001b\\[[0-9;]*[A-Za-z]"; ""))
  }
}
