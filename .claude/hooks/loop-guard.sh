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
#
#    Scoped to the current unit. The log is append-only across units while task
#    ids restart at T-001 in each one, so counting the whole file adds an earlier
#    unit's T-002 to this one's. Measured in a real project: T-002 read 12 (7+5)
#    and T-003 read 11 (7+4) against a ceiling of 10, while nothing in the live
#    unit exceeded 5 - two false alarms on every stop, for the rest of that unit
#    and every unit after. A guard that cries wolf is one nobody reads.
#
#    The boundary is the commit time of loop/PLAN.md's `Unit base:`, which
#    /orchestrate records on the unit's first run. Nothing new writes to
#    AUDIT.log for this - the file's single-writer rule is why it can be trusted.
#    If the boundary cannot be resolved - no plan, no base recorded yet, no git -
#    fall back to counting the whole file. Over-warning is the safe failure here;
#    silently skipping the check is not.
if [ -f "$audit" ]; then
    since=''
    base=$(sed -n 's/.*[Uu]nit base:[^0-9a-f]*\([0-9a-f]\{7,40\}\).*/\1/p' \
        "$root/loop/PLAN.md" 2>/dev/null | head -1)
    [ -n "$base" ] && since=$(TZ=UTC0 git -C "$root" log -1 \
        --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ "$base" 2>/dev/null)

    over=$(awk -F' *\\| *' -v m="$max_spawns" -v since="$since" '
        # Every line opens with a 20-character UTC stamp, so this comparison does
        # not depend on how the field separator splits the rest of the line.
        since != "" && substr($0, 1, 20) < since { next }
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
