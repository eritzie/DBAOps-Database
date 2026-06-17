#Requires -Module dbatools
<#
.SYNOPSIS
    Deploys the DBAOps database and all core objects to a SQL Server instance.

.DESCRIPTION
    Runs the numbered Setup scripts in order. Each Setup script uses SQLCMD :r includes
    to reference the individual object scripts — the individual files remain the source
    of truth and can still be run standalone via SSMS (SQLCMD Mode) or sqlcmd.exe.

    Scripts intentionally excluded from this deploy:
      - Setup\09_CreateXESessions_MANUAL-SETUP.sql    (review ring buffer sizes and file paths
                                          per instance before enabling — run manually
                                          in SSMS with SQLCMD Mode or via sqlcmd.exe)

.PARAMETER SqlInstance
    Target SQL Server instance (e.g. SQL-DEV-01).

.PARAMETER CreateAgentJobs
    Runs Setup\08_CreateAgentJobs.sql, which creates all five DBAOps capture jobs.
    Three jobs require XE sessions that are NOT deployed by this script:
      - DBAOps - Capture - Blocking History  -> XESessions\DBAOps_BlockedProcess.sql
      - DBAOps - Capture - RpcExecutions     -> XESessions\DBAOps_SpExecutionCapture.sql
      - DBAOps - Capture - SaActivity        -> XESessions\DBAOps_SaActivityMonitor.sql
    Run Setup\09_CreateXESessions_MANUAL-SETUP.sql manually after reviewing per-instance settings.

.PARAMETER XELogsPath
    Path to the XE log folder on the target instance. Must end with a backslash.
    Defaults to C:\XEvents\. Substituted into the SaActivity Agent job step.

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01

    Deploys core DBAOps objects (scripts 01 through 06 and 09).

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -CreateAgentJobs

    Full deployment including all five Agent jobs.

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -CreateAgentJobs -XELogsPath 'D:\XEvents\'

    Full deployment for an instance where the XE log folder is on D:\.

.EXAMPLE
    .\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -WhatIf

    Shows which scripts would run without executing them.
#>
[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [string]$SqlInstance,

    [switch]$CreateAgentJobs,

    [string]$XELogsPath = 'C:\XEvents\'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot

#
# Expand-SqlIncludes
# Recursively resolves SQLCMD :r directives so Invoke-DbaQuery receives plain SQL.
# Other SQLCMD directives (:setvar, :on error, etc.) are stripped.
#
function Expand-SqlIncludes {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $dir     = Split-Path $FilePath -Parent
    $lines   = Get-Content $FilePath

    $expanded = foreach ($line in $lines) {
        if ($line -match '^\s*:r\s+(.+)$') {
            $includePath = Join-Path $dir $Matches[1].Trim()
            Expand-SqlIncludes -FilePath $includePath
        }
        elseif ($line -match '^\s*:') {
            # Strip other SQLCMD directives (:setvar, :on error, etc.)
        }
        else {
            $line
        }
    }

    $expanded -join "`n"
}

$coreScripts = @(
    'Setup\01_CreateDatabase.sql',
    'Setup\02_CreateSchemas.sql',
    'Setup\03_CreateTables.sql',
    'Setup\04_CreateProcedures.sql',
    'Setup\05_CreateTriggers.sql',
    'Setup\06_CreateUsers.sql',
    'Setup\07_CreateRoles.sql'
)

$scripts = [System.Collections.Generic.List[string]]::new()
$scripts.AddRange([string[]]$coreScripts)

if ($CreateAgentJobs) {
    $scripts.Add('Setup\08_CreateAgentJobs.sql')
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
        $sql = Expand-SqlIncludes -FilePath $path
        $sql = $sql -replace [regex]::Escape('$(XELogsPath)'), $XELogsPath
        Invoke-DbaQuery -SqlInstance $SqlInstance -Query $sql -MessagesToOutput -EnableException
    }
}

if ($CreateAgentJobs) {
    Write-Host ''
    Write-Warning @"
Three Agent jobs require XE sessions that were NOT deployed by this script:
  - DBAOps - Capture - Blocking History  -> XESessions\DBAOps_BlockedProcess.sql
  - DBAOps - Capture - RpcExecutions     -> XESessions\DBAOps_SpExecutionCapture.sql
  - DBAOps - Capture - SaActivity        -> XESessions\DBAOps_SaActivityMonitor.sql
Run Setup\09_CreateXESessions_MANUAL-SETUP.sql manually after reviewing per-instance settings.
Jobs 'DBAOps - Capture - Deadlocks' and 'DBAOps - Capture - WaitStats' are ready immediately.
"@
}

Write-Host 'Deployment complete.' -ForegroundColor Green
