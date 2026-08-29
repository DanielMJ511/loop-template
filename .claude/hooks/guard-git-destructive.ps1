# Destructive-git guard - PreToolUse on Bash (Windows / PowerShell).
# Counterpart of guard-git-destructive.sh; the two must agree on the same
# command string, or what is refused becomes platform-dependent.
#
# Declared in .claude/skills/orchestrate/SKILL.md and in every Bash-capable
# agent's frontmatter, so it covers the orchestrator's own calls and each
# subagent's. Subagent hooks fire only while that subagent runs.
#
# BLOCKING, unlike the loop's other two hooks. See the .sh twin's header for why
# refusing beat instructing: the constraint was stated, banked, sharpened after a
# second incident, and delivered verbatim in a spawn prompt, and an agent ran the
# command anyway.
#
# Refuses `git stash`, `git checkout [<ref>] -- <path>` / `git checkout .`, and
# `git restore <path>`. Still allows `git stash list` and `git stash show` -
# read-only, and the loop's own verification procedure runs `git stash list` to
# confirm a tree is intact - plus `git restore --staged` and branch switching.
#
# Does NOT skip when loop/ is absent: a guard that disables itself based on what
# is in the directory is a guard with a bypass. Fails OPEN on an unreadable
# payload, so it can never wedge every Bash call in the session.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $p = $raw | ConvertFrom-Json
    $cmd = ''
    if ($p.tool_input -and $p.tool_input.command) { $cmd = [string]$p.tool_input.command }
    if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

    # Collapse whitespace so the patterns need only handle single spaces.
    # Matching runs over the whole string, so a command hidden behind && or a
    # subshell is still caught. The .sh twin performs exactly this.
    $norm = ($cmd -replace '\s+', ' ').Trim()

    # `git` plus any number of leading options (-C <path>, --no-pager, ...) then
    # the subcommand.
    $gitPrefix = "(^|[^A-Za-z0-9_-])git( +-{1,2}[^ ]+( +[^ -][^ ]*)?)* +"
    function Test-GitSub([string]$sub) {
        return [regex]::IsMatch($norm, "$gitPrefix$sub( |`$)")
    }

    $reason = ''

    # 1. git stash - except the two read-only subcommands.
    #
    # EVERY `git stash` in the command is classified, not one of them. Extracting
    # a single occurrence was the earlier shape, and it picked a different one on
    # each platform: Match is leftmost so it took the FIRST, the .sh twin's `sed`
    # is greedy so it took the LAST. `git stash && git stash list` was therefore
    # refused here and allowed under sh, and `git stash list && git stash`
    # refused under sh and allowed here - so on either platform there was a
    # spelling that walked a real stash straight past the guard. One dangerous
    # occurrence now refuses the whole command.
    #
    # This half fails CLOSED, unlike the payload read above: if Test-GitSub finds
    # a stash the scan cannot classify, the command is refused. Guessing
    # permissively about an unrecognised spelling of a work-destroying command
    # costs the user their tree; guessing strictly costs them one retry.
    if (Test-GitSub 'stash') {
        $reason = "git stash sweeps up every uncommitted change in the tree, including work belonging to other tasks. Two incidents in this project's history lost work to it."
        $occurrences = [regex]::Matches($norm, $gitPrefix + 'stash( +[A-Za-z][A-Za-z-]*)?')
        if ($occurrences.Count -gt 0) {
            $allSafe = $true
            foreach ($occ in $occurrences) {
                # Strip through the subcommand keyword. LastIndexOf takes the
                # LAST `stash` in the occurrence, so a `-C /srv/stash` option
                # earlier in the same match cannot be mistaken for it.
                $v = $occ.Value
                $sub = $v.Substring($v.LastIndexOf('stash') + 5).Trim()
                if ($sub -ne 'list' -and $sub -ne 'show') { $allSafe = $false }
            }
            if ($allSafe) { $reason = '' }
        }
    }

    # 2. git checkout with a pathspec - the `--` form or a bare `.`.
    #
    # A ref may sit between the subcommand and the pathspec, and the earlier
    # pattern admitted only `-`-prefixed options there - so
    # `git checkout HEAD -- <path>`, the most common spelling of this failure by
    # some margin, matched nothing and was allowed. Intervening tokens are now
    # unrestricted apart from the shell operators, which is what stops the
    # bare-`.` branch reaching across an `&&` into an unrelated `cd .`.
    if (-not $reason -and (Test-GitSub 'checkout')) {
        if ([regex]::IsMatch($norm, ' checkout( +[^ &|;]+)* +(--( |$)|\.( |$))')) {
            $reason = "git checkout [<ref>] -- <path> reverts the file to that commit, discarding your own in-progress edits along with whatever you meant to undo. It is safe only when the file has no other uncommitted work, which is almost never true mid-task."
        }
    }

    # 3. git restore - except --staged on its own, which leaves content alone.
    if (-not $reason -and (Test-GitSub 'restore')) {
        $staged   = [regex]::IsMatch($norm, ' restore( +[^ ]+)* +--staged')
        $worktree = [regex]::IsMatch($norm, ' restore( +[^ ]+)* +--worktree')
        if (-not ($staged -and -not $worktree)) {
            $reason = "git restore <path> discards uncommitted working-tree changes, the same failure as git checkout -- <path>."
        }
    }

    if (-not $reason) { exit 0 }

    $shown = if ($norm.Length -gt 120) { $norm.Substring(0, 120) } else { $norm }
    $msg = "Refused: ``$shown``. $reason Take an out-of-tree copy before you break anything and restore from that instead - that is the reliable half of the lesson this guard enforces. To inspect without changing anything, ``git stash list``, ``git status`` and ``git diff`` are all still available."

    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $msg
        }
    }
    # Built with a real serializer rather than hand-escaped quotes - the seeded
    # lesson about hand-built payloads applies to what a hook emits too.
    $out | ConvertTo-Json -Compress -Depth 5
}
catch { }

exit 0
