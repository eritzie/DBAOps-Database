# DBAOps

A DBA operational utility database for SQL Server environments. Provides centralized storage for deployment tracking, maintenance logging, and diagnostic data.

## What Is This?

`DBAOps` is a contained database designed to be the single operational hub for DBA tooling on a SQL Server instance. Instead of scattering operational objects across `master`, `tempdb`, or ad-hoc utility databases, everything lives here with clear schema boundaries.

## Schema Layout

| Schema    | Purpose                                                     | Owner          |
|-----------|-------------------------------------------------------------|----------------|
| `dbo`     | Ola Hallengren Maintenance Solution objects                 | Ola / dbatools |
| `deploy`  | Deployment manifests, rollback data, run-once tracking      | DBA team       |
| `trace`   | Extended Events targets, diagnostic log archives            | DBA team       |
| `monitor` | (Future) Server health snapshots, wait stats, etc.          | DBA team       |

## Quick Start

Run the setup scripts in order:

```sql
-- 1. Create the contained database
:r Setup\01_CreateDatabase.sql

-- 2. Create schemas
:r Setup\02_CreateSchemas.sql

-- 3. Create tables (RollbackManifest, RunOnceManifest)
:r Setup\03_CreateTables.sql

-- 4. Create contained users (review and customize first)
:r Setup\04_CreateUsers.sql

-- 5. Create deploy maintenance procedures
:r Maintenance\usp_CleanupRollbackData.sql
:r Maintenance\usp_CleanupRunOnceManifest.sql

-- 6. Create trace objects (deadlock history)
:r Trace\DeadlockHistory.sql
:r Trace\usp_CleanupDeadlockHistory.sql

-- 7. Create monitor objects (wait stats snapshots)
:r Monitor\WaitStatsSnapshot.sql
:r Monitor\usp_CleanupWaitStats.sql
```

Install Ola Hallengren's Maintenance Solution:

```powershell
Install-DbaMaintenanceSolution -SqlInstance YourServer -Database DBAOps -InstallJobs -LogToTable -CleanupTime 168
```

## Template Strategy

The repo provides two templates for two fundamentally different deployment scenarios:

**Data changes** (`DataUpdate_Script_Template.sql`) — one-time data fixes, backfills, migrations. These can't be rolled back from source control, so the template provides rollback data capture via `RollbackManifest` and run-once idempotency via `RunOnceManifest`. This is the heavy-duty template.

**Schema changes** (`StoredProcedure_Template.sql`) — stored procedure deployments using `CREATE OR ALTER`. These are inherently idempotent and rollback is handled by deploying the previous version from Git. The template is a lightweight deployment wrapper with diagnostic header/footer logging. No manifest machinery needed.

Two additional lightweight templates are included for ad-hoc use outside of CI/CD pipelines:

| Template | Purpose |
|----------|---------|
| `Server_Database_SprocName.sql` | Minimal stored procedure — `CREATE OR ALTER`, `TRY/CATCH`, `THROW` |
| `Server_Database_ScriptName.sql` | Lightweight ad-hoc data script with basic transaction safety |

## Run-Once System

### How It Works

Data update scripts are self-guarding. The template checks `deploy.RunOnceManifest` on startup — if a row exists with `Status = 'Success'` for that script name, execution is skipped. This means:

- Scripts can live in the repo permanently without risk of re-execution
- Failed runs are recorded but do not block retries
- Each environment (Dev, Test, Prod) has its own `DBAOps` instance, so the same script runs once per environment automatically
- No manual tracking, no archive folders, no pipeline write-back to the repo

### Script Flow

```
Script starts
  → Check RunOnceManifest (already succeeded? → skip)
  → Check open transactions
  → Register in RollbackManifest
  → Capture rollback data (SELECT INTO)
  → Print BEFORE image
  → Apply data change (TRY/CATCH)
  → Print AFTER image
  → Register Success in RunOnceManifest
  → Footer

On error:
  → Register Failed in RunOnceManifest (with error message)
  → RAISERROR
  → Footer
```

### Querying the RunOnce Manifest

```sql
-- What has run on this server?
SELECT * FROM [DBAOps].[deploy].[RunOnceManifest] ORDER BY [ExecutedAt] DESC;

-- Would a specific script run or skip?
SELECT * FROM [DBAOps].[deploy].[RunOnceManifest]
WHERE [ScriptName] = 'DataUpdate_PBI4530_FixOrphanedAccounts.sql';

-- Everything from a specific pipeline run
SELECT * FROM [DBAOps].[deploy].[RunOnceManifest] WHERE [DeploymentId] = 'PR-895';
```

## Deployment Rollback System

### How It Works

When a data update script runs:

1. A manifest row is inserted into `deploy.RollbackManifest` with deployment context (ticket, PR number, source table, etc.)
2. The affected data is captured via `SELECT INTO` to a rollback table named `deploy.RB_<ManifestId>_<TableName>`
3. The data change is applied inside a transaction
4. If rollback is needed (even days later), the manifest points you to the exact rollback table

### Lifecycle

```
Active → Expired → Archived (table dropped) → Purged (manifest row deleted, optional)
```

- **Active**: Rollback data is available. Protected from cleanup.
- **RolledBack**: Data was used to reverse a deployment.
- **Expired**: Past retention period. Data table still exists during grace period.
- **Archived**: Rollback table has been dropped. Manifest row retained for audit trail.

### Querying the Rollback Manifest

