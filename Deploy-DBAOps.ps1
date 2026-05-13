#Requires -Module dbatools
<#
.SYNOPSIS
    Deploys the DBAOps database and all core objects to a SQL Server instance.

.DESCRIPTION
    Runs the Setup, Maintenance, Trace, and Monitor scripts in dependency order.
    Stops on the first error so a bad script does not let subsequent scripts run
    against a partially deployed database.

    Scripts intentionally excluded from this deploy:
      - Trace\XESessions\XEventSessions.sql              (review thresholds before enabling)
      - Trace\XESessions\XEventSession_DatabaseActivity.sql  (targeted, per-incident use)
      - Trace\XESessions\sa_activity_monitor.sql         (requires C:\XELogs\ and service
                                                          account write access -- run manually)

.PARAMETER SqlInstance
    Target SQL Server instance (e.g. <SqlInstance>).

.PARAMETER IncludeSaCapturePipeline
    Also deploys the sa activity capture objects:
      trace.SaLoginHistory, trace.CaptureSaActivity, trace.CleanupSaActivity.
    The sa_activity_monitor XE session must be running before the Agent jobs
    will produce data. Deploy it manually via Trace\XESessions\sa_activity_monitor.sql.

.PARAMETER CreateAgentJobs
    Creates the two SQL Agent jobs for the sa activity pipeline.
    Requires -IncludeSaCapturePipeline.

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance <SqlInstance>

    Deploys core DBAOps objects only.

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance <SqlInstance> -IncludeSaCapturePipeline -CreateAgentJobs

    Full deployment including the sa activity capture pipeline and Agent jobs.

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance <SqlInstance> -WhatIf

    Shows which scripts would run without executing them.
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    [switch]$IncludeSaCapturePipeline,

    [switch]$CreateAgentJobs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($CreateAgentJobs -and -not $IncludeSaCapturePipeline) {
    throw '-CreateAgentJobs requires -IncludeSaCapturePipeline.'
}

$root = $PSScriptRoot

$coreScripts = @(
    'Setup\01_CreateDatabase.sql',
    'Setup\02_CreateSchemas.sql',
    'Setup\03_CreateTables.sql',
    'Setup\04_CreateUsers.sql',
    'Maintenance\CleanupRollbackData.sql',
    'Maintenance\CleanupRunOnceManifest.sql',
    'Trace\DeadlockHistory.sql',
    'Trace\CleanupDeadlockHistory.sql',
    'Monitor\WaitStatsSnapshot.sql',
    'Monitor\CleanupWaitStats.sql'
)

$saScripts = @(
    'Trace\SaLoginHistory.sql',
    'Trace\CaptureSaActivity.sql',
    'Trace\CleanupSaActivity.sql'
)

$scripts = [System.Collections.Generic.List[string]]::new()
$scripts.AddRange([string[]]$coreScripts)

if ($IncludeSaCapturePipeline) {
    $scripts.AddRange([string[]]$saScripts)
}

if ($CreateAgentJobs) {
    $scripts.Add('Setup\05_CreateAgentJobs.sql')
}

Write-Host "DBAOps deployment -> $SqlInstance" -ForegroundColor White

foreach ($relative in $scripts) {
    $path = Join-Path $root $relative

    if (-not (Test-Path $path)) {
        Write-Error "Script not found: $path"
        return
    }

    if ($PSCmdlet.ShouldProcess($SqlInstance, "Execute $relative")) {
        Write-Host "  --> $relative" -ForegroundColor Cyan
        Invoke-DbaQuery -SqlInstance $SqlInstance -File $path -MessagesToOutput -EnableException
    }
}

if ($IncludeSaCapturePipeline) {
    Write-Host ''
    Write-Warning @"
sa_activity_monitor XE session was NOT deployed by this script.
Before the capture job will produce data, run manually on each instance:
  1. Create C:\XELogs\ and grant the SQL Server service account write access.
  2. Execute Trace\XESessions\sa_activity_monitor.sql.
  3. Verify: SELECT * FROM sys.dm_xe_sessions WHERE name = 'sa_activity_monitor'
"@
}

Write-Host 'Deployment complete.' -ForegroundColor Green
