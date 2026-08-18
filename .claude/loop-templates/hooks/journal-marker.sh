#!/bin/sh
# PreCompact hook — writes loop/HANDOFF.md before the orchestrator's context
# is compacted.
#
# The durable task state on the PLAN.md line covers the case where the
# orchestrator got far enough to write it. This covers the case where it did
# not: compaction is precisely the moment the working details it has not yet
# flushed are lost. It is also the one moment no agent can anticipate from
# inside its own turn, which is why it is a hook and not an instruction.
#
# Everything here is derived from files, never from session context — the hook
# has no access to that, and after #4 it does not need it.

DIR="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$DIR/loop/PLAN.md"
[ -f "$PLAN" ] || exit 0

# The in-flight task is the first unchecked line; prefer one showing attempts.
LINE=$(grep -m1 'attempt=' "$PLAN")
[ -n "$LINE" ] || LINE=$(grep -m1 '^- \[ \]' "$PLAN")
[ -n "$LINE" ] || exit 0        # nothing in flight; nothing worth checkpointing

TASK=$(printf '%s' "$LINE" | sed -n 's/^- \[.\] \(T-[0-9]*\).*/\1/p')
TITLE=$(printf '%s' "$LINE" | sed -n 's/^- \[.\] T-[0-9]* — \([^(]*\).*/\1/p')
ATTEMPT=$(printf '%s' "$LINE" | sed -n 's/.*attempt=\([0-9]*\/[0-9]*\).*/\1/p')
[ -n "$ATTEMPT" ] || ATTEMPT="0 — no respins"
LAST=$(printf '%s' "$LINE" | sed -n 's/.*last=\([^ ]*\).*/\1/p')
[ -n "$LAST" ] || LAST="none recorded"

# Never clobber a checkpoint a human or /loop-handoff wrote and the loop has
# not consumed yet — theirs describes a stage this hook cannot know.
HANDOFF="$DIR/loop/HANDOFF.md"
if [ -f "$HANDOFF" ] && grep -q '^Status: active' "$HANDOFF"; then exit 0; fi

{
  printf '# HANDOFF — session checkpoint\n'
  printf 'Written: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Status: active\n\n'
  printf '## Unit\nSee loop/PLAN.md\n\n'
  printf '## Current task\n%s — %s\n\n' "$TASK" "$TITLE"
  printf '## Stage\nunknown — written by the PreCompact hook, which cannot see the in-flight stage.\nRe-derive it from the tree before acting.\n\n'
  printf '## Failure counter\n%s\n\n' "$ATTEMPT"
  printf '## Last test result\n%s\n\n' "$LAST"
  printf '## Uncommitted changes\n%s\n\n' "$(cd "$DIR" && git status --short 2>/dev/null | head -40)"
  printf '## Tree state\nNot assessed — the hook does not read diffs. Check before trusting it.\n\n'
  printf '## Next action\nResume %s. Confirm the stage from the tree first.\n' "$TASK"
} > "$HANDOFF"

exit 0
