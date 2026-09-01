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
#   git checkout [<ref>] --   - reverts to that commit, discarding your own
#   git checkout [<ref>] .      in-progress edits along with whatever you meant
#                               to undo. The ref is optional and usually there:
#                               `git checkout HEAD -- <path>` is the common form.
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

# .tool_input.command, via a reader chosen by PROBING it, never by `command -v`
# alone - audit-subagent.sh carries the same three-way selection.
#
# This block is why the probe exists. On Windows, `python3` commonly resolves to
# the Microsoft Store App Execution Alias: it satisfies `command -v`, prints
# "Python was not found", exits 49, and writes nothing. `cmd` was then empty,
# the guard hit the fail-open below, and a real `git stash` - the command that
# destroyed work twice in this project's history - went straight through, with
# no error anywhere. Measured on Windows 11 + Git Bash, jq absent.
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

case $JSON_READER in
    jq)      cmd=$(printf '%s' "$raw" | jq -r '.tool_input.command // ""' 2>/dev/null) ;;
    python3) cmd=$(printf '%s' "$raw" | python3 -c \
                 'import sys,json;print((json.load(sys.stdin).get("tool_input") or {}).get("command") or "")' 2>/dev/null) ;;
    perl)    cmd=$(printf '%s' "$raw" | perl -MJSON::PP -e \
                 'my $d=eval{JSON::PP->new->decode(do{local $/;<STDIN>})};my $v=eval{$d->{tool_input}{command}};print defined $v ? $v : ""' 2>/dev/null) ;;
    *)       exit 0 ;;
esac
[ -n "$cmd" ] || exit 0

# Collapse whitespace so the patterns below need only handle single spaces.
# Matching runs over the whole string rather than per segment, so a command
# hidden behind && or a subshell is still caught.
norm=$(printf '%s' "$cmd" | tr '\n\r\t' '   ' | tr -s ' ')

# `git` followed by any number of leading options (-C <path>, --no-pager, ...)
# and then the subcommand.
GIT_PREFIX='(^|[^A-Za-z0-9_-])git( +-{1,2}[^ ]+( +[^ -][^ ]*)?)* +'
git_sub() { printf '%s' "$norm" | grep -qE "$GIT_PREFIX$1( |$)" ; }

reason=''

# 1. git stash - except the two read-only subcommands.
#
# EVERY `git stash` in the command is classified, not one of them. Extracting a
# single occurrence was the earlier shape, and it picked a different one on each
# platform: `sed` matches greedily so it took the LAST, .NET's Match is leftmost
# so it took the FIRST. `git stash && git stash list` was therefore refused on
# Windows and allowed here, and `git stash list && git stash` refused here and
# allowed on Windows - so on either platform there was a spelling that walked a
# real stash straight past the guard. One dangerous occurrence now refuses the
# whole command.
#
# This half fails CLOSED, unlike the payload read above: if git_sub finds a stash
# the scan cannot classify, the command is refused. Guessing permissively about
# an unrecognised spelling of a work-destroying command costs the user their
# tree; guessing strictly costs them one retry.
if git_sub stash; then
    reason="git stash sweeps up every uncommitted change in the tree, including work belonging to other tasks. Two incidents in this project's history lost work to it."
    occurrences=$(printf '%s' "$norm" | grep -oE "${GIT_PREFIX}stash( +[A-Za-z][A-Za-z-]*)?")
    if [ -n "$occurrences" ]; then
        all_safe=1
        _oldifs=$IFS
        IFS='
'
        set -- $occurrences
        IFS=$_oldifs
        for _occ do
            # Strip through the subcommand keyword. `##` takes the LAST `stash`
            # in the occurrence, so a `-C /srv/stash` option earlier in the same
            # match cannot be mistaken for it.
            _sub=${_occ##*stash}
            _sub=${_sub# }
            case "$_sub" in
                list|show) : ;;
                *) all_safe=0 ;;
            esac
        done
        [ "$all_safe" = 1 ] && reason=''
    fi
fi

# 2. git checkout with a pathspec - the `--` form or a bare `.`.
#
# A ref may sit between the subcommand and the pathspec, and the earlier pattern
# admitted only `-`-prefixed options there - so `git checkout HEAD -- <path>`,
# the most common spelling of this failure by some margin, matched nothing and
# was allowed. Intervening tokens are now unrestricted apart from the shell
# operators, which is what stops the bare-`.` branch reaching across an `&&`
# into an unrelated `cd .`.
if [ -z "$reason" ] && git_sub checkout; then
    if printf '%s' "$norm" | grep -qE ' checkout( +[^ &|;]+)* +(--( |$)|\.( |$))'; then
        reason="git checkout [<ref>] -- <path> reverts the file to that commit, discarding your own in-progress edits along with whatever you meant to undo. It is safe only when the file has no other uncommitted work, which is almost never true mid-task."
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
# reader selected above; the .ps1 twin uses ConvertTo-Json. Falling through
# this case with no reader is impossible: an unreadable payload exits earlier.
case $JSON_READER in
    jq)      printf '%s' "$msg" | jq -Rsc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:.}}' ;;
    python3) printf '%s' "$msg" | python3 -c 'import sys,json;print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.stdin.read()}},separators=(",",":")))' ;;
    perl)    printf '%s' "$msg" | perl -MJSON::PP -e 'my $m=do{local $/;<STDIN>};print JSON::PP->new->canonical(0)->encode({hookSpecificOutput=>{hookEventName=>"PreToolUse",permissionDecision=>"deny",permissionDecisionReason=>$m}})' ;;
esac
exit 0
