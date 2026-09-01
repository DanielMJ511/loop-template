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
# The .ps1 twin is skipped when no PowerShell is on PATH *or* when the one found
# cannot actually run it, and the run says which rather than reporting a pass it
# did not perform. Under WSL2 the twin is reached through Windows interop
# (`powershell.exe` plus a `wslpath -w` path), so the cross-twin check runs on a
# Linux box with no PowerShell of its own.
#
# Needs jq or python3 to build the hook payload - and PROBES the one it picks
# rather than trusting `command -v`, because on Windows `python3` resolves to a
# Microsoft Store alias that produces nothing. See the builder block below.

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(dirname -- "$here")
cases="$here/guard-git-destructive.cases"
sh_hook="$root/.claude/hooks/guard-git-destructive.sh"
ps_hook="$root/.claude/hooks/guard-git-destructive.ps1"

[ -f "$cases" ]   || { echo "missing $cases";   exit 1; }
[ -f "$sh_hook" ] || { echo "missing $sh_hook"; exit 1; }

# One JSON payload builder, chosen once rather than per case - and chosen by
# PROBING it, never by `command -v` alone.
#
# On Windows `command -v python3` succeeds against the Microsoft Store App
# Execution Alias, which prints "Python was not found", exits 49, and writes
# NOTHING to stdout. Detection by presence therefore selected a builder that
# silently produced empty payloads: every hook saw no command, both twins
# answered `allow`, and 24 BLOCK cases reported as FAIL against a guard that was
# working perfectly. Measured on Windows 11 + Git Bash, jq absent.
#
# A harness that cannot build a payload must refuse to report cases at all. A
# wrong verdict that looks like a hook defect is worse than no run.
payload_jq() { printf '%s' "$1" | jq -Rsc '{tool_input:{command:.}}'; }
payload_py() { python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1"; }
# perl ships with Git for Windows, already this template's Windows prerequisite,
# so a Git Bash box builds payloads with nothing to install.
payload_pl() { perl -MJSON::PP -e 'print JSON::PP->new->encode({tool_input=>{command=>$ARGV[0]}})' "$1"; }

# The probe carries a quote and a backslash, so a builder that mangles escaping
# fails here rather than at some case in the middle of the list.
# Order-independent, because a builder may emit keys in any order: JSON::PP uses
# Perl hashes, which are unordered, so a probe that expects one key *before*
# another fails against a builder that is working correctly.
probe_ok() {
    case $1 in *"$2"*) ;; *) return 1 ;; esac
    case $1 in *"$3"*) ;; *) return 1 ;; esac
    return 0
}

probe_payload='loop probe "42" \x'
builder=''
if command -v jq >/dev/null 2>&1; then
    probe_ok "$(payload_jq "$probe_payload" 2>/dev/null)" '"tool_input"' '42' && builder=jq
fi
if [ -z "$builder" ] && command -v python3 >/dev/null 2>&1; then
    probe_ok "$(payload_py "$probe_payload" 2>/dev/null)" '"tool_input"' '42' && builder=py
fi
if [ -z "$builder" ] && command -v perl >/dev/null 2>&1; then
    probe_ok "$(payload_pl "$probe_payload" 2>/dev/null)" '"tool_input"' '42' && builder=pl
fi
if [ -z "$builder" ]; then
    echo "FATAL: no working JSON builder, so no case can be run."
    echo "  jq, python3 and perl were all absent or unusable. On Windows,"
    echo "  \`python3\` is often the Microsoft Store alias: it resolves, prints a"
    echo "  message, and produces nothing. Install jq and re-run."
    exit 1
fi
payload() { case $builder in jq) payload_jq "$1" ;; py) payload_py "$1" ;; pl) payload_pl "$1" ;; esac; }

verdict_of() { printf '%s' "$1" | grep -q '"deny"' && echo BLOCK || echo allow; }

# `powershell.exe` is tried last and is the WSL2 interop path: a Linux box with
# Windows interop has no `pwsh` or `powershell`, but reaches the Windows binary
# under /mnt/c. Order matters - inside Git Bash on Windows, `powershell` already
# resolves, and that is the native case.
ps_exe=''
ps_skip=''
if [ "$1" != '--sh-only' ]; then
    for c in pwsh powershell powershell.exe; do
        command -v "$c" >/dev/null 2>&1 && { ps_exe=$c; break; }
    done
fi

# Under WSL2 the interpreter is a Windows binary and cannot resolve a Linux
# path, so hand it a UNC one. Everywhere else the path is already native to
# whichever shell found the interpreter.
ps_path="$ps_hook"
if [ -n "$ps_exe" ]; then
    if command -v wslpath >/dev/null 2>&1; then       # WSL2
        ps_path=$(wslpath -w "$ps_hook")
    elif command -v cygpath >/dev/null 2>&1; then     # Git Bash / MSYS
        ps_path=$(cygpath -w "$ps_hook")
    fi
fi

# -ExecutionPolicy Bypass is per-invocation and changes no machine setting. It
# is required, not cosmetic: the default policy on client Windows is Restricted,
# a blocked script writes nothing to stdout, and `verdict_of` maps nothing to
# `allow` - so without it every case reports as allowed.
run_ps() { "$ps_exe" -NoProfile -ExecutionPolicy Bypass -File "$ps_path" 2>/dev/null; }

# Probe the interpreter too, for exactly the reason the builder is probed: a
# .ps1 that cannot run is indistinguishable from one that allowed everything.
# One known-BLOCK case settles it before any result is printed.
if [ -n "$ps_exe" ] && [ -f "$ps_hook" ]; then
    if [ "$(verdict_of "$(printf '%s' "$(payload 'git stash')" | run_ps)")" != BLOCK ]; then
        ps_skip="$ps_exe could not run the .ps1 twin: it answered a known-BLOCK
      case with 'allow', which is exactly what a script that never ran looks
      like. Check the execution policy, and that the path resolves."
        ps_exe=''
    fi
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
        ps_v=$(verdict_of "$(printf '%s' "$p" | run_ps)")
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
# Count result lines, not every line: anything a tool leaked into the file would
# otherwise inflate the total. The Store-alias bug reported 78 cases for 39.
total=$(grep -c ' ps1=' "$here/.results")
fail=$(grep -c '^FAIL' "$here/.results")
diverge=$(grep -c '^DIVERGE' "$here/.results")
rm -f "$here/.results"

echo
if [ -z "$ps_exe" ]; then
    if [ "$1" = '--sh-only' ]; then
        echo "NOTE: --sh-only, so the .ps1 twin was NOT run."
    elif [ -n "$ps_skip" ]; then
        echo "NOTE: $ps_skip"
    else
        echo "NOTE: no PowerShell on PATH - the .ps1 twin was NOT run."
    fi
    echo "      The twins have diverged before; this run cannot rule that out."
fi
echo "cases: $total   wrong verdict: $fail   twins disagree: $diverge"
[ "$fail" -eq 0 ] && [ "$diverge" -eq 0 ] || exit 1
echo "OK"
