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

# The builder is chosen by PROBING it, never by `command -v` alone. On Windows
# `command -v python3` succeeds against the Microsoft Store App Execution Alias,
# which prints "Python was not found", exits 49, and writes NOTHING to stdout -
# so detection by presence selects a builder that silently emits empty payloads
# and every case reports a wrong column against a hook that is working. Measured
# on Windows 11 + Git Bash, jq absent, against the sibling guard suite: 24 FAILs
# and a case count of 78 for 39 cases. A harness that cannot build a payload
# must refuse to report cases.
#
# cwd is a parameter rather than baked in, because the two twins need it spelled
# differently: under WSL2 the .ps1 runs as a Windows binary and cannot resolve a
# Linux path.
payload_jq() {
    jq -nc --arg cwd "$1" --arg a "$2" --arg m "$3" \
        '{cwd:$cwd, agent_type:$a, agent_id:"0123abcd4567", last_assistant_message:$m}'
}
payload_py() {
    python3 -c 'import json,sys;print(json.dumps({"cwd":sys.argv[1],"agent_type":sys.argv[2],"agent_id":"0123abcd4567","last_assistant_message":sys.argv[3]}))' \
        "$1" "$2" "$3"
}

# perl ships with Git for Windows, already this template's Windows prerequisite,
# so a Git Bash box builds payloads with nothing to install.
payload_pl() {
    perl -MJSON::PP -e 'print JSON::PP->new->encode({cwd=>$ARGV[0],agent_type=>$ARGV[1],agent_id=>"0123abcd4567",last_assistant_message=>$ARGV[2]})' \
        "$1" "$2" "$3"
}

# Order-independent, because a builder may emit keys in any order: JSON::PP uses
# Perl hashes, which are unordered, so a probe that expects one key *before*
# another fails against a builder that is working correctly.
probe_ok() {
    case $1 in *"$2"*) ;; *) return 1 ;; esac
    case $1 in *"$3"*) ;; *) return 1 ;; esac
    return 0
}

probe_msg='quoted "42" and a \\ backslash'
builder=''
if command -v jq >/dev/null 2>&1; then
    probe_ok "$(payload_jq "$tmp" probe "$probe_msg" 2>/dev/null)" '"agent_type"' '42' && builder=jq
fi
if [ -z "$builder" ] && command -v python3 >/dev/null 2>&1; then
    probe_ok "$(payload_py "$tmp" probe "$probe_msg" 2>/dev/null)" '"agent_type"' '42' && builder=py
fi
if [ -z "$builder" ] && command -v perl >/dev/null 2>&1; then
    probe_ok "$(payload_pl "$tmp" probe "$probe_msg" 2>/dev/null)" '"agent_type"' '42' && builder=pl
fi
if [ -z "$builder" ]; then
    echo "FATAL: no working JSON builder, so no case can be run."
    echo "  jq, python3 and perl were all absent or unusable. On Windows,"
    echo "  \`python3\` is often the Microsoft Store alias: it resolves, prints a"
    echo "  message, and produces nothing. Install jq and re-run."
    exit 1
fi
payload() { case $builder in jq) payload_jq "$1" "$2" "$3" ;; py) payload_py "$1" "$2" "$3" ;; pl) payload_pl "$1" "$2" "$3" ;; esac; }

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

# Both the hook path and the fixture directory have to be spelled for whichever
# interpreter was found. Under WSL2 that means UNC; everywhere else the paths are
# already native to the shell that found it.
ps_path="$ps_hook"
ps_cwd="$tmp"
if [ -n "$ps_exe" ]; then
    if command -v wslpath >/dev/null 2>&1; then       # WSL2
        ps_path=$(wslpath -w "$ps_hook"); ps_cwd=$(wslpath -w "$tmp")
    elif command -v cygpath >/dev/null 2>&1; then     # Git Bash / MSYS
        ps_path=$(cygpath -w "$ps_hook"); ps_cwd=$(cygpath -w "$tmp")
    fi
fi

# ps_cwd matters more than ps_path: Git Bash mangles a path passed as an
# *argument* to a native binary, but never one embedded inside a JSON string,
# and cwd travels in the payload.

# -ExecutionPolicy Bypass is per-invocation and changes no machine setting. It is
# required, not cosmetic: the default policy on client Windows is Restricted, and
# a blocked script writes no line at all - which this runner would otherwise
# report as NOLINE for every case rather than as a broken interpreter.
run_ps() { "$ps_exe" -NoProfile -ExecutionPolicy Bypass -File "$ps_path" "$1" 2>/dev/null; }

# Read the one line the hook just appended and print `task/verdict`, or
# `NOLINE/NOLINE` when it wrote nothing at all - which is a distinct failure
# from writing the wrong thing and must not be reported as a `-` verdict.
columns() {
    [ -s "$log" ] || { printf 'NOLINE/NOLINE'; return; }
    awk -F' *\\| *' 'END { printf "%s/%s", $3, $4 }' "$log"
}

# Probe the interpreter too, for exactly the reason the builder is probed: a
# .ps1 that cannot run writes no line, and this runner would report NOLINE for
# every case rather than saying the interpreter is broken. One known case
# settles it before any result is printed.
if [ -n "$ps_exe" ] && [ -f "$ps_hook" ]; then
    rm -f "$log"
    printf '%s' "$(payload "$ps_cwd" test-runner 'TASK: T-001
VERDICT: TESTS PASSED')" | run_ps test-runner >/dev/null 2>&1
    if [ "$(columns)" != 'T-001/TESTS PASSED' ]; then
        ps_skip="$ps_exe could not run the .ps1 twin: a known case came back as
      '$(columns)', which is what a script that never ran looks like. Check the
      execution policy, and that $ps_cwd resolves for it."
        ps_exe=''
    fi
    rm -f "$log"
fi

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
    p=$(payload "$tmp" "$agent_field" "$body")
    want="$want_task/$want_verdict"

    rm -f "$log"
    printf '%s' "$p" | sh "$sh_hook" "$arg" >/dev/null 2>&1
    sh_got=$(columns)

    ps_got='-'
    if [ -n "$ps_exe" ] && [ -f "$ps_hook" ]; then
        rm -f "$log"
        printf '%s' "$(payload "$ps_cwd" "$agent_field" "$body")" | run_ps "$arg" >/dev/null 2>&1
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
# Count result lines, not every line: anything a tool leaked into the file would
# otherwise inflate the total. The Store-alias bug reported 78 cases for 39 in
# the sibling suite.
total=$(grep -c ' ps1=' "$here/.audit-results")
fail=$(grep -c '^FAIL' "$here/.audit-results")
diverge=$(grep -c '^DIVERGE' "$here/.audit-results")
rm -f "$here/.audit-results"

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
echo "cases: $total   wrong column: $fail   twins disagree: $diverge"
[ "$fail" -eq 0 ] && [ "$diverge" -eq 0 ] || exit 1
echo "OK"
