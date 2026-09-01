#!/usr/bin/env sh
# Runs .claude/hooks/audit-subagent.{sh,ps1} over tests/audit-subagent.cases.
#
# Usage:  sh tests/run-audit-tests.sh            both twins
#         sh tests/run-audit-tests.sh --sh-only  the POSIX twin alone
# Exit:   0 all cases match and both twins agree; 1 otherwise.
#
# Why this exists. `loop/AUDIT.log` is the record no agent can shape - it is
# what /retro reads when it will not take an agent's word for what ran, and it
# is the instrument every measurement of this loop's cost is derived from. Until
# this file there was no executable check on it at all, while the guard next
# door had 39 cases. Every defect it has had shipped past a read-through:
#
#   - the prose scan attributing a T-004 review to T-003, because the diff's
#     context named the creating task first;
#   - `docs-writer` acquiring `NO FINDINGS` by quoting the auditor verbatim,
#     which the first fix claimed to close and did not.
#
# Both are cases below. A log that is quietly wrong is worse than an absent one,
# because it is trusted.
#
# It checks TWO things, the second being the one that caught the real bug in the
# sibling guard:
#   1. each twin's recorded task and verdict against the expectation
#   2. the two twins against EACH OTHER
#
# The .ps1 twin is skipped when no PowerShell is on PATH, and the run says so
# rather than reporting a pass it did not perform.
#
# Needs python3 or jq to build the hook payload, the same two-parser fallback
# the hooks themselves carry.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
cases="$here/audit-subagent.cases"
sh_hook="$root/.claude/hooks/audit-subagent.sh"
ps_hook="$root/.claude/hooks/audit-subagent.ps1"

[ -f "$cases" ]   || { echo "missing $cases";   exit 1; }
[ -f "$sh_hook" ] || { echo "missing $sh_hook"; exit 1; }

# The hook writes only inside a directory that has a loop/ folder, so the
# fixture needs one. Everything is thrown away on exit, including on failure.
tmp=$(mktemp -d) || { echo "cannot create a temp dir"; exit 1; }
trap 'rm -rf "$tmp"' EXIT INT TERM
mkdir -p "$tmp/loop"
log="$tmp/loop/AUDIT.log"

if command -v jq >/dev/null 2>&1; then
    payload() {
        jq -nc --arg cwd "$tmp" --arg a "$1" --arg m "$2" \
            '{cwd:$cwd, agent_type:$a, agent_id:"0123abcd4567", last_assistant_message:$m}'
    }
elif command -v python3 >/dev/null 2>&1; then
    payload() {
        python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[1],"agent_type":sys.argv[2],"agent_id":"0123abcd4567","last_assistant_message":sys.argv[3]}))' \
            "$tmp" "$1" "$2"
    }
else
    echo "need jq or python3 to build the hook payload"; exit 1
fi

ps_exe=''
if [ "$1" != '--sh-only' ]; then
    for c in pwsh powershell; do command -v "$c" >/dev/null 2>&1 && { ps_exe=$c; break; }; done
fi

# Read the one line the hook just appended and print `task/verdict`, or
# `NOLINE/NOLINE` when it wrote nothing at all - which is a distinct failure
# from writing the wrong thing and must not be reported as a `-` verdict.
columns() {
    [ -s "$log" ] || { printf 'NOLINE/NOLINE'; return; }
    awk -F' *\\| *' 'END { printf "%s/%s", $3, $4 }' "$log"
}

# Strip CR so the list works whether or not it was checked out with CRLF.
tr -d '\r' < "$cases" | while IFS='|' read -r agent want_task want_verdict msg; do
    case "$agent" in ''|\#*) continue ;; esac
    [ -n "$msg" ] || continue

    # `-` in the agent field means: send no agent_type, and pass the name as the
    # argument instead, which is the hook's documented fallback path.
    arg=''
    if [ "$agent" = '-' ]; then agent_field=''; arg='test-runner'; want_agent='test-runner'
    else agent_field=$agent; want_agent=$agent
    fi

    # printf %b expands the \n the case file uses, which is what exercises the
    # hook's newline flattening.
    body=$(printf '%b' "$msg")
    p=$(payload "$agent_field" "$body")
    want="$want_task/$want_verdict"

    rm -f "$log"
    printf '%s' "$p" | sh "$sh_hook" "$arg" >/dev/null 2>&1
    sh_got=$(columns)

    ps_got='-'
    if [ -n "$ps_exe" ] && [ -f "$ps_hook" ]; then
        rm -f "$log"
        printf '%s' "$p" | "$ps_exe" -NoProfile -File "$ps_hook" "$arg" >/dev/null 2>&1
        ps_got=$(columns)
    fi

    mark='  '
    if [ "$sh_got" != "$want" ] || { [ "$ps_got" != '-' ] && [ "$ps_got" != "$want" ]; }; then
        mark='FAIL'
    fi
    if [ "$ps_got" != '-' ] && [ "$sh_got" != "$ps_got" ]; then
        mark='DIVERGE'
    fi

    printf '%-8s sh=%-22s ps1=%-22s want=%-22s %s\n' \
        "$mark" "$sh_got" "$ps_got" "$want" "$want_agent: $msg"
done > "$here/.audit-results" 2>&1

cat "$here/.audit-results"
total=$(grep -c . "$here/.audit-results")
fail=$(grep -c '^FAIL' "$here/.audit-results")
diverge=$(grep -c '^DIVERGE' "$here/.audit-results")
rm -f "$here/.audit-results"

echo
if [ -z "$ps_exe" ]; then
    if [ "$1" = '--sh-only' ]; then
        echo "NOTE: --sh-only, so the .ps1 twin was NOT run."
    else
        echo "NOTE: no pwsh/powershell on PATH - the .ps1 twin was NOT run."
    fi
    echo "      The twins have diverged before; this run cannot rule that out."
fi
echo "cases: $total   wrong column: $fail   twins disagree: $diverge"
[ "$fail" -eq 0 ] && [ "$diverge" -eq 0 ] || exit 1
echo "OK"
