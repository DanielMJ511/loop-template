#!/usr/bin/env sh
# Runs .claude/hooks/guard-git-destructive.{sh,ps1} over tests/guard-git-destructive.cases.
#
# Usage:  sh tests/run-guard-tests.sh            both twins (~80s)
#         sh tests/run-guard-tests.sh --sh-only  the POSIX twin alone (~5s)
# Exit:   0 all cases match and both twins agree; 1 otherwise.
#
# The full run spawns PowerShell once per case and takes over a minute on
# Windows. That is slow enough to look hung, and long enough to trip a two
# minute command timeout mid-script - which is exactly how the pre-fix hooks
# once got left sitting in a working tree. Use --sh-only while iterating, but
# the cross-twin diff is the check that matters, so run it in full before
# committing a change to either hook.
#
# This is the only executable check in the template. Everything else here is
# prose instructions for agents, which always read as correct - the defects that
# mattered in this repo's history all passed a read-through and failed a run.
# The guard is the one piece that is code, and it is blocking, so it is the one
# piece where being wrong costs the user their working tree.
#
# It checks TWO things, and the second is the one that caught the real bug:
#   1. each twin's verdict against the expectation
#   2. the two twins against EACH OTHER
# They diverged once already, in opposite directions on the same two commands -
# `sed` is greedy, .NET's Match is leftmost - so each platform had a spelling
# that walked a real `git stash` past the guard. No single-twin run can see that.
#
# The .ps1 twin is skipped when no PowerShell is on PATH, and the run says so
# rather than reporting a pass it did not perform.
#
# Needs python3 or jq to build the hook payload, the same two-parser fallback
# the hooks themselves carry.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
cases="$here/guard-git-destructive.cases"
sh_hook="$root/.claude/hooks/guard-git-destructive.sh"
ps_hook="$root/.claude/hooks/guard-git-destructive.ps1"

[ -f "$cases" ]   || { echo "missing $cases";   exit 1; }
[ -f "$sh_hook" ] || { echo "missing $sh_hook"; exit 1; }

# One JSON payload builder, chosen once rather than per case.
if command -v jq >/dev/null 2>&1; then
    payload() { printf '%s' "$1" | jq -Rsc '{tool_input:{command:.}}'; }
elif command -v python3 >/dev/null 2>&1; then
    payload() { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1"; }
else
    echo "need jq or python3 to build the hook payload"; exit 1
fi

verdict_of() { printf '%s' "$1" | grep -q '"deny"' && echo BLOCK || echo allow; }

ps_exe=''
if [ "$1" != '--sh-only' ]; then
    for c in pwsh powershell; do command -v "$c" >/dev/null 2>&1 && { ps_exe=$c; break; }; done
fi

fail=0; total=0; diverge=0

# Strip CR so the list works whether or not it was checked out with CRLF.
tr -d '\r' < "$cases" | while IFS='|' read -r want cmd; do
    case "$want" in ''|\#*) continue ;; esac
    [ -n "$cmd" ] || continue
    total=$((total + 1))
    p=$(payload "$cmd")

    sh_v=$(verdict_of "$(printf '%s' "$p" | sh "$sh_hook")")

    ps_v='-'
    if [ -n "$ps_exe" ] && [ -f "$ps_hook" ]; then
        ps_v=$(verdict_of "$(printf '%s' "$p" | "$ps_exe" -NoProfile -File "$ps_hook" 2>/dev/null)")
    fi

    mark='  '
    if [ "$sh_v" != "$want" ] || { [ "$ps_v" != '-' ] && [ "$ps_v" != "$want" ]; }; then
        mark='FAIL'; fail=$((fail + 1))
    fi
    if [ "$ps_v" != '-' ] && [ "$sh_v" != "$ps_v" ]; then
        mark='DIVERGE'; diverge=$((diverge + 1))
    fi

    printf '%-8s sh=%-6s ps1=%-6s want=%-6s %s\n' "$mark" "$sh_v" "$ps_v" "$want" "$cmd"
done > "$here/.results" 2>&1

cat "$here/.results"
total=$(grep -c . "$here/.results")
fail=$(grep -c '^FAIL' "$here/.results")
diverge=$(grep -c '^DIVERGE' "$here/.results")
rm -f "$here/.results"

echo
if [ -z "$ps_exe" ]; then
    if [ "$1" = '--sh-only' ]; then
        echo "NOTE: --sh-only, so the .ps1 twin was NOT run."
    else
        echo "NOTE: no pwsh/powershell on PATH - the .ps1 twin was NOT run."
    fi
    echo "      The twins have diverged before; this run cannot rule that out."
fi
echo "cases: $total   wrong verdict: $fail   twins disagree: $diverge"
[ "$fail" -eq 0 ] && [ "$diverge" -eq 0 ] || exit 1
echo "OK"
