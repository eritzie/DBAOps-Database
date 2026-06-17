/*
===================================================================================================
DBAOps Database - Setup Script 02: Create Schemas

Description:
    Creates the DBAOps operational schemas by including the individual schema scripts
    from Security\Schema\. Each script uses IF NOT EXISTS so this is safe to re-run.

    deploy   Deployment manifests, rollback data tables, run-once tracking
    trace    Extended Events capture (deadlocks, blocking, RPC, sa activity)
    monitor  Server health snapshots, wait statistics history
    audit    DDL and permission change history (SchemaChangeHistory)
    maint    Reserved for future maintenance objects

Prerequisites:
    - Run 01_CreateDatabase.sql first

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Convert to :r include pattern

===================================================================================================
*/

USE [DBAOps];
GO

:r ..\Security\Schemas\deploy.sql
:r ..\Security\Schemas\trace.sql
:r ..\Security\Schemas\monitor.sql
:r ..\Security\Schemas\audit.sql
:r ..\Security\Schemas\maint.sql

PRINT '***** Schema setup complete.';
GO
