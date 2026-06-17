#Requires -Module Pester
<#
.SYNOPSIS
    Pester tests for the DBAOps-Database deployment scripts.

.DESCRIPTION
    Validates that all :r include paths resolve to existing files, that Deploy-DBAOps.ps1
    script references are correct, that the Expand-SqlIncludes function behaves as expected,
    and that key SQL objects are present in their expected files.

    Run from the repo root:
        Invoke-Pester .\Tests\DBAOps.Tests.ps1 -Output Detailed
#>

BeforeDiscovery {
    # Data needed only for the agent-job and security object spot-check tests.
    $agentJobs = @(
        @{ File = 'DBAOps-CaptureDeadlocks.sql';        JobName = 'DBAOps - Capture - Deadlocks'         }
        @{ File = 'DBAOps-CaptureWaitStats.sql';        JobName = 'DBAOps - Capture - WaitStats'          }
        @{ File = 'DBAOps-CaptureBlockingHistory.sql';  JobName = 'DBAOps - Capture - Blocking History'   }
        @{ File = 'DBAOps-CaptureRpcExecutions.sql';    JobName = 'DBAOps - Capture - RpcExecutions'      }
        @{ File = 'DBAOps-CaptureSaActivity.sql';       JobName = 'DBAOps - Capture - SaActivity'         }
    )
    $roleFiles   = @(
        @{ File = 'dr_RO.sql' }; @{ File = 'dr_RW.sql' }; @{ File = 'dr_RWE.sql' }
        @{ File = 'dr_EO.sql' }; @{ File = 'dr_RE.sql' }; @{ File = 'dr_Del.sql' }
        @{ File = 'dr_Deploy.sql' }
    )
    $schemaFiles = @(
        @{ File = 'deploy.sql' }; @{ File = 'trace.sql' }; @{ File = 'monitor.sql' }
        @{ File = 'audit.sql' };  @{ File = 'maint.sql' }
    )
}

BeforeAll {
    $repoRoot   = Split-Path $PSScriptRoot -Parent
    $includeRx  = [regex]'^\s*:r\s+(.+?)\s*$'
    $deployRefRx = [regex]"'(Setup\\[^']+\.sql)'"

    # Collect all :r includes from Setup scripts
    $script:setupIncludes = @()
    foreach ($sf in (Get-ChildItem (Join-Path $repoRoot 'Setup') -Filter '*.sql')) {
        $dir = Split-Path $sf.FullName -Parent
        foreach ($line in (Get-Content $sf.FullName)) {
            $m = $includeRx.Match($line)
            if ($m.Success) {
                $rel = $m.Groups[1].Value
                $script:setupIncludes += [PSCustomObject]@{
                    ScriptName   = $sf.Name
                    RelativePath = $rel
                    FullPath     = Join-Path $dir $rel
                }
            }
        }
    }

    # Collect Deploy-DBAOps.ps1 Setup script references
    $script:deployRefs = @()
    foreach ($line in (Get-Content (Join-Path $repoRoot 'Deploy-DBAOps.ps1'))) {
        $m = $deployRefRx.Match($line)
        if ($m.Success) {
            $ref = $m.Groups[1].Value
            $script:deployRefs += [PSCustomObject]@{
                Reference = $ref
                FullPath  = Join-Path $repoRoot $ref
            }
        }
    }

    # Define Expand-SqlIncludes locally — mirrors Deploy-DBAOps.ps1 exactly
    function Expand-SqlIncludes {
        param([Parameter(Mandatory)][string]$FilePath)
        $dir     = Split-Path $FilePath -Parent
        $lines   = Get-Content $FilePath
        $expanded = foreach ($line in $lines) {
            if ($line -match '^\s*:r\s+(.+)$') {
                $includePath = Join-Path $dir $Matches[1].Trim()
                Expand-SqlIncludes -FilePath $includePath
            }
            elseif ($line -match '^\s*:') { }
            else { $line }
        }
        $expanded -join "`n"
    }
}


# =============================================================================
Describe 'Setup script :r include paths' {
# =============================================================================

    It 'collects at least one :r include from Setup scripts' {
        $script:setupIncludes.Count | Should -BeGreaterThan 0
    }

    It 'all :r include paths resolve to existing files' {
        $broken = $script:setupIncludes | Where-Object { -not (Test-Path $_.FullPath) }
        if ($broken) {
            $detail = ($broken | ForEach-Object {
                "  $($_.ScriptName)  ->  $($_.RelativePath)"
            }) -join "`n"
            $broken.Count | Should -Be 0 -Because "these paths do not exist on disk:`n$detail"
        }
        $broken | Should -BeNullOrEmpty
    }

}


