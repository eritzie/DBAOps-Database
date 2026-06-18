# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Deployment

Requires the `dbatools` PowerShell module.

```powershell
# Core deployment
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01

# Core + all Agent jobs
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -CreateAgentJobs

# Non-default XE log path for the sa capture job
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -CreateAgentJobs -XELogsPath 'D:\XEvents\'

# Preview without executing
.\Deploy-DBAOps.ps1 -SqlInstance SQL-DEV-01 -WhatIf
```

`Deploy-DBAOps.ps1` strips SQLCMD `:setvar` lines before execution and substitutes `$(XELogsPath)` with the `-XELogsPath` parameter value (default `C:\XEvents\`). It does **not** deploy XE sessions, Security objects, ServerAudit specs, Triggers, or dbo utility procedures — those are all manual.

Install Ola Hallengren's Maintenance Solution separately:

```powershell
Install-DbaMaintenanceSolution -SqlInstance SQL-DEV-01 -Database DBAOps -InstallJobs -LogToTable -CleanupTime 168
```

## Architecture

DBAOps is a SQL Server database that acts as an operational hub for DBA tooling. Objects are organized by schema:

| Schema | Purpose |
|--------|---------|
| `deploy` | Run-once manifest, rollback manifest, and rollback data tables |
| `trace` | Deadlock, blocking, RPC execution, and sa login event capture |
| `monitor` | Cumulative wait statistics snapshots |
| `dbo` | Instance-diagnostic utility procedures (no DBAOps table dependencies) |
| `audit` | DDL change history (XE ring buffer) and sa login event capture |
| `maint` | Reserved for future maintenance objects |

## Directory Layout

Schema-bearing directories (`trace/`, `monitor/`, `deploy/`, `dbo/`, `audit/`) each have `Tables/` and `Stored Procedures/` subdirectories. Top-level directories:

```
AgentJobs/      SQL Agent job creation scripts (standalone; run manually after XE sessions are deployed)
XESessions/     Extended Events session definitions (manual deploy only)
ServerAudit/    Server audit and database audit spec scripts (manual deploy only)
Triggers/       trg_SchemaChangeCapture DDL trigger (manual, per-database — legacy alternative to XE pipeline)
Security/       Schema and role idempotent creation scripts (manual deploy only)
Setup/          Bootstrap scripts run by Deploy-DBAOps.ps1 in order (01–07 core; 08 Agent jobs; 09 XE sessions manual)
Templates/      DataUpdate and StoredProcedure deployment templates for application teams
Samples/        CI/CD pipeline examples
```

## SQL File Conventions

### Comment header

Every file uses a 95-`=` header where `/*` and the opening `=` run are on the same line, and the closing `=` run and `*/` are on the same line:

```sql
/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    ...

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    YYYY-MM-DD  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/
```

### Table files — `*/Tables/*.sql`

The entire body (CREATE TABLE, indexes, extended properties) lives inside one `IF OBJECT_ID(N'[schema].[Table]', 'U') IS NULL BEGIN ... END GO` block. No `GO` separators inside the block.

### Stored procedure files — `*/Stored Procedures/*.sql`

Always open with `USE [DBAOps]; GO` before the comment block. Use `CREATE OR ALTER PROCEDURE`. No trailing `GO` after the closing `END`.

### XE sessions, Agent jobs, ServerAudit, Triggers

As-is deployment scripts with their own idempotency guards. Use `E:\Audit\` → `C:\Audit\` and `E:\XEvents\` → `C:\XEvents\` as the default path convention for this repo. `DBAOps_ServerAudit.sql` uses `:setvar` for its path variable (SQLCMD mode required). `DBAOps_SaActivityMonitor.sql` no longer requires SQLCMD mode by default — the `:setvar` and file target are commented out; uncomment both only when enabling the optional file target.

### Schema files — `Security/Schema/*.sql`

```sql
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'schema_name')
    EXEC sp_executesql N'CREATE SCHEMA [schema_name] AUTHORIZATION [dbo]';
GO
```

### Role files — `Security/Role/*.sql`

```sql
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'role_name' AND type = 'R')
    CREATE ROLE [role_name] AUTHORIZATION [dbo];
GO
```

## Key Patterns

### XE-backed capture pipelines

Six pipelines follow the same shape: XE session (manual deploy) → Capture proc reads buffer/file → Cleanup proc manages retention → Agent job schedules both steps.

| Pipeline | Schema | XE Session | Capture Proc | Agent Job |
|----------|--------|-----------|-------------|-----------|
| Deadlocks | `trace` | `system_health` (built-in) | `trace.CaptureDeadlocks` | `DBAOps-CaptureDeadlocks.sql` |
| Blocking | `trace` | `DBAOps_BlockedProcess` | `trace.CaptureBlockingHistory` | `DBAOps-CaptureBlockingHistory.sql` |
| RPC Execution | `trace` | `DBAOps_SpExecutionCapture` | `trace.CaptureRpcExecutions` | `DBAOps-CaptureRpcExecutions.sql` |
| sa Activity (trace) | `trace` | `DBAOps_SaActivityMonitor` (file target) | `trace.CaptureSaActivity` | `DBAOps-CaptureSaActivity.sql` |
| sa Activity (audit) | `audit` | `DBAOps_SaActivityMonitor` (ring buffer) | `audit.CaptureSaActivity` | — |
| Schema Changes | `audit` | `DBAOps_SchemaChange` (ring buffer) | `audit.CaptureSchemaChanges` | `DBAOps-CaptureSchemaChanges.sql` |

`Deploy-DBAOps.ps1` deploys the deadlock pipeline (table + both procs) as part of core. The other pipelines require their XE session to be running first. The `audit` sa activity pipeline is the successor to the `trace` version — it uses a ring buffer instead of a file target and stores events in `audit.SaLoginHistory`.

### Run-once system

Data update scripts self-guard via `deploy.RunOnceManifest`: on startup, check for `Status = 'Success'` for the script's exact filename. If found, skip. Failed runs are recorded but don't block retries. Deleting a Success row means the script will re-execute on next deployment — use `deploy.CleanupRunOnceManifest @WhatIf = 1` before any manual cleanup.

### Rollback manifest

Before applying a data change, capture the before-image with `SELECT INTO [DBAOps].[deploy].[RB_<ManifestId>_<TableName>]` and register in `deploy.RollbackManifest`. Lifecycle: `Active → Expired → Archived`. `deploy.CleanupRollbackData` runs a two-phase cleanup: expire first, then drop data tables after a grace period, so rollback data is always available until explicitly expired.

### dbo utility procedures

The 19 procedures in `dbo/Stored Procedures/` query only DMVs and system catalogs — no DBAOps tables. Several accept `@Database` as `USER_DATABASES`, `ALL_DATABASES`, or a specific database name (Ola Hallengren-style targeting). They can be executed against any SQL Server instance.

## README Status

`README.md` reflects the current schema-based layout. Treat this file as authoritative for any behavioral or deployment details not covered there.
