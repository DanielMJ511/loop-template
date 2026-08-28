#!/usr/bin/env sh
# Destructive-git guard - PreToolUse on Bash (POSIX). Counterpart of
# guard-git-destructive.ps1; the two must agree on the same command string.
#
# Declared in .claude/skills/orchestrate/SKILL.md and in every Bash-capable
# agent's frontmatter, so it covers the orchestrator's own calls and each
# subagent's. Subagent hooks fire only while that subagent runs.
#
# BLOCKING, unlike the loop's other two hooks. It refuses three commands that
# have destroyed uncommitted work in real runs, and it refuses them rather than
# asking, because the alternative - telling agents not to - was tried and failed:
# the constraint was stated, banked in LESSONS.md, sharpened after a second
# incident, and delivered verbatim in a spawn prompt, and an agent ran the
# command anyway. Two incidents, neither caught by any guard; both recovered by
# a human reading the tree afterwards.
#
# Refuses:
#   git stash ...             - sweeps up every uncommitted change in the tree,
#                               including other tasks' work
#   git checkout -- <path>    - reverts to the last COMMIT, discarding your own
#   git checkout .              in-progress edits along with whatever you meant
#                               to undo
#   git restore <path>        - same, modern spelling
#
# Deliberately still allowed:
#   git stash list / show     - read-only, and the loop's own verification
#                               procedure runs `git stash list` to confirm a
#                               tree is intact. Blocking it would break the
#                               check that catches this class of incident.
#   git restore --staged      - unstages without touching working-tree content
#   git checkout <branch>     - switching branches is not the failure mode
#
# Unlike audit-subagent, this does NOT skip when loop/ is absent. A guard that
# disables itself based on what is in the directory is a guard with a bypass;
# registration already scopes it to this project.
#
# Fails OPEN on an unreadable payload (exit 0, no output): a guard that cannot
# read its input must not wedge every Bash call in the session.

raw=$(cat)
[ -n "$raw" ] || exit 0

# .tool_input.command, via whichever parser exists. jq is not installed
# everywhere - audit-subagent.sh carries the same two-parser fallback.
if command -v jq >/dev/null 2>&1; then
    cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // ""' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
    cmd=$(printf '%s' "$raw" | python3 -c \
        'import sys,json;print((json.load(sys.stdin).get("tool_input") or {}).get("command") or "")' 2>/dev/null)
else
    exit 0
fi
[ -n "$cmd" ] || exit 0

# Collapse whitespace so the patterns below need only handle single spaces.
# Matching runs over the whole string rather than per segment, so a command
# hidden behind && or a subshell is still caught.
norm=$(printf '%s' "$cmd" | tr '\n\r\t' '   ' | tr -s ' ')

# `git` followed by any number of leading options (-C <path>, --no-pager, ...)
# and then the subcommand.
git_sub() { printf '%s' "$norm" | grep -qE "(^|[^A-Za-z0-9_-])git( +-{1,2}[^ ]+( +[^ -][^ ]*)?)* +$1( |$)" ; }

reason=''

# 1. git stash - except the two read-only subcommands.
if git_sub stash; then
    sub=$(printf '%s' "$norm" | sed -n 's/.* stash *\([a-z]*\).*/\1/p' | head -1)
    case "$sub" in
        list|show) : ;;
        *) reason="git stash sweeps up every uncommitted change in the tree, including work belonging to other tasks. Two incidents in this project's history lost work to it." ;;
    esac
fi

# 2. git checkout with a pathspec - the `--` form or a bare `.`.
if [ -z "$reason" ] && git_sub checkout; then
    if printf '%s' "$norm" | grep -qE ' checkout( +-{1,2}[^ ]+)* +(--( |$)|\.( |$))'; then
        reason="git checkout -- <path> reverts the file to the last COMMIT, discarding your own in-progress edits along with whatever you meant to undo. It is safe only when the file has no other uncommitted work, which is almost never true mid-task."
    fi
fi

# 3. git restore - except --staged on its own, which leaves content alone.
if [ -z "$reason" ] && git_sub restore; then
    if printf '%s' "$norm" | grep -qE ' restore( +[^ ]+)* +--staged' \
       && ! printf '%s' "$norm" | grep -qE ' restore( +[^ ]+)* +--worktree'; then
        :
    else
        reason="git restore <path> discards uncommitted working-tree changes, the same failure as git checkout -- <path>."
    fi
fi

[ -n "$reason" ] || exit 0

msg="Refused: \`$(printf '%s' "$norm" | cut -c1-120)\`. $reason Take an out-of-tree copy before you break anything and restore from that instead - that is the reliable half of the lesson this guard enforces. To inspect without changing anything, \`git stash list\`, \`git status\` and \`git diff\` are all still available."

# Serialize with a real JSON writer, never by hand-escaping. The refusal message
# quotes the offending command back, so it carries whatever quotes, backslashes
# and shell metacharacters the agent typed - and a hand-rolled sed escape was
# observed here emitting an EMPTY reason for a command containing backslashes,
# which reaches the agent as a refusal with no explanation at all. Uses the same
# parser that read the payload above; the .ps1 twin uses ConvertTo-Json.
if command -v jq >/dev/null 2>&1; then
    printf '%s' "$msg" | jq -Rsc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}'
else
    printf '%s' "$msg" | python3 -c 'import sys,json;print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.stdin.read()}},separators=(",",":")))'
fi
exit 0
