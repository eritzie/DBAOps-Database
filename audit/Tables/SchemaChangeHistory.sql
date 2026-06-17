/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Audit trail for DDL changes (CREATE/ALTER/DROP) and permission changes
    (GRANT/REVOKE/DENY) captured by the trg_SchemaChangeCapture database-scoped trigger.

Schema Notes:
    SourceDatabase stores DB_NAME() at trigger fire time. When the same schema/table are
    deployed to multiple databases, this column identifies which database produced each row
    if rows are ever consolidated into a central store.

    SchemaName is NULLable because the EVENTDATA() XML emits an empty element
    (<SchemaName />) rather than an absent node for database- and schema-level permission
    events. The trigger uses NULLIF to convert empty string to NULL so this column is
    clean for filtering.

    EventDataXml is the authoritative source for all event data. The scalar columns
    capture only Permission[1] and Grantee[1]; statements that grant multiple permissions
    or target multiple grantees in one statement require reprocessing EventDataXml to
    recover the full set (Phase 1 known limitation).

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-17  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[audit].[SchemaChangeHistory]', 'U') IS NULL
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

END
GO