# =============================================================================
Describe 'Deploy-DBAOps.ps1 script references' {
# =============================================================================

    It 'collects at least one script reference from Deploy-DBAOps.ps1' {
        $script:deployRefs.Count | Should -BeGreaterThan 0
    }

    It 'all Setup script references in Deploy-DBAOps.ps1 exist on disk' {
        $missing = $script:deployRefs | Where-Object { -not (Test-Path $_.FullPath) }
        if ($missing) {
            $detail = ($missing | ForEach-Object { "  $($_.Reference)" }) -join "`n"
            $missing.Count | Should -Be 0 -Because "these scripts are referenced but missing:`n$detail"
        }
        $missing | Should -BeNullOrEmpty
    }

}


# =============================================================================
Describe 'Expand-SqlIncludes function' {
# =============================================================================

    BeforeAll {
        $tmpRoot = Join-Path $env:TEMP "DBAOps.Tests.$(Get-Random)"
        New-Item -ItemType Directory -Path $tmpRoot | Out-Null
    }

    AfterAll {
        Remove-Item $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns file content when no :r directives are present' {
        $f = Join-Path $tmpRoot 'simple.sql'
        Set-Content $f "SELECT 1;`nSELECT 2;"
        $result = Expand-SqlIncludes -FilePath $f
        $result | Should -Match 'SELECT 1'
        $result | Should -Match 'SELECT 2'
    }

    It 'expands a :r include and inlines the referenced file content' {
        Set-Content (Join-Path $tmpRoot 'child.sql') "SELECT 'child content';"
        $parent = Join-Path $tmpRoot 'parent.sql'
        Set-Content $parent ":r child.sql"
        (Expand-SqlIncludes -FilePath $parent) | Should -Match 'child content'
    }

    It 'strips :setvar directives without including them in output' {
        $f = Join-Path $tmpRoot 'setvar.sql'
        Set-Content $f ":setvar XELogsPath `"C:\XEvents\`"`nSELECT 1;"
        $result = Expand-SqlIncludes -FilePath $f
        $result | Should -Not -Match ':setvar'
        $result | Should -Match 'SELECT 1'
    }

    It 'handles relative paths whose subdirectory names contain spaces' {
        $spaceDir = Join-Path $tmpRoot 'Stored Procedures'
        New-Item -ItemType Directory -Path $spaceDir | Out-Null
        Set-Content (Join-Path $spaceDir 'proc.sql') "CREATE PROCEDURE dbo.Test AS SELECT 1;"
        $parent = Join-Path $tmpRoot 'parent_spaces.sql'
        Set-Content $parent ":r Stored Procedures\proc.sql"
        (Expand-SqlIncludes -FilePath $parent) | Should -Match 'CREATE PROCEDURE'
    }

    It 'recursively expands nested :r includes' {
        Set-Content (Join-Path $tmpRoot 'level2.sql') "SELECT 'deep';"
        Set-Content (Join-Path $tmpRoot 'level1.sql') ":r level2.sql"
        Set-Content (Join-Path $tmpRoot 'level0.sql') ":r level1.sql"
        (Expand-SqlIncludes -FilePath (Join-Path $tmpRoot 'level0.sql')) | Should -Match 'deep'
    }

    It 'expands Setup\08_CreateAgentJobs.sql without throwing' {
        { Expand-SqlIncludes -FilePath (Join-Path $repoRoot 'Setup\08_CreateAgentJobs.sql') } |
            Should -Not -Throw
    }

    It 'expanded Setup\08_CreateAgentJobs.sql contains all five job names' {
        $sql = Expand-SqlIncludes -FilePath (Join-Path $repoRoot 'Setup\08_CreateAgentJobs.sql')
        $sql | Should -Match 'DBAOps - Capture - Deadlocks'
        $sql | Should -Match 'DBAOps - Capture - WaitStats'
        $sql | Should -Match 'DBAOps - Capture - Blocking History'
        $sql | Should -Match 'DBAOps - Capture - RpcExecutions'
        $sql | Should -Match 'DBAOps - Capture - SaActivity'
    }

    It 'expanded Setup\04_CreateProcedures.sql contains deploy schema proc definitions' {
        $sql = Expand-SqlIncludes -FilePath (Join-Path $repoRoot 'Setup\04_CreateProcedures.sql')
        $sql | Should -Match 'CREATE OR ALTER PROCEDURE \[deploy\]\.\[CleanupRollbackData\]'
        $sql | Should -Match 'CREATE OR ALTER PROCEDURE \[deploy\]\.\[CleanupRunOnceManifest\]'
    }

    It 'expanded Setup\03_CreateTables.sql contains deploy schema table definitions' {
        $sql = Expand-SqlIncludes -FilePath (Join-Path $repoRoot 'Setup\03_CreateTables.sql')
        $sql | Should -Match '\[deploy\]\.\[RollbackManifest\]'
        $sql | Should -Match '\[deploy\]\.\[RunOnceManifest\]'
    }

    It 'XELogsPath substitution removes the placeholder and inserts the supplied path' {
        $sql = Expand-SqlIncludes -FilePath (Join-Path $repoRoot 'Setup\08_CreateAgentJobs.sql')
        $sql = $sql -replace [regex]::Escape('$(XELogsPath)'), 'D:\XEvents\'
        $sql | Should -Match 'D:\\XEvents\\'
        $sql | Should -Not -Match '\$\(XELogsPath\)'
    }

}


