/*
===================================================================================================
DBAOps Database - Setup Script 03: Create Tables

Description:
    Creates all DBAOps tables by including the individual table scripts. Each script
    uses IF OBJECT_ID IS NULL so this is safe to re-run.

    deploy schema:
        RollbackManifest     Central registry of rollback data captures
        RunOnceManifest      Registry and guard for run-once deployment scripts

    trace schema:
        DeadlockHistory      Deadlock graphs from system_health XE ring buffer
        BlockingHistory      Blocked process events from DBAOps_BlockedProcess XE session
        RpcExecutionHistory  Stored procedure execution detail from DBAOps_SpExecutionCapture
        SaLoginHistory       sa login events from DBAOps_SaActivityMonitor XE file target

    monitor schema:
        WaitStatsSnapshot    Cumulative wait statistics snapshots from sys.dm_os_wait_stats

    audit schema:
        SchemaChangeHistory  DDL and permission change events from trg_SchemaChangeCapture

Prerequisites:
    - Run 01_CreateDatabase.sql and 02_CreateSchemas.sql first

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Convert to :r include pattern; split deploy tables to
                                deploy\Tables\ and added all schema tables

===================================================================================================
*/

USE [DBAOps];
GO

-- deploy schema
:r ..\deploy\Tables\RollbackManifest.sql
:r ..\deploy\Tables\RunOnceManifest.sql

-- trace schema
:r ..\trace\Tables\DeadlockHistory.sql
:r ..\trace\Tables\BlockingHistory.sql
:r ..\trace\Tables\RpcExecutionHistory.sql
:r ..\trace\Tables\SaLoginHistory.sql

-- monitor schema
:r ..\monitor\Tables\WaitStatsSnapshot.sql

-- audit schema
:r ..\audit\Tables\SchemaChangeHistory.sql

PRINT '***** Table setup complete.';
GO
