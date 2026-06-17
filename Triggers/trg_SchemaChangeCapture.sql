/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys the trg_SchemaChangeCapture database-scoped DDL trigger. Assumes the audit
    schema and audit.SchemaChangeHistory table already exist in the target database.

    The trigger is dropped and recreated so the definition is always current after each run.

    To deploy to a database that does not already have the audit schema and table, use
    Triggers\trg_SchemaChangeCapture_MANUAL-SETUP.sql instead.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-17  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

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
