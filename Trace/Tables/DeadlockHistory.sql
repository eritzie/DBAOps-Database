/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Stores deadlock events extracted from the system_health XE session ring buffer.
    Each row contains the full deadlock graph XML for post-incident analysis.
    Populated by trace.CaptureDeadlocks.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[trace].[DeadlockHistory]', 'U') IS NULL
BEGIN

    CREATE TABLE [trace].[DeadlockHistory] (
        [DeadlockId]    INT            IDENTITY (1, 1) NOT NULL,
        [EventTime]     DATETIME2 (3)  NOT NULL,
        [DatabaseName]  NVARCHAR (128) NULL,
        [VictimProcess] NVARCHAR (128) NULL,
        [DeadlockGraph] XML            NOT NULL,
        [CapturedAt]    DATETIME2 (0)  CONSTRAINT [DF_DeadlockHistory_CapturedAt] DEFAULT (sysutcdatetime()) NOT NULL,
        CONSTRAINT [PK_DeadlockHistory] PRIMARY KEY CLUSTERED ([DeadlockId] ASC)
    );

    CREATE NONCLUSTERED INDEX [IX_DeadlockHistory_EventTime]
        ON [trace].[DeadlockHistory]([EventTime] DESC);

    CREATE NONCLUSTERED INDEX [IX_DeadlockHistory_DatabaseName]
        ON [trace].[DeadlockHistory]([DatabaseName] ASC) WHERE ([DatabaseName] IS NOT NULL);

END
GO
