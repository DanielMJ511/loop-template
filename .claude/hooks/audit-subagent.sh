#!/usr/bin/env sh
# Loop audit hook - SubagentStop (POSIX). Counterpart of audit-subagent.ps1;
# see that file's header for what this log is for and why it is structural only.
#
# Takes the calling agent's name as $1, used only if the payload omits
# agent_type.
#
# Every path exits 0. Exit code 2 on SubagentStop *prevents the subagent from
# stopping*, so a crash here would hang the loop rather than lose a log line.
#
# Needs jq or python3 to read the hook payload. If neither is present it exits
# silently - the loop still works, it just has no audit trail.

raw=$(cat)
[ -n "$raw" ] || exit 0

# Pick a JSON reader by PROBING it, never by `command -v` alone. On Windows,
# `python3` commonly resolves to the Microsoft Store App Execution Alias: it
# satisfies `command -v`, prints "Python was not found", exits 49, and writes
# nothing to stdout. Presence-detection therefore picked a reader that returns
# empty for every field, which disabled this hook silently - and the same bug
# left the blocking git guard allowing a real `git stash` through. Measured on
# Windows 11 + Git Bash with jq absent.
#
# perl is third because it ships with Git for Windows, which is already this
# template's Windows prerequisite, so a Git Bash box parses with nothing to
# install. The .ps1 twin needs none of this - it has ConvertFrom-Json.
JSON_READER=''
for _c in jq python3 perl; do
    command -v "$_c" >/dev/null 2>&1 || continue
    case $_c in
        jq)      _v=$(printf '{"k":"v"}' | jq -r '.k // ""' 2>/dev/null) ;;
        python3) _v=$(printf '{"k":"v"}' | python3 -c \
                     'import sys,json;print(json.load(sys.stdin).get("k") or "")' 2>/dev/null) ;;
        perl)    _v=$(printf '{"k":"v"}' | perl -MJSON::PP -e \
                     'my $d=eval{JSON::PP->new->decode(do{local $/;<STDIN>})};print defined $d->{k} ? $d->{k} : ""' 2>/dev/null) ;;
    esac
    [ "$_v" = v ] && { JSON_READER=$_c; break; }
done

json_get() {
    case $JSON_READER in
        jq)      printf '%s' "$raw" | jq -r --arg k "$1" '.[$k] // ""' 2>/dev/null ;;
        python3) printf '%s' "$raw" | python3 -c \
                     'import sys,json;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null ;;
        perl)    printf '%s' "$raw" | perl -MJSON::PP -e \
                     'my $d=eval{JSON::PP->new->decode(do{local $/;<STDIN>})};my $v=$d->{$ARGV[0]};print defined $v ? $v : ""' "$1" 2>/dev/null ;;
    esac
}

# Write only inside a project that has adopted the loop. cwd is the authority on
# where we are; a hook registered at user scope fires in every project.
root=$(json_get cwd)
[ -n "$root" ] || exit 0
[ -d "$root/loop" ] || exit 0

agent=$(json_get agent_type)
[ -n "$agent" ] || agent="$1"
[ -n "$agent" ] || agent=unknown

id=$(json_get agent_id | cut -c1-8)
[ -n "$id" ] || id='-'

msg=$(json_get last_assistant_message)

# Two views of the message. `flat` keeps the original characters so T-003 stays
# intact; `norm` reduces every non-alphanumeric to a space so a token can be
# matched on whole-word boundaries with a plain substring test. The .ps1 twin
# performs exactly this normalization - the two must agree byte for byte on the
# same payload, or the log's verdict column becomes platform-dependent.
flat=$(printf '%s' "$msg" | tr '\n\r\t' '   ' | tr -s ' ')
norm=$(printf '%s' "$msg" | tr -c 'A-Za-z0-9' ' ' | tr -s ' ')

