# DBAOps

A DBA operational utility database for SQL Server environments. Provides centralized storage for deployment tracking, diagnostic event capture, server health monitoring, and schema change auditing.

## What Is This?

`DBAOps` is a contained database designed to be the single operational hub for DBA tooling on a SQL Server instance. Instead of scattering operational objects across `master`, `tempdb`, or ad-hoc utility databases, everything lives here with clear schema boundaries.

## Schema Layout

| Schema    | Purpose                                                          |
|-----------|------------------------------------------------------------------|
| `dbo`     | Instance-diagnostic utility procedures (DMV queries, no tables) |
| `deploy`  | Deployment manifests, rollback data, run-once tracking           |
| `trace`   | XE-backed event capture — deadlocks, blocking, RPC, sa activity |
| `monitor` | Server health snapshots and wait statistics history              |
| `audit`   | DDL change history (XE ring buffer) and sa login event capture   |
| `maint`   | Reserved for future maintenance objects                          |

## Quick Deploy (PowerShell)

Requires the `dbatools` module. `Deploy-DBAOps.ps1` runs the numbered Setup scripts in dependency order and stops on the first error.

```powershell
# Core deployment (01 through 07)
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01

# Core + all five Agent jobs
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -CreateAgentJobs

# Non-default XE log path for the sa capture job
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -CreateAgentJobs -XELogsPath 'D:\XEvents\'

# Preview without executing
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -WhatIf
```

**`Setup\09_CreateXESessions_MANUAL-SETUP.sql` is excluded from the automated deploy** — XE sessions require per-instance review of ring buffer sizes and file paths. Run it manually via SSMS or `sqlcmd.exe` after reviewing the settings.

## Manual Deployment

Run the Setup scripts in order in SSMS or via `sqlcmd.exe`:

```sql
:r Setup\01_CreateDatabase.sql      -- contained database + SIMPLE recovery
:r Setup\02_CreateSchemas.sql       -- all six operational schemas
:r Setup\03_CreateTables.sql        -- all tables across deploy, trace, monitor, audit
:r Setup\04_CreateProcedures.sql    -- all stored procedures across all schemas
:r Setup\05_CreateTriggers.sql      -- trg_SchemaChangeCapture on DBAOps (legacy DDL trigger)
:r Setup\06_CreateUsers.sql         -- contained user template (customize before running)
:r Setup\07_CreateRoles.sql         -- dr_RO, dr_RW, dr_RWE, dr_EO, dr_RE, dr_Del, dr_Deploy
:r Setup\08_CreateAgentJobs.sql     -- five DBAOps capture jobs (no schedules added)
:r Setup\09_CreateXESessions_MANUAL-SETUP.sql    -- XE sessions (review per instance before enabling)
```

Ola Hallengren's Maintenance Solution is not part of DBAOps but is commonly deployed to the same database. Use `-LogToTable` to enable command logging:

```powershell
Install-DbaMaintenanceSolution -SqlInstance SQL-DEV-01 -Database DBAOps -InstallJobs -LogToTable -CleanupTime 168
```

## Capture Pipelines

Six capture pipelines write diagnostic data into DBAOps. Each follows the same pattern: an XE session (manual deploy) feeds a capture proc, a cleanup proc manages retention, and an Agent job schedules both steps.

| Pipeline | Schema | XE Session | Table | Capture Proc | Recommended Interval |
|----------|--------|-----------|-------|-------------|----------------------|
| Deadlocks | `trace` | `system_health` (built-in) | `trace.DeadlockHistory` | `trace.CaptureDeadlocks` | 5 min |
| Blocking | `trace` | `DBAOps_BlockedProcess` | `trace.BlockingHistory` | `trace.CaptureBlockingHistory` | 5 min |
| RPC Execution | `trace` | `DBAOps_SpExecutionCapture` | `trace.RpcExecutionHistory` | `trace.CaptureRpcExecutions` | 30–60 min |
| sa Activity | `trace` | `DBAOps_SaActivityMonitor` (file target, optional) | `trace.SaLoginHistory` | `trace.CaptureSaActivity` | 10 min |
| sa Activity | `audit` | `DBAOps_SaActivityMonitor` (ring buffer) | `audit.SaLoginHistory` | `audit.CaptureSaActivity` | 5 min |
| Schema Changes | `audit` | `DBAOps_SchemaChange` (ring buffer) | `audit.SchemaChangeHistory` | `audit.CaptureSchemaChanges` | 5 min |

The deadlock pipeline is ready immediately after deployment — it reads `system_health` which is always active. All others require their XE sessions to be deployed first. The `audit` sa activity pipeline is the successor to the `trace` version — it reads from the ring buffer and does not require a file system path.

