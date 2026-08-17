#!/usr/bin/env sh
# Loop audit hook — SubagentStop (POSIX). Counterpart of audit-subagent.ps1;
# see that file's header for what this log is for and why it is structural only.
#
# Takes the calling agent's name as $1, used only if the payload omits
# agent_type.
#
# Every path exits 0. Exit code 2 on SubagentStop *prevents the subagent from
# stopping*, so a crash here would hang the loop rather than lose a log line.
#
# Needs jq or python3 to read the hook payload. If neither is present it exits
# silently — the loop still works, it just has no audit trail.

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

flat=$(json_get last_assistant_message | tr '\n\r\t' '   ' | tr -s ' ')

task=$(printf '%s' "$flat" | grep -oE 'T-[0-9]{3}' | head -1)
[ -n "$task" ] || task='-'

# Verdict token. `case` is case-sensitive: these agents emit uppercase verdicts
# by convention, and matching loosely would fire on prose.
signal='-'
for pat in 'NO TESTS EXECUTED' 'CHANGES REQUESTED' 'APPROVED' 'BLOCKED' 'FAILED'; do
    case "$flat" in
        *"$pat"*) signal="$pat"; break ;;
    esac
done

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s | %s | %s | %s | %s\n' "$stamp" "$agent" "$task" "$signal" "$id" \
    >> "$root/loop/AUDIT.log" 2>/dev/null

exit 0