# Task id. Prefer the agent's declared `TASK:` line, exactly as the verdict
# below prefers its `VERDICT:` line and for the same reason. The prose fallback
# logs the FIRST id anywhere in the report, which is the wrong one whenever a
# summary mentions an earlier task before naming its own: observed in a real
# run, a T-004 code review logged as T-003 because the diff's context named the
# task that created the file. `TASK: -` is a valid declaration, and the only way
# a unit-scoped agent can say "no task" rather than have it inferred.
task=$(printf '%s' "$flat" | grep -oiE 'TASK:[[:space:]]*(T-[0-9]{3}|-)' | head -1     | grep -oE 'T-[0-9]{3}|-$')
[ -n "$task" ] || task=$(printf '%s' "$flat" | grep -oE 'T-[0-9]{3}' | head -1)
[ -n "$task" ] || task='-'

# Verdict vocabulary, shared with audit-subagent.ps1 and with the agent files
# that emit it. Ordered most-specific first, because matching is substring-based
# on word-bounded text: NOT VERIFIED must be tested before VERIFIED and
# NO FINDINGS before FINDINGS, or the negative verdict logs as its opposite.
#
# Keep this list in sync with the `VERDICT:` lines in .claude/agents/. A token
# no agent emits is dead weight; an agent verdict absent here logs as `-`, which
# is indistinguishable from "the agent said nothing".
VERDICTS='NO TESTS EXECUTED
UNABLE TO AUDIT
CHANGES REQUESTED
NOT VERIFIED
NO FINDINGS
TESTS PASSED
TESTS FAILED
APPROVED
VERIFIED
FINDINGS
BLOCKED'

# Print the first token in $VERDICTS that appears in $norm behind $1, or nothing.
# Splits on newline into positional params rather than piping into `while read`,
# which would run the loop in a subshell and lose the result.
find_verdict() {
    _prefix=$1
    _oldifs=$IFS
    IFS='
'
    set -- $VERDICTS
    IFS=$_oldifs
    for _pat do
        case " $norm " in
            *" $_prefix$_pat "*) printf '%s' "$_pat"; return 0 ;;
        esac
    done
    return 1
}

# Verdict scanning runs ONLY for the four agents that have a verdict vocabulary.
# For every other agent BOTH scans are skipped and the column stays `-`.
#
# The agent's declared `VERDICT: <token>` line is preferred; scanning free prose
# is the fallback only, because it fires on a token used mid-sentence ("not
# APPROVED-ing it yet") and this log is meant to be the record no agent can shape.
#
# Restricting only the *prose* scan is not enough, and that half-fix shipped once.
# A docs-writer unit-close entry quotes the auditor's `VERDICT: NO FINDINGS`
# verbatim; that normalizes to `VERDICT NO FINDINGS` and matches the *prefixed*
# scan, logging a verdict for a stage that has none - the very failure the
# earlier fix claimed to close. Observed in a real run (docs-writer, 2026-08-27).
# An agent that emits no verdict must not be able to acquire one by quoting
# somebody else's.
# `builder` is a third case: it carries a verdict ONLY on the direct route, where
# /orchestrate folds the test stage into its spawn. It therefore gets the
# declared-line scan and NOT the prose fallback - on the full route it writes
# about tests it did not run and about the guard it proved, which is exactly the
# prose that would mint a verdict out of nothing. A full-route builder emits no
# `VERDICT:` line, and its column stays `-`.
signal=''
case "$agent" in
    test-runner|verifier|code-reviewer|security-auditor)
        signal=$(find_verdict 'VERDICT ')
        [ -n "$signal" ] || signal=$(find_verdict '')
        ;;
    builder)
        signal=$(find_verdict 'VERDICT ')
        ;;
esac
[ -n "$signal" ] || signal='-'

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s | %s | %s | %s | %s\n' "$stamp" "$agent" "$task" "$signal" "$id" \
    >> "$root/loop/AUDIT.log" 2>/dev/null

exit 0
