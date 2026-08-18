param([string]$AgentName = '')

# Loop audit hook - SubagentStop (Windows / PowerShell).
#
# Declared as a `Stop` hook in each loop agent's frontmatter; Claude Code
# converts that to SubagentStop and unregisters it when the agent finishes.
# Each agent passes its own name as the argument, so the log stays correct even
# if the payload's agent_type is absent on that path.
#
# Appends one line per finished subagent to loop/AUDIT.log, giving /retro a
# third record alongside loop/STATE.md and the commits. STATE.md is agents
# reporting on themselves and is written only after a task completes; this log
# is written by the harness as each spawn ends, so it survives a session that
# dies mid-task and cannot be shaped by the agent describing itself.
#
# Structural only - who ran, when, on what, with what verdict token. The
# narrative stays in STATE.md. Keeping content out means the log never leaks a
# long report and never needs truncating.
#
# Every path exits 0. Exit code 2 on SubagentStop *prevents the subagent from
# stopping*, so a crash here would hang the loop rather than lose a log line.

$ErrorActionPreference = 'SilentlyContinue'

try {
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

    $p = $raw | ConvertFrom-Json

    # Write only inside a project that has adopted the loop. cwd is the
    # authority on where we are; a hook registered at user scope fires in every
    # project, and a stray AUDIT.log in an unrelated repo is a bug report.
    $root = $p.cwd
    if ([string]::IsNullOrWhiteSpace($root)) { exit 0 }
    $loopDir = Join-Path $root 'loop'
    if (-not (Test-Path -LiteralPath $loopDir -PathType Container)) { exit 0 }

    $agent = if ($p.agent_type) { $p.agent_type }
             elseif ($AgentName) { $AgentName }
             else { 'unknown' }

    $id = '-'
    if ($p.agent_id) {
        $id = [string]$p.agent_id
        if ($id.Length -gt 8) { $id = $id.Substring(0, 8) }
    }

    $msg = if ($p.last_assistant_message) { [string]$p.last_assistant_message } else { '' }

    # Two views of the message. $flat keeps the original characters so T-003
    # stays intact; $norm reduces every non-alphanumeric to a space so a token
    # can be matched on whole-word boundaries with a plain substring test. The
    # .sh twin performs exactly this normalization - the two must agree on the
    # same payload, or the log's verdict column becomes platform-dependent.
    $flat = ($msg -replace '\s+', ' ').Trim()
    $norm = (($msg -replace '[^A-Za-z0-9]', ' ') -replace '\s+', ' ').Trim()

    # Task id, if the agent named one anywhere in its report.
    $task = '-'
    $m = [regex]::Match($flat, 'T-\d{3}')
    if ($m.Success) { $task = $m.Value }

    # Verdict vocabulary, shared with audit-subagent.sh and with the agent files
    # that emit it. Ordered most-specific first, because matching is substring-
    # based on word-bounded text: NOT VERIFIED must be tested before VERIFIED
    # and NO FINDINGS before FINDINGS, or the negative verdict logs as its
    # opposite.
    #
    # Keep this list in sync with the `VERDICT:` lines in .claude/agents/. A
    # token no agent emits is dead weight; an agent verdict absent here logs as
    # `-`, which is indistinguishable from "the agent said nothing".
    $verdicts = @(
        'NO TESTS EXECUTED',
        'UNABLE TO AUDIT',
        'CHANGES REQUESTED',
        'NOT VERIFIED',
        'NO FINDINGS',
        'TESTS PASSED',
        'TESTS FAILED',
        'APPROVED',
        'VERIFIED',
        'FINDINGS',
        'BLOCKED'
    )

    # Prefer the agent's declared `VERDICT: <token>` line. Scanning free prose is
    # the fallback only: it fires on a token used mid-sentence ("not
    # APPROVED-ing it yet"), and this log is supposed to be the record no agent
    # can shape.
    $padded = " $norm "
    $signal = '-'
    foreach ($prefix in @('VERDICT ', '')) {
        foreach ($pat in $verdicts) {
            if ($padded.Contains(" $prefix$pat ")) { $signal = $pat; break }
        }
        if ($signal -ne '-') { break }
    }

    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $line  = "$stamp | $agent | $task | $signal | $id"

    # Two subagents can finish at once; retry briefly rather than drop a line.
    $log = Join-Path $loopDir 'AUDIT.log'
    for ($i = 0; $i -lt 5; $i++) {
        try {
            Add-Content -LiteralPath $log -Value $line -Encoding utf8 -ErrorAction Stop
            break
        } catch {
            Start-Sleep -Milliseconds 40
        }
    }
}
catch { }

exit 0