```sql
-- Recent deadlocks
SELECT TOP 10 [EventTime], [DatabaseName], [VictimProcess], [DeadlockGraph]
FROM [DBAOps].[trace].[DeadlockHistory]
ORDER BY [EventTime] DESC;

-- Active blocking chains
SELECT TOP 10 [EventTime], [DatabaseName], [BlockedSpid], [BlockingSpid],
              [BlockedWaitTime], [BlockingSql]
FROM [DBAOps].[trace].[BlockingHistory]
ORDER BY [EventTime] DESC;

-- sa application inventory (remediation list)
SELECT [SourceInstance], [AppName], [ClientHost],
       COUNT(*) AS ConnectionCount,
       MIN([EventTime]) AS FirstSeen, MAX([EventTime]) AS LastSeen
FROM [DBAOps].[audit].[SaLoginHistory]
WHERE [EventType] IN ('sql_batch_completed', 'rpc_completed')
GROUP BY [SourceInstance], [AppName], [ClientHost]
ORDER BY ConnectionCount DESC;
```

## Monitor Schema

Periodic server health snapshots for trend analysis.

`monitor.WaitStatsSnapshot` stores cumulative wait stats from `sys.dm_os_wait_stats` with benign waits excluded (Paul Randal's standard exclusion list). Analyze by computing deltas between two snapshot IDs.

```sql
-- Capture a snapshot manually
EXEC [monitor].[CaptureWaitStats];

-- Top waits in the last snapshot interval
SELECT TOP 10
    curr.[WaitType],
    curr.[WaitTimeMs] - prev.[WaitTimeMs] AS DeltaWaitMs
FROM [monitor].[WaitStatsSnapshot] curr
    INNER JOIN [monitor].[WaitStatsSnapshot] prev
        ON curr.[WaitType] = prev.[WaitType]
       AND prev.[SnapshotId] = curr.[SnapshotId] - 1
WHERE curr.[SnapshotId] = (SELECT MAX([SnapshotId]) FROM [monitor].[WaitStatsSnapshot])
ORDER BY DeltaWaitMs DESC;
```

## Audit Schema

`audit.SchemaChangeHistory` captures DDL object changes (CREATE/ALTER/DROP) across all user databases via the `DBAOps_SchemaChange` XE session. The session writes to a 32 MB ring buffer; `audit.CaptureSchemaChanges` drains it on a schedule (recommended every 5 minutes) and loads new events into the table. Schema names are resolved by catalog lookup against the affected database at capture time, with a sql_text parse fallback for dropped objects.

`audit.SaLoginHistory` captures query activity executed under the `sa` login, fed by the same `DBAOps_SaActivityMonitor` XE session ring buffer.

Deploy `XESessions\DBAOps_SchemaChange.sql` manually against each instance to enable DDL auditing. Deploy `XESessions\DBAOps_SaActivityMonitor.sql` to enable sa activity capture.

The legacy DDL trigger (`Triggers\trg_SchemaChangeCapture.sql`) is still available as an alternative for environments where XE sessions cannot be used. It captures DDL and permission events via `EVENTDATA()` and writes to the same `audit.SchemaChangeHistory` table — note that the trigger-based columns differ from the XE-based schema (the table was redesigned for the XE approach).

```sql
-- Recent DDL changes
SELECT TOP 20
    [CapturedAt], [EventName], [DatabaseName], [SchemaName],
    [ObjectName], [ObjectType], [LoginName], [SqlText]
FROM [DBAOps].[audit].[SchemaChangeHistory]
ORDER BY [CapturedAt] DESC;

-- Objects with unresolved schema names (review these)
SELECT [EventTime], [EventName], [DatabaseName], [ObjectName], [SqlText]
FROM [DBAOps].[audit].[SchemaChangeHistory]
WHERE [SchemaResolutionMethod] = 'unresolved'
ORDER BY [EventTime] DESC;
```

## dbo Utility Procedures

19 read-only diagnostic procedures that query DMVs and system catalogs. No DBAOps table dependencies — they can be executed against any instance. Several accept `@Database` as `USER_DATABASES`, `ALL_DATABASES`, or a specific database name.

| Procedure | Purpose |
|-----------|---------|
| `FindServerString` | Search SQL modules, Agent job steps, and linked servers for a string |
| `GetBackupStatus` | Last backup date per database, overdue flag |
| `GetBlockingSession` | Active blocking chains with SQL text |
| `GetConnectionSummary` | Session counts grouped by database, login, host |
| `GetFailedJob` | Agent jobs that failed within the last N hours |
| `GetIndexFragmentation` | Fragmented indexes above threshold (SAMPLED mode) |
| `GetLogSpaceUsage` | Transaction log size and percent used |
| `GetLongRunningJob` | Jobs running longer than N× their average duration |
| `GetLongRunningQuery` | Active requests exceeding elapsed seconds threshold |
| `GetMissingIndex` | Missing index recommendations from plan cache |
| `GetOpenTransaction` | Sessions with open transactions, including sleeping |
| `GetReplicationStatus` | Distribution agent status (run on distributor) |
| `GetSqlLoginAudit` | Password policy compliance, blank/weak passwords |
| `GetSysadminMembers` | High-privilege role members and SA account status |
| `GetTempdbConfig` | TempDB file configuration and autogrowth analysis |
| `GetTempdbContention` | PAGELATCH waits on TempDB allocation pages |
| `GetTopQuery` | Top queries by CPU, logical reads, or logical writes |
| `GetUnusedIndex` | Non-clustered indexes with zero reads since last restart |
| `GetVersionStoreUsage` | Version store space per database, snapshot isolation state |

## Deployment Templates

`Templates\` contains two templates for different deployment scenarios:

**`DataUpdate_Script_Template.sql`** — data changes that can't be rolled back from source control. Provides rollback data capture via `deploy.RollbackManifest` and run-once idempotency via `deploy.RunOnceManifest`. Use for one-time data fixes, backfills, and migrations.

**`StoredProcedure_Script_Template.sql`** — stored procedure deployments using `CREATE OR ALTER`. Inherently idempotent; rollback is deploying the previous version from Git. Includes a diagnostic header/footer.

## Run-Once System

Data update scripts are self-guarding. On startup the script checks `deploy.RunOnceManifest` — if a row with `Status = 'Success'` exists for that script name, execution is skipped. Each environment (Dev, Test, Prod) has its own DBAOps instance so the same script runs once per environment automatically.

```
Script starts
  → Check RunOnceManifest (already succeeded? → skip)
  → Check open transactions
  → Register in RollbackManifest
  → Capture rollback data (SELECT INTO deploy.RB_<ManifestId>_<TableName>)
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

```sql
-- What has run on this server?
SELECT * FROM [DBAOps].[deploy].[RunOnceManifest] ORDER BY [ExecutedAt] DESC;

-- Would a script run or skip?
SELECT * FROM [DBAOps].[deploy].[RunOnceManifest]
WHERE [ScriptName] = 'DataUpdate_PBI4530_FixOrphanedAccounts.sql';
```

## Rollback System

Before applying a data change, scripts capture the before-image via `SELECT INTO` to a table named `deploy.RB_<ManifestId>_<TableName>` and register in `deploy.RollbackManifest`. Even days later, the manifest points you to the exact snapshot table.

```
Active → Expired → Archived (table dropped)
```

```sql
-- All active rollback entries
SELECT * FROM [DBAOps].[deploy].[RollbackManifest] WHERE [Status] = 'Active';

-- Everything for a specific ticket
SELECT * FROM [DBAOps].[deploy].[RollbackManifest] WHERE [Ticket] = 'PBI-12345';
```

## Cleanup Procedures

All cleanup procs support `@WhatIf = 1` to preview what would be removed. Schedule as SQL Agent job steps.

| Proc | Schema | Default Retention | Notes |
|------|--------|-------------------|-------|
| `CleanupRollbackData` | `deploy` | 30 days + 14-day grace | Two-phase: expire then drop data tables |
| `CleanupRunOnceManifest` | `deploy` | 90 days (Failed), 365 days (Success) | Pass `-1` for indefinite Success retention |
| `CleanupDeadlockHistory` | `trace` | 90 days | |
| `CleanupBlockingHistory` | `trace` | 90 days | |
| `CleanupRpcExecutionHistory` | `trace` | 90 days | Batched 5,000-row deletes |
| `CleanupSaActivity` | `trace` | 90 days | Legacy file-target pipeline |
| `CleanupWaitStats` | `monitor` | 30 days | |
| `CleanupSaActivity` | `audit` | 90 days | Ring buffer pipeline |
| `CleanupSchemaChanges` | `audit` | 90 days | |

```sql
-- Preview any cleanup before running
EXEC [deploy].[CleanupRollbackData]          @WhatIf = 1;
EXEC [deploy].[CleanupRunOnceManifest]       @WhatIf = 1;
EXEC [trace].[CleanupDeadlockHistory]        @WhatIf = 1;
EXEC [trace].[CleanupBlockingHistory]        @WhatIf = 1;
EXEC [trace].[CleanupSaActivity]             @WhatIf = 1;
EXEC [monitor].[CleanupWaitStats]            @WhatIf = 1;
EXEC [audit].[CleanupSaActivity]             @WhatIf = 1;
EXEC [audit].[CleanupSchemaChanges]          @WhatIf = 1;
```

## CI/CD Integration

The `DataUpdate_Script_Template.sql` includes a `@DeploymentId` variable for pipeline injection:

- **Azure DevOps**: `$(Build.BuildId)`, `PR-$(System.PullRequest.PullRequestId)`
- **GitHub Actions**: `${{ github.run_id }}`, `PR-${{ github.event.pull_request.number }}`
- **Jenkins**: `${BUILD_NUMBER}`, `${CHANGE_ID}`

`Samples\azure-pipelines-sample.yml` demonstrates the full Build → Dev → Test → Prod flow with dacpac deployment and self-guarding RunOnce script execution.

## Cloud Compatibility

- **Azure SQL Database**: Contained by default. Setup scripts work as-is (skip `sp_configure` and `CONTAINMENT` settings).
- **AWS RDS for SQL Server**: Supports `PARTIAL` containment. Run setup scripts normally.
- **On-premises**: Run setup scripts in order. `contained database authentication` is enabled automatically by `01_CreateDatabase.sql`.

## Customization

The data update template uses `@UtilityDB` defaulting to `DBAOps`. To use a different database name, change this variable — no other modifications needed.