```sql
-- All active rollback entries
SELECT * FROM [DBAOps].[deploy].[RollbackManifest] WHERE [Status] = 'Active';

-- Everything for a specific ticket
SELECT * FROM [DBAOps].[deploy].[RollbackManifest] WHERE [Ticket] = 'PBI-12345';

-- Everything from a specific pipeline run
SELECT * FROM [DBAOps].[deploy].[RollbackManifest] WHERE [DeploymentId] = 'PR-678';
```

## Maintenance

### Rollback Cleanup

```sql
-- Preview what would be cleaned up
EXEC [deploy].[usp_CleanupRollbackData] @WhatIf = 1;

-- Run with defaults (30-day retention, 14-day grace period)
EXEC [deploy].[usp_CleanupRollbackData];
```

### RunOnce Cleanup

```sql
-- Preview what would be cleaned up
EXEC [deploy].[usp_CleanupRunOnceManifest] @WhatIf = 1;

-- Run with defaults (90 days for failures, 365 for successes)
EXEC [deploy].[usp_CleanupRunOnceManifest];

-- Keep success rows forever (safest — prevents accidental re-execution)
EXEC [deploy].[usp_CleanupRunOnceManifest] @SuccessRetentionDays = -1;
```

Both procs can be scheduled as SQL Agent job steps (weekly recommended) or run manually.

## Cloud Compatibility

- **Azure SQL Database**: Contained by default. The setup scripts work as-is (skip `sp_configure` and `CONTAINMENT` settings).
- **AWS RDS for SQL Server**: Supports `PARTIAL` containment. Run setup scripts normally.
- **On-premises**: Run setup scripts in order. `contained database authentication` is enabled automatically.

## Trace Schema

Diagnostic event capture for post-incident analysis.

**Deadlock History** — `trace.DeadlockHistory` stores parsed deadlock graphs extracted from the `system_health` XE session. The `trace.usp_CaptureDeadlocks` proc pulls new events from the ring buffer and deduplicates against prior captures. Schedule every 5-15 minutes via SQL Agent.

**XE Session Definitions** — Pre-built Extended Events sessions for blocked process reports and long-running query capture. These are template scripts (commented out by default) — review thresholds and enable as needed.

```sql
-- Check recent deadlocks
SELECT TOP 10 * FROM [DBAOps].[trace].[DeadlockHistory] ORDER BY [EventTime] DESC;
```

## Monitor Schema

Periodic server health snapshots for trend analysis.

**Wait Stats Snapshots** — `monitor.WaitStatsSnapshot` stores cumulative wait stats from `sys.dm_os_wait_stats` with benign waits excluded (Paul Randal's standard exclusion list). The `monitor.usp_CaptureWaitStats` proc takes a snapshot. Schedule every 15-30 minutes. Analyze by computing deltas between two snapshot IDs.

```sql
-- Capture a snapshot
EXEC [monitor].[usp_CaptureWaitStats];

-- Top waits in the last snapshot interval
SELECT TOP 10
    curr.WaitType,
    curr.WaitTimeMs - prev.WaitTimeMs AS DeltaWaitMs
FROM [monitor].[WaitStatsSnapshot] curr
    INNER JOIN [monitor].[WaitStatsSnapshot] prev
        ON curr.WaitType = prev.WaitType AND prev.SnapshotId = curr.SnapshotId - 1
WHERE curr.SnapshotId = (SELECT MAX(SnapshotId) FROM [monitor].[WaitStatsSnapshot])
ORDER BY DeltaWaitMs DESC;
```

## Maintenance Summary

All cleanup procs follow the same pattern: configurable retention, `@WhatIf` preview mode, safe defaults. Schedule as SQL Agent job steps (weekly recommended).

| Proc | Schema | Default Retention | Notes |
|------|--------|-------------------|-------|
| `usp_CleanupRollbackData` | deploy | 30 days + 14-day grace | Drops rollback data tables |
| `usp_CleanupRunOnceManifest` | deploy | 90 days (Failed), 365 days (Success) | `-1` for indefinite Success retention |
| `usp_CleanupDeadlockHistory` | trace | 90 days | |
| `usp_CleanupWaitStats` | monitor | 30 days | |

## Customization

The data update template uses `@UtilityDB` as a configurable variable defaulting to `DBAOps`. If your environment uses a different name, change this variable — no other modifications needed.

## CI/CD Integration

The `DataUpdate_Script_Template.sql` includes a `@DeploymentId` variable designed for pipeline injection:

- **Azure DevOps**: `$(Build.BuildId)`, `PR-$(System.PullRequest.PullRequestId)`, `$(Release.ReleaseName)`
- **GitHub Actions**: `${{ github.run_id }}`, `PR-${{ github.event.pull_request.number }}`
- **Jenkins**: `${BUILD_NUMBER}`, `${CHANGE_ID}`

## Repository Structure

```
DBAOps/
├── README.md
├── LICENSE
├── .gitignore
├── Setup/
│   ├── 01_CreateDatabase.sql
│   ├── 02_CreateSchemas.sql
│   ├── 03_CreateTables.sql
│   └── 04_CreateUsers.sql
├── Maintenance/
│   ├── usp_CleanupRollbackData.sql
│   └── usp_CleanupRunOnceManifest.sql
├── Trace/
│   ├── DeadlockHistory.sql
│   ├── XEventSessions.sql
│   └── usp_CleanupDeadlockHistory.sql
├── Monitor/
│   ├── WaitStatsSnapshot.sql
│   └── usp_CleanupWaitStats.sql
├── Templates/
│   ├── DataUpdate_Script_Template.sql
│   ├── StoredProcedure_Template.sql
│   ├── Server_Database_SprocName.sql
│   └── Server_Database_ScriptName.sql
└── Samples/
    └── azure-pipelines-sample.yml
```