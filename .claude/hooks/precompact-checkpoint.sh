#!/usr/bin/env sh
# PreCompact checkpoint (POSIX). Counterpart of precompact-checkpoint.ps1.
#
# Declared in .claude/skills/orchestrate/SKILL.md frontmatter. Fires immediately
# before the orchestrator's context is compacted - the one moment no agent can
# anticipate from inside its own turn, and the moment it loses the working detail
# it has not yet flushed.
#
# It never reads the transcript. Everything a resume needs is already durable:
#
#   in-flight task  <- first unchecked `- [ ] T-00X` in loop/PLAN.md
#   attempt counter <- that packet's own `Status:` line, verbatim
#   stage           <- last agent to finish for that task in loop/AUDIT.log
#   tree state      <- git status --short
#
# So this writes the same loop/HANDOFF.md shape /loop-handoff writes, including
# `Status: active`, and /orchestrate step 1 resumes from it by exactly the same path.
# No second resume mechanism.
#
# Always exits 0. Exit code 2 on PreCompact *blocks compaction*, which would hang
# a session rather than lose a checkpoint.

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

plan="$root/loop/PLAN.md"
[ -f "$plan" ] || exit 0

# The in-flight task: first unchecked task line whose packet is not blocked.
# /orchestrate skips blocked tasks, so a checkpoint pointing at one would resume
# onto the task a human was asked to look at.
task=''
for t in $(sed -n 's/^- \[ \] \(T-[0-9]\{3\}\).*/\1/p' "$plan" 2>/dev/null); do
    if ! grep -q '^Status: blocked' "$root/loop/tasks/$t.md" 2>/dev/null; then
        task=$t
        break
    fi
done
[ -n "$task" ] || exit 0

packet="$root/loop/tasks/$task.md"
status=$(sed -n 's/^Status: *//p' "$packet" 2>/dev/null | head -1)
[ -n "$status" ] || status='unknown - no Status line in the packet'

title=$(sed -n 's/^# *\(T-[0-9]\{3\}.*\)/\1/p' "$packet" 2>/dev/null | head -1)
[ -n "$title" ] || title="$task"

# Stage: the last agent that finished for this task. This is what the transcript
# would have told us, and the audit log is the more reliable of the two for a
# session that is about to lose its context.
stage=$(awk -F' *\\| *' -v t="$task" '$3 == t { s = $2 } END { print s }' \
    "$root/loop/AUDIT.log" 2>/dev/null)
if [ -n "$stage" ]; then
    stage="after $stage (last spawn recorded in loop/AUDIT.log)"
else
    stage='unknown - no AUDIT.log entry for this task'
fi

# Keep the two verdicts apart by the agent that emitted them. A test-runner
# verdict recorded under "Last verification result" would tell a resuming session
# that step 4b ran when it never did - and 4b is the stage that catches what the
# suite structurally cannot see.
testv=$(awk -F' *\\| *' -v t="$task" '$3 == t && $2 == "test-runner" && $4 != "-" { v = $4 } END { print v }' \
    "$root/loop/AUDIT.log" 2>/dev/null)
[ -n "$testv" ] || testv='n/a - no test-runner verdict recorded for this task'

verdict=$(awk -F' *\\| *' -v t="$task" '$3 == t && $2 == "verifier" && $4 != "-" { v = $4 } END { print v }' \
    "$root/loop/AUDIT.log" 2>/dev/null)
[ -n "$verdict" ] || verdict='n/a - stage not reached, or not applicable to this project'

dirty=$(cd "$root" && git status --short 2>/dev/null)
[ -n "$dirty" ] || dirty='none'

stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

cat > "$root/loop/HANDOFF.md" <<EOF
# HANDOFF - session checkpoint
Written: $stamp
Written by: PreCompact hook (derived from durable state, not from the transcript)
Status: active

## Unit
See loop/PLAN.md - this checkpoint was written automatically at compaction.

## Current task
$title

## Stage
$stage

## Failure counter
$status

## Last test result
$testv

## Last verification result
$verdict

## Uncommitted changes
$dirty

## Tree state
Not assessed - a hook cannot judge whether a change is half-applied. Run git diff before trusting it.

## Next action
Resume $task at the stage above. Re-read the packet's Status line first: it is the record that survived.
EOF

exit 0
