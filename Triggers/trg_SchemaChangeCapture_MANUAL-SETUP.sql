/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Standalone deployment script for DDL and permission change audit objects.
    Run against each target database to deploy:
      1. audit schema
      2. audit.SchemaChangeHistory table
      3. trg_SchemaChangeCapture database-scoped DDL trigger

    Idempotent: schema and table are created only if absent; the trigger is dropped
    and recreated so the definition is always current after each run.

    This script is NOT part of the DBAOps dacpac. Run it manually against each
    target database using a login with db_owner or ddladmin rights.

Usage Example:
    -- Connect to the target database, then execute this script.
    -- Do not run against vendor databases without completing
    -- Phase 2 (cross-DB write, certificate signing, dr_AuditWriter role).

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-17  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

SET NOCOUNT ON;
GO

-- ============================================================
-- 1. audit schema
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'audit')
BEGIN
    EXEC sp_executesql N'CREATE SCHEMA [audit] AUTHORIZATION [dbo]';
    PRINT 'Created schema: audit';
END;
ELSE
    PRINT 'Schema audit already exists — skipped.';
GO

-- ============================================================
-- 2. audit.SchemaChangeHistory table
-- ============================================================
IF NOT EXISTS (
    SELECT 1
    FROM   sys.tables  t
    JOIN   sys.schemas s ON s.schema_id = t.schema_id
    WHERE  s.name = N'audit'
      AND  t.name = N'SchemaChangeHistory'
)
BEGIN
    CREATE TABLE [audit].[SchemaChangeHistory]
    (
        [EventId]        bigint        NOT NULL  IDENTITY(1,1),
        [CapturedAt]     datetime2(3)  NOT NULL  CONSTRAINT [DF_SchemaChangeHistory_CapturedAt] DEFAULT SYSDATETIME(),
        [EventType]      varchar(100)  NOT NULL,
        [PostTime]       datetime2(3)  NOT NULL,
        [DatabaseName]   sysname       NOT NULL,
        [SchemaName]     sysname       NULL,
        [ObjectName]     sysname       NULL,
        [ObjectType]     varchar(100)  NULL,
        [LoginName]      sysname       NOT NULL,
        [UserName]       sysname       NOT NULL,
        [PermissionType] varchar(100)  NULL,
        [Grantee]        sysname       NULL,
        [Grantor]        sysname       NULL,
        [TSQLCommand]    nvarchar(max) NULL,
        [EventDataXml]   xml           NOT NULL,
        [SourceDatabase] sysname       NOT NULL,

        CONSTRAINT [PK_SchemaChangeHistory] PRIMARY KEY CLUSTERED ([EventId] ASC)
    );
    PRINT 'Created table: audit.SchemaChangeHistory';
END;
ELSE
    PRINT 'Table audit.SchemaChangeHistory already exists — skipped.';
GO

-- ============================================================
-- 3. trg_SchemaChangeCapture database-scoped DDL trigger
-- ============================================================
IF EXISTS (
    SELECT 1
    FROM   sys.triggers
    WHERE  name              = N'trg_SchemaChangeCapture'
      AND  parent_class_desc = N'DATABASE'
)
BEGIN
    DROP TRIGGER [trg_SchemaChangeCapture] ON DATABASE;
    PRINT 'Dropped existing trigger: trg_SchemaChangeCapture';
END;
GO

CREATE TRIGGER [trg_SchemaChangeCapture]
ON DATABASE
FOR DDL_TABLE_EVENTS,
    DDL_VIEW_EVENTS,
    DDL_PROCEDURE_EVENTS,
    DDL_FUNCTION_EVENTS,
    DDL_TRIGGER_EVENTS,
    DDL_INDEX_EVENTS,
    DDL_SCHEMA_EVENTS,
    DDL_TYPE_EVENTS,
    DDL_SYNONYM_EVENTS,
    GRANT_DATABASE,
    REVOKE_DATABASE,
    DENY_DATABASE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ED xml = EVENTDATA();

    BEGIN TRY
        INSERT INTO [audit].[SchemaChangeHistory]
        (
            [EventType],
            [PostTime],
            [DatabaseName],
            [SchemaName],
            [ObjectName],
            [ObjectType],
            [LoginName],
            [UserName],
            [PermissionType],
            [Grantee],
            [Grantor],
            [TSQLCommand],
            [EventDataXml],
            [SourceDatabase]
        )
        VALUES
        (
            @ED.value('(/EVENT_INSTANCE/EventType)[1]',                    'varchar(100)'),
            @ED.value('(/EVENT_INSTANCE/PostTime)[1]',                     'datetime2(3)'),
            @ED.value('(/EVENT_INSTANCE/DatabaseName)[1]',                 'sysname'),
            NULLIF(@ED.value('(/EVENT_INSTANCE/SchemaName)[1]', 'sysname'), ''),
            @ED.value('(/EVENT_INSTANCE/ObjectName)[1]',                   'sysname'),
            @ED.value('(/EVENT_INSTANCE/ObjectType)[1]',                   'varchar(100)'),
            @ED.value('(/EVENT_INSTANCE/LoginName)[1]',                    'sysname'),
            @ED.value('(/EVENT_INSTANCE/UserName)[1]',                     'sysname'),
            @ED.value('(/EVENT_INSTANCE/Permissions/Permission)[1]',       'varchar(100)'),
            @ED.value('(/EVENT_INSTANCE/Grantees/Grantee)[1]',             'sysname'),
            @ED.value('(/EVENT_INSTANCE/Grantor)[1]',                      'sysname'),
            @ED.value('(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]',      'nvarchar(max)'),
            @ED,
            DB_NAME()
        );
    END TRY
    BEGIN CATCH
        DECLARE @msg nvarchar(2048)
            = N'trg_SchemaChangeCapture: INSERT failed in ' + DB_NAME()
            + N' — ' + ERROR_MESSAGE();
        EXEC sys.xp_logevent 50001, @msg, 'WARNING';
    END CATCH;
END;
GO

PRINT 'Created trigger: trg_SchemaChangeCapture';
GO