# =============================================================================
Describe 'SQL object presence in source files' {
# =============================================================================

    It 'deploy\Tables\RollbackManifest.sql defines [deploy].[RollbackManifest]' {
        Get-Content (Join-Path $repoRoot 'deploy\Tables\RollbackManifest.sql') -Raw |
            Should -Match '\[deploy\]\.\[RollbackManifest\]'
    }

    It 'deploy\Tables\RunOnceManifest.sql defines [deploy].[RunOnceManifest]' {
        Get-Content (Join-Path $repoRoot 'deploy\Tables\RunOnceManifest.sql') -Raw |
            Should -Match '\[deploy\]\.\[RunOnceManifest\]'
    }

    It 'deploy\Tables\RollbackManifest.sql has IF OBJECT_ID idempotency guard' {
        Get-Content (Join-Path $repoRoot 'deploy\Tables\RollbackManifest.sql') -Raw |
            Should -Match "IF OBJECT_ID\(N'\[deploy\]\.\[RollbackManifest\]'"
    }

    It 'audit\Tables\SchemaChangeHistory.sql defines [audit].[SchemaChangeHistory]' {
        Get-Content (Join-Path $repoRoot 'audit\Tables\SchemaChangeHistory.sql') -Raw |
            Should -Match '\[audit\]\.\[SchemaChangeHistory\]'
    }

    It 'AgentJobs\<File> contains expected job name "<JobName>"' -ForEach $agentJobs {
        Get-Content (Join-Path $repoRoot "AgentJobs\$File") -Raw |
            Should -Match ([regex]::Escape($JobName))
    }

    It 'AgentJobs\DBAOps-CaptureSaActivity.sql uses $(XELogsPath) not a hardcoded drive path' {
        $content = Get-Content (Join-Path $repoRoot 'AgentJobs\DBAOps-CaptureSaActivity.sql') -Raw
        $content | Should -Match '\$\(XELogsPath\)'
        $content | Should -Not -Match "'[A-Z]:\\XEvents\\"
    }

    It 'Security\Roles\<File> has IF NOT EXISTS idempotency guard' -ForEach $roleFiles {
        Get-Content (Join-Path $repoRoot "Security\Roles\$File") -Raw |
            Should -Match 'IF NOT EXISTS'
    }

    It 'Security\Schemas\<File> uses sp_executesql for CREATE SCHEMA' -ForEach $schemaFiles {
        $content = Get-Content (Join-Path $repoRoot "Security\Schemas\$File") -Raw
        $content | Should -Match 'sp_executesql'
        $content | Should -Match 'CREATE SCHEMA'
    }

}


# =============================================================================
Describe 'Deploy-DBAOps.ps1 structure and safety' {
# =============================================================================

    BeforeAll {
        $script:deployContent = Get-Content (Join-Path $repoRoot 'Deploy-DBAOps.ps1') -Raw
    }

    It 'requires the dbatools module' {
        $script:deployContent | Should -Match '#Requires -Module dbatools'
    }

    It 'sets $ErrorActionPreference to Stop' {
        $script:deployContent | Should -Match "\`$ErrorActionPreference = 'Stop'"
    }

    It 'defines the Expand-SqlIncludes function' {
        $script:deployContent | Should -Match 'function Expand-SqlIncludes'
    }

    It 'uses Invoke-DbaQuery (not Invoke-Sqlcmd)' {
        $script:deployContent | Should -Match 'Invoke-DbaQuery'
        $script:deployContent | Should -Not -Match 'Invoke-Sqlcmd'
    }

    It "defaults XELogsPath to C:\XEvents\" {
        $script:deployContent | Should -Match ([regex]::Escape("XELogsPath = 'C:\XEvents\'"))
    }

    It 'does not reference old flat Trace\, Monitor\, or Maintenance\ paths' {
        $script:deployContent | Should -Not -Match "'Trace\\"
        $script:deployContent | Should -Not -Match "'Monitor\\"
        $script:deployContent | Should -Not -Match "'Maintenance\\"
    }

    It 'does not contain the removed -IncludeSaCapturePipeline parameter' {
        $script:deployContent | Should -Not -Match 'IncludeSaCapturePipeline'
    }

    It 'supports -WhatIf via SupportsShouldProcess' {
        $script:deployContent | Should -Match 'SupportsShouldProcess'
    }

}
