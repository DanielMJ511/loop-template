#!/bin/sh
# SubagentStop hook — appends one line per agent completion to loop/AUDIT.md.
#
# This is the loop's only record of a spawn that no agent wrote down. STATE.md
# is agents reporting on themselves, and docs-writer only runs on tasks that
# succeeded — so a task that died mid-escalation leaves no trace of having been
# attempted at all. This fires either way.

DIR="${CLAUDE_PROJECT_DIR:-.}"
[ -d "$DIR/loop" ] || exit 0

AUDIT="$DIR/loop/AUDIT.md"
[ -f "$AUDIT" ] || printf '# AUDIT — agent spawn log\n\nWritten by the SubagentStop hook. One line per agent completion, appended, never edited.\n\n' > "$AUDIT"

# Hook input arrives as JSON on stdin. Pull the agent name out without
# assuming a JSON parser is installed — sed is available wherever sh is.
AGENT=$(sed -n 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$AGENT" ] || AGENT="unknown"

TASK=$(grep -m1 'attempt=' "$DIR/loop/PLAN.md" 2>/dev/null | sed -n 's/^- \[.\] \(T-[0-9]*\).*/\1/p')
[ -n "$TASK" ] || TASK="-"

printf '%s  %-18s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT" "$TASK" >> "$AUDIT"
exit 0
