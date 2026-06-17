/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Stores cumulative wait statistics snapshots from sys.dm_os_wait_stats. Each snapshot
    is one set of rows sharing the same SnapshotId and CapturedAt timestamp. Analyze wait
    trends by computing deltas between two snapshot IDs. Benign and system wait types are
    excluded at capture time by monitor.CaptureWaitStats.

Schema Notes:
    SnapshotId is assigned by CaptureWaitStats as MAX(SnapshotId)+1 rather than IDENTITY,
    so gaps in the sequence indicate failed captures, not missing rows.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[monitor].[WaitStatsSnapshot]', 'U') IS NULL
BEGIN

    CREATE TABLE [monitor].[WaitStatsSnapshot] (
        [SnapshotId]        INT           NOT NULL,
        [CapturedAt]        DATETIME2 (0) NOT NULL,
        [WaitType]          NVARCHAR (60) NOT NULL,
        [WaitingTasksCount] BIGINT        NOT NULL,
        [WaitTimeMs]        BIGINT        NOT NULL,
        [MaxWaitTimeMs]     BIGINT        NOT NULL,
        [SignalWaitTimeMs]  BIGINT        NOT NULL,
        CONSTRAINT [PK_WaitStatsSnapshot] PRIMARY KEY CLUSTERED ([SnapshotId] ASC, [WaitType] ASC)
    );

    CREATE NONCLUSTERED INDEX [IX_WaitStatsSnapshot_CapturedAt]
        ON [monitor].[WaitStatsSnapshot]([CapturedAt] DESC);

END
GO
