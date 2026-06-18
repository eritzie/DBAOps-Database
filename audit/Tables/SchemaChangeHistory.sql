/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Permanent store for DDL object changes (CREATE/ALTER/DROP) captured by the
    DBAOps_SchemaChange XE session. Populated on a schedule by audit.CaptureSchemaChanges,
    which reads the ring buffer and deduplicates against this table.

Schema Notes:
    EventName matches XE event names: object_created, object_altered, object_deleted.

    TransactionId enables deduplication. Each (EventName, TransactionId) pair is unique
    within the SQL Server process lifetime. The filtered index excludes NULL TransactionId
    rows (possible for some object types) to keep the dedup lookup efficient.

    SchemaResolutionMethod records how SchemaName was populated:
      'catalog'    -- resolved via sys.objects join on ObjectId (most reliable)
      'parsed'     -- extracted from SqlText by pattern match (fallback for dropped objects)
      'unresolved' -- neither method succeeded; SchemaName is NULL

    ObjectId is stored as NULL when the XE payload returns 0. NULLIF(ObjectId, 0) is
    applied during insert in audit.CaptureSchemaChanges.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-18  Eric Ritzie (eritzie)            Replaced Phase 1 DDL trigger design with
                                                  XE ring buffer capture design
===============================================================================================*/

IF OBJECT_ID(N'[audit].[SchemaChangeHistory]', 'U') IS NULL
BEGIN

    CREATE TABLE [audit].[SchemaChangeHistory]
    (
        [EventId]                bigint          NOT NULL  IDENTITY(1,1),
        [CapturedAt]             datetime2(3)    NOT NULL  CONSTRAINT [DF_SchemaChangeHistory_CapturedAt] DEFAULT SYSDATETIME(),
        [EventName]              varchar(50)     NOT NULL,
        [EventTime]              datetime2(7)    NOT NULL,
        [TransactionId]          bigint          NULL,
        [DatabaseName]           sysname         NOT NULL,
        [ObjectId]               int             NULL,
        [ObjectName]             sysname         NOT NULL,
        [ObjectType]             varchar(30)     NOT NULL,
        [SchemaName]             sysname         NULL,
        [SchemaResolutionMethod] varchar(20)     NULL,
        [LoginName]              sysname         NULL,
        [ClientHost]             nvarchar(128)   NULL,
        [AppName]                nvarchar(128)   NULL,
        [SqlText]                nvarchar(max)   NULL,

        CONSTRAINT [PK_SchemaChangeHistory] PRIMARY KEY CLUSTERED ([EventId] ASC)
    );

    CREATE NONCLUSTERED INDEX [IX_SchemaChangeHistory_EventTime]
        ON [audit].[SchemaChangeHistory] ([EventTime] ASC);

    CREATE NONCLUSTERED INDEX [IX_SchemaChangeHistory_TransactionId]
        ON [audit].[SchemaChangeHistory] ([EventName], [TransactionId])
        WHERE [TransactionId] IS NOT NULL;

END
GO
