param([string]$AgentName = '')

# Loop audit hook — SubagentStop (Windows / PowerShell).
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
# Structural only — who ran, when, on what, with what verdict token. The
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

    $msg  = if ($p.last_assistant_message) { [string]$p.last_assistant_message } else { '' }
    $flat = ($msg -replace '\s+', ' ').Trim()

    # Task id, if the agent named one anywhere in its report.
    $task = '-'
    $m = [regex]::Match($flat, 'T-\d{3}')
    if ($m.Success) { $task = $m.Value }

    # Verdict token. Matched case-sensitively on word boundaries: these agents
    # emit uppercase verdicts by convention, and a case-insensitive match would
    # fire on the word "approved" appearing anywhere in prose.
    $signal = '-'
    foreach ($pat in @('NO TESTS EXECUTED', 'CHANGES REQUESTED', 'APPROVED', 'BLOCKED', 'FAILED')) {
        if ($flat -cmatch ('\b' + [regex]::Escape($pat) + '\b')) { $signal = $pat; break }
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
