#!/bin/sh
# Stop hook — surfaces runaway loop state at the end of every turn.
#
# It reports; it never blocks. A Stop hook that can refuse to stop is a trap:
# the one time it is wrong, the session cannot be ended without editing config.
# Enforcement belongs to /orchestrate, which can act on what it finds. This is
# the deterministic half — it runs whether or not an agent remembered to look.

DIR="${CLAUDE_PROJECT_DIR:-.}"
PLAN="$DIR/loop/PLAN.md"
[ -f "$PLAN" ] || exit 0

# Match T-00X only. The ## Verification list uses the same checkbox syntax in
# the same file, and counting those as tasks reports a loop that does not exist.
done_n=$(grep -c '^- \[x\] T-' "$PLAN")
todo_n=$(grep -c '^- \[ \] T-' "$PLAN")
blocked_n=$(grep -c '^- \[!\] T-' "$PLAN")
ceiling_n=$(grep -c 'attempt=2/2' "$PLAN")

# Silent on a healthy loop. Noise on every turn trains people to ignore it.
[ "$blocked_n" -eq 0 ] && [ "$ceiling_n" -eq 0 ] && exit 0

echo "loop guard: ${done_n} done, ${todo_n} remaining, ${blocked_n} blocked, ${ceiling_n} at the escalation ceiling."

if [ "$blocked_n" -gt 0 ]; then
  echo "blocked — these need a human before /orchestrate runs again:"
  grep '^- \[!\] T-' "$PLAN"
fi

if [ "$ceiling_n" -gt 0 ]; then
  echo "at ceiling — one more failure escalates or blocks:"
  grep 'attempt=2/2' "$PLAN"
fi

exit 0
