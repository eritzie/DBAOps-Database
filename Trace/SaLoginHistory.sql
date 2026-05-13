/*
================================================================================
  DBAOps \ Trace \ SaLoginHistory.sql

  Purpose : Persistent audit table for all sa login activity captured by the
            sa_activity_monitor Extended Events session. Populated by
            trace.CaptureSaActivity, scheduled via SQL Agent.

            Part of the sa remediation effort -- this table drives the
            application re-credentialing inventory and provides a forensic
            audit trail for auditors while sa cannot yet be disabled.

  Schema  : trace
  Deploy  : Run after Setup\02_CreateSchemas.sql
  Cleanup : trace.CleanupSaActivity (configurable retention, default 90 days)

  Usage
  -----
    -- All connections as sa in the last 24 hours
    SELECT * FROM [DBAOps].[trace].[SaLoginHistory]
    WHERE [EventTime] >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ORDER BY [EventTime] DESC;

    -- Application inventory -- distinct app + host combinations (remediation list)
    SELECT
        [SourceInstance],
        [AppName],
        [ClientHost],
        COUNT(*)        AS ConnectionCount,
        MIN([EventTime]) AS FirstSeen,
        MAX([EventTime]) AS LastSeen
    FROM [DBAOps].[trace].[SaLoginHistory]
    WHERE [EventType] = 'login'
    GROUP BY [SourceInstance], [AppName], [ClientHost]
    ORDER BY [SourceInstance], ConnectionCount DESC;

    -- All SQL executed as sa on a specific instance
    SELECT [EventTime], [EventType], [AppName], [ClientHost], [DatabaseName], [SqlText]
    FROM [DBAOps].[trace].[SaLoginHistory]
    WHERE [SourceInstance] = 'GP-ENT-NEW\ENT'
    ORDER BY [EventTime] DESC;

  Author  : Eric Ritzie
  Date    : 2026-05-13
  Version : 1.0
================================================================================
*/

USE [DBAOps];
GO

-- == Table ====================================================================

IF OBJECT_ID(N'[trace].[SaLoginHistory]', 'U') IS NULL
BEGIN
    CREATE TABLE [trace].[SaLoginHistory] (
        [Id]             BIGINT          NOT NULL IDENTITY(1,1),
        [CapturedAt]     DATETIME2(3)    NOT NULL CONSTRAINT [DF_SaLoginHistory_CapturedAt] DEFAULT SYSUTCDATETIME(),
        [EventTime]      DATETIME2(3)    NOT NULL,
        [EventType]      VARCHAR(50)     NOT NULL,   -- login | logout | sql_batch_completed | rpc_completed
        [AppName]        NVARCHAR(256)   NULL,
        [ClientHost]     NVARCHAR(256)   NULL,
        [DatabaseName]   NVARCHAR(256)   NULL,
        [SqlText]        NVARCHAR(MAX)   NULL,
        [SourceInstance] NVARCHAR(128)   NOT NULL CONSTRAINT [DF_SaLoginHistory_SourceInstance] DEFAULT @@SERVERNAME,

        CONSTRAINT [PK_SaLoginHistory] PRIMARY KEY CLUSTERED ([Id] ASC)
            WITH (DATA_COMPRESSION = ROW)
    );

    PRINT 'Created table trace.SaLoginHistory.';
END
ELSE
BEGIN
    PRINT 'Table trace.SaLoginHistory already exists -- skipping creation.';
END
GO

-- == Indexes ==================================================================

-- Primary query pattern: recent events, newest first
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE [object_id] = OBJECT_ID(N'[trace].[SaLoginHistory]')
      AND [name]      = N'IX_SaLoginHistory_EventTime'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SaLoginHistory_EventTime]
        ON [trace].[SaLoginHistory] ([EventTime] DESC)
        INCLUDE ([EventType], [AppName], [ClientHost], [SourceInstance]);

    PRINT 'Created index IX_SaLoginHistory_EventTime.';
END
GO

-- Application inventory / remediation list query pattern
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE [object_id] = OBJECT_ID(N'[trace].[SaLoginHistory]')
      AND [name]      = N'IX_SaLoginHistory_AppInventory'
)
BEGIN
    CREATE NONCLUSTERED INDEX [IX_SaLoginHistory_AppInventory]
        ON [trace].[SaLoginHistory] ([SourceInstance] ASC, [AppName] ASC, [ClientHost] ASC)
        INCLUDE ([EventTime], [EventType]);

    PRINT 'Created index IX_SaLoginHistory_AppInventory.';
END
GO
