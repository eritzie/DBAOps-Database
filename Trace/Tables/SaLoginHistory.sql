/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Stores individual events captured from the DBAOps_SaActivityMonitor XE session. Each row
    represents one login, logout, sql_batch_completed, or rpc_completed event executed
    under the sa login. Populated by trace.CaptureSaActivity.

Schema Notes:
    SourceInstance defaults to @@servername to support potential multi-instance aggregation.
    IX_SaLoginHistory_AppInventory is the primary analytical index — supports identifying
    which applications and hosts connect as sa, grouped by instance.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[trace].[SaLoginHistory]', 'U') IS NULL
BEGIN

    CREATE TABLE [trace].[SaLoginHistory] (
        [Id]             BIGINT         IDENTITY (1, 1) NOT NULL,
        [CapturedAt]     DATETIME2 (3)  CONSTRAINT [DF_SaLoginHistory_CapturedAt] DEFAULT (sysutcdatetime()) NOT NULL,
        [EventTime]      DATETIME2 (3)  NOT NULL,
        [EventType]      VARCHAR (50)   NOT NULL,
        [AppName]        NVARCHAR (256) NULL,
        [ClientHost]     NVARCHAR (256) NULL,
        [DatabaseName]   NVARCHAR (256) NULL,
        [SqlText]        NVARCHAR (MAX) NULL,
        [SourceInstance] NVARCHAR (128) CONSTRAINT [DF_SaLoginHistory_SourceInstance] DEFAULT (@@servername) NOT NULL,
        CONSTRAINT [PK_SaLoginHistory] PRIMARY KEY CLUSTERED ([Id] ASC) WITH (DATA_COMPRESSION = ROW)
    );

    CREATE NONCLUSTERED INDEX [IX_SaLoginHistory_AppInventory]
        ON [trace].[SaLoginHistory]([SourceInstance] ASC, [AppName] ASC, [ClientHost] ASC)
        INCLUDE([EventTime], [EventType]);

    CREATE NONCLUSTERED INDEX [IX_SaLoginHistory_EventTime]
        ON [trace].[SaLoginHistory]([EventTime] DESC)
        INCLUDE([EventType], [AppName], [ClientHost], [SourceInstance]);

END
GO
