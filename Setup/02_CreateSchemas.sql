/*
===================================================================================================
DBAOps Database - Setup Script 02: Create Schemas

Description:
    Creates operational schemas within DBAOps. Each schema scopes a distinct area
    of DBA operations.

    Schema layout:
        deploy      - Deployment rollback tracking (RollbackManifest, rollback data tables)
        trace       - Extended Events targets, diagnostic log archives
        monitor     - (Future) Server health snapshots, wait stats history, etc.

Prerequisites:
    - Run 01_CreateDatabase.sql first
    - Execute in the context of [DBAOps]

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

-- deploy: Deployment rollback tracking
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'deploy')
BEGIN
    EXEC('CREATE SCHEMA [deploy] AUTHORIZATION [dbo]');
    PRINT '***** Schema [deploy] created.';
END
ELSE
    PRINT '***** Schema [deploy] already exists.';
GO

-- trace: Diagnostic and trace data
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'trace')
BEGIN
    EXEC('CREATE SCHEMA [trace] AUTHORIZATION [dbo]');
    PRINT '***** Schema [trace] created.';
END
ELSE
    PRINT '***** Schema [trace] already exists.';
GO

-- monitor: Future use — server health, wait stats, etc.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE [name] = N'monitor')
BEGIN
    EXEC('CREATE SCHEMA [monitor] AUTHORIZATION [dbo]');
    PRINT '***** Schema [monitor] created.';
END
ELSE
    PRINT '***** Schema [monitor] already exists.';
GO

PRINT '***** Schema setup complete.';
GO