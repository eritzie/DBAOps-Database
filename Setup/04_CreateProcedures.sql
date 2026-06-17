/*
===================================================================================================
DBAOps Database - Setup Script 04: Create Stored Procedures

Description:
    Creates all DBAOps stored procedures by including the individual procedure scripts.
    All scripts use CREATE OR ALTER so this is safe to re-run.

    deploy schema:
        CleanupRollbackData      Two-phase lifecycle management for rollback data tables
        CleanupRunOnceManifest   Row-level cleanup for run-once script tracking

    trace schema — deadlock pipeline (system_health, no XE setup required):
        CaptureDeadlocks, CleanupDeadlockHistory

    trace schema — blocking pipeline (requires DBAOps_BlockedProcess XE session):
        CaptureBlockingHistory, CleanupBlockingHistory

    trace schema — RPC execution pipeline (requires DBAOps_SpExecutionCapture XE session):
        CaptureRpcExecutions, CleanupRpcExecutionHistory

    trace schema — sa activity pipeline (requires 08_CreateSaPipeline.sql):
        CaptureSaActivity, CleanupSaActivity

    monitor schema — wait stats pipeline (no XE setup required):
        CaptureWaitStats, CleanupWaitStats

    dbo schema — diagnostic utility procedures (instance-wide, no DBAOps table dependencies):
        FindServerString, GetBackupStatus, GetBlockingSession, GetConnectionSummary,
        GetFailedJob, GetIndexFragmentation, GetLogSpaceUsage, GetLongRunningJob,
        GetLongRunningQuery, GetMissingIndex, GetOpenTransaction, GetReplicationStatus,
        GetSqlLoginAudit, GetSysadminMembers, GetTempdbConfig, GetTempdbContention,
        GetTopQuery, GetUnusedIndex, GetVersionStoreUsage

Prerequisites:
    - Run 01 through 03 first

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Initial creation (split from 06_CreateCoreObjects.sql)

===================================================================================================
*/

USE [DBAOps];
GO

-- -----------------------------------------------------------------------
-- deploy schema
-- -----------------------------------------------------------------------
:r ..\deploy\CleanupRollbackData.sql
:r ..\deploy\CleanupRunonceManifest.sql

-- -----------------------------------------------------------------------
-- trace schema: deadlock pipeline
-- -----------------------------------------------------------------------
:r ..\trace\Stored Procedures\CaptureDeadlocks.sql
:r ..\trace\Stored Procedures\CleanupDeadlockHistory.sql

-- -----------------------------------------------------------------------
-- trace schema: blocking pipeline
-- -----------------------------------------------------------------------
:r ..\trace\Stored Procedures\CaptureBlockingHistory.sql
:r ..\trace\Stored Procedures\CleanupBlockingHistory.sql

-- -----------------------------------------------------------------------
-- trace schema: RPC execution pipeline
-- -----------------------------------------------------------------------
:r ..\trace\Stored Procedures\CaptureRpcExecutions.sql
:r ..\trace\Stored Procedures\CleanupRpcExecutionHistory.sql

-- -----------------------------------------------------------------------
-- trace schema: sa activity pipeline
-- -----------------------------------------------------------------------
:r ..\trace\Stored Procedures\CaptureSaActivity.sql
:r ..\trace\Stored Procedures\CleanupSaActivity.sql

-- -----------------------------------------------------------------------
-- monitor schema: wait stats pipeline
-- -----------------------------------------------------------------------
:r ..\monitor\Stored Procedures\CaptureWaitStats.sql
:r ..\monitor\Stored Procedures\CleanupWaitStats.sql

-- -----------------------------------------------------------------------
-- dbo schema: diagnostic utility procedures
-- -----------------------------------------------------------------------
:r ..\dbo\Stored Procedures\FindServerString.sql
:r ..\dbo\Stored Procedures\GetBackupStatus.sql
:r ..\dbo\Stored Procedures\GetBlockingSession.sql
:r ..\dbo\Stored Procedures\GetConnectionSummary.sql
:r ..\dbo\Stored Procedures\GetFailedJob.sql
:r ..\dbo\Stored Procedures\GetIndexFragmentation.sql
:r ..\dbo\Stored Procedures\GetLogSpaceUsage.sql
:r ..\dbo\Stored Procedures\GetLongRunningJob.sql
:r ..\dbo\Stored Procedures\GetLongRunningQuery.sql
:r ..\dbo\Stored Procedures\GetMissingIndex.sql
:r ..\dbo\Stored Procedures\GetOpenTransaction.sql
:r ..\dbo\Stored Procedures\GetReplicationStatus.sql
:r ..\dbo\Stored Procedures\GetSqlLoginAudit.sql
:r ..\dbo\Stored Procedures\GetSysadminMembers.sql
:r ..\dbo\Stored Procedures\GetTempdbConfig.sql
:r ..\dbo\Stored Procedures\GetTempdbContention.sql
:r ..\dbo\Stored Procedures\GetTopQuery.sql
:r ..\dbo\Stored Procedures\GetUnusedIndex.sql
:r ..\dbo\Stored Procedures\GetVersionStoreUsage.sql

PRINT '***** Stored procedure setup complete.';
GO
