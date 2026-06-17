/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Stores blocked process events extracted from the DBAOps_BlockedProcess XE session
    ring buffer. Each row captures one blocked_process_report event, including both the
    blocked and blocking process details. Populated by trace.CaptureBlockingHistory.

Schema Notes:
    BlockingSql may be empty or show the last executed statement rather than an active one
    when the blocking process is a sleeping session holding an open transaction. This is a
    known limitation of the blocked_process_report event, not a capture defect.

    BlockingGraph stores the full raw blocked_process_report XML for drill-down queries.
    All other columns are cracked from it at capture time for query performance.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[trace].[BlockingHistory]', 'U') IS NULL
BEGIN

    CREATE TABLE [trace].[BlockingHistory] (
        [BlockingId]      INT            IDENTITY (1, 1) NOT NULL,
        [EventTime]       DATETIME2 (3)                  NOT NULL,
        [DatabaseName]    NVARCHAR (128)                 NULL,
        [BlockedSpid]     SMALLINT                       NULL,
        [BlockedLogin]    NVARCHAR (128)                 NULL,
        [BlockedHost]     NVARCHAR (128)                 NULL,
        [BlockedWaitTime] INT                            NULL,   -- milliseconds
        [BlockedSql]      NVARCHAR (MAX)                 NULL,
        [BlockingSpid]    SMALLINT                       NULL,
        [BlockingLogin]   NVARCHAR (128)                 NULL,
        [BlockingHost]    NVARCHAR (128)                 NULL,
        [BlockingStatus]  NVARCHAR (32)                  NULL,
        [BlockingSql]     NVARCHAR (MAX)                 NULL,   -- may be empty; see Schema Notes
        [BlockingGraph]   XML                            NOT NULL,
        [CapturedAt]      DATETIME2 (0)  CONSTRAINT [DF_BlockingHistory_CapturedAt] DEFAULT (SYSUTCDATETIME()) NOT NULL,
        CONSTRAINT [PK_BlockingHistory] PRIMARY KEY CLUSTERED ([BlockingId] ASC)
    );

    CREATE NONCLUSTERED INDEX [IX_BlockingHistory_EventTime]
        ON [trace].[BlockingHistory] ([EventTime] DESC);

    CREATE NONCLUSTERED INDEX [IX_BlockingHistory_DatabaseName]
        ON [trace].[BlockingHistory] ([DatabaseName] ASC) WHERE ([DatabaseName] IS NOT NULL);

    EXEC sys.sp_addextendedproperty
        @name       = N'MS_Description',
        @value      = N'May be empty or show the last executed statement when the blocking process is a sleeping session holding an open transaction. This is a known limitation of the blocked_process_report event.',
        @level0type = N'SCHEMA', @level0name = N'trace',
        @level1type = N'TABLE',  @level1name = N'BlockingHistory',
        @level2type = N'COLUMN', @level2name = N'BlockingSql';

    EXEC sys.sp_addextendedproperty
        @name       = N'MS_Description',
        @value      = N'Full raw blocked_process_report XML. All other columns are cracked from this at capture time.',
        @level0type = N'SCHEMA', @level0name = N'trace',
        @level1type = N'TABLE',  @level1name = N'BlockingHistory',
        @level2type = N'COLUMN', @level2name = N'BlockingGraph';

END
GO
