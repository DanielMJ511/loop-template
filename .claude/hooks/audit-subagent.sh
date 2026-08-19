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

json_get() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$raw" | jq -r --arg k "$1" '.[$k] // ""' 2>/dev/null
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$raw" | python3 -c \
            'import sys,json;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null
    fi
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

task=$(printf '%s' "$flat" | grep -oE 'T-[0-9]{3}' | head -1)
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

# Prefer the agent's declared `VERDICT: <token>` line. Scanning free prose is the
# fallback only: it fires on a token used mid-sentence ("not APPROVED-ing it
# yet"), and this log is supposed to be the record no agent can shape.
signal=$(find_verdict 'VERDICT ')

# The prose fallback runs only for agents that HAVE a verdict vocabulary. For the
# others it can produce nothing but false positives: observed in a real run, a
# docs-writer entry reported `APPROVED` because its journal entry quotes the code
# reviewer's verdict, attributing a code-reviewer outcome to a stage that has
# none - and inconsistently, since its sibling spawns logged `-`.
if [ -z "$signal" ]; then
    case "$agent" in
        test-runner|verifier|code-reviewer|security-auditor)
            signal=$(find_verdict '') ;;
    esac
fi
[ -n "$signal" ] || signal='-'

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s | %s | %s | %s | %s\n' "$stamp" "$agent" "$task" "$signal" "$id" \
    >> "$root/loop/AUDIT.log" 2>/dev/null

exit 0
