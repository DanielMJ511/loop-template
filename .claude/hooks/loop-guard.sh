#!/usr/bin/env sh
# Loop guard - Stop hook (POSIX). Counterpart of loop-guard.ps1.
#
# Declared in .claude/skills/orchestrate/SKILL.md frontmatter, so it registers
# when /orchestrate is invoked and stays registered for the rest of the session.
# No settings.json is involved.
#
# ADVISORY, NEVER BLOCKING. It always exits 0. Exit code 2 on Stop *prevents
# Claude from stopping*, which in a foreground session you are sitting in front
# of is a foot-gun, not a guardrail. To surface a warning without blocking it
# prints `{"systemMessage": "..."}` on stdout - the one documented route to the
# user from a non-blocking hook. Plain stdout and stderr go to the debug log
# only on exit 0, so a hook that "warns" by echoing is a hook nobody reads.
#
# It reads only durable state - loop/PROFILE.md, the task packets, loop/AUDIT.log
# - never the transcript. Everything it reports survives a session that died.
#
# Silent when nothing is over budget: no output, no message, no noise. That is
# what makes it safe to leave registered for a whole session.

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

root=$(json_get cwd)
[ -n "$root" ] || exit 0
[ -d "$root/loop" ] || exit 0

profile="$root/loop/PROFILE.md"
audit="$root/loop/AUDIT.log"

# Budget from the profile, with a default if the field is absent or unparseable.
# A missing budget must not silence the guard - an unconfigured ceiling is the
# case where a runaway is most likely, not least.
max_spawns=$(sed -n 's/.*[Mm]ax spawns per task[^0-9]*\([0-9][0-9]*\).*/\1/p' "$profile" 2>/dev/null | head -1)
case "$max_spawns" in ''|*[!0-9]*) max_spawns=10 ;; esac

warnings=''
add() { warnings="${warnings}${warnings:+ }$1" ;}

# 1. Tasks that burned more spawns than the budget allows. AUDIT.log is the only
#    record of spawns that actually happened, including those from a dead run.
if [ -f "$audit" ]; then
    over=$(awk -F' *\\| *' -v m="$max_spawns" '
        $3 ~ /^T-[0-9]+$/ { c[$3]++ }
        END { for (t in c) if (c[t] > m) printf "%s used %d spawns; ", t, c[t] }
    ' "$audit" 2>/dev/null)
    [ -n "$over" ] && add "Over the ${max_spawns}-spawn budget: ${over%; }."
fi

# 2. Tasks the escalation ladder gave up on. /orchestrate skips these on the next
#    run by design, so without a nudge they sit unchecked and unnoticed.
blocked=$(grep -l '^Status: blocked' "$root"/loop/tasks/T-*.md 2>/dev/null \
    | sed 's|.*/||;s|\.md$||' | tr '\n' ' ')
[ -n "$blocked" ] && add "Blocked, awaiting a human: ${blocked% }."

# 3. Tasks sitting at the last rung. Not yet blocked, but one failure away, and
#    the next run resumes there rather than starting fresh.
atmax=$(grep -lE '^Status:.*attempt 3 of 3' "$root"/loop/tasks/T-*.md 2>/dev/null \
    | sed 's|.*/||;s|\.md$||' | tr '\n' ' ')
[ -n "$atmax" ] && add "At the final attempt: ${atmax% }."

[ -n "$warnings" ] || exit 0

# systemMessage is shown to the user without blocking. Keep it one line.
esc=$(printf '%s' "Loop guard: $warnings" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"systemMessage": "%s"}\n' "$esc"
exit 0
