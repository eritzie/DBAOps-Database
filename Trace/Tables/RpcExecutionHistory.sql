/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Stores per-execution detail for stored procedure calls collected from the
    DBAOps_SpExecutionCapture XE ring buffer session. Populated by trace.CaptureRpcExecutions.
    All timestamps stored in UTC; DurationMs and CpuTimeMs converted from XE microseconds
    on insert.

Schema Notes:
    EventTime is the XE event timestamp (UTC). CollectedAt is the insert time.
    IX_RpcExecutionHistory_EventTime supports the watermark lookup in
    CaptureRpcExecutions and the range scan in CleanupRpcExecutionHistory.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-09  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[trace].[RpcExecutionHistory]', 'U') IS NULL
BEGIN

    CREATE TABLE [trace].[RpcExecutionHistory] (
        [Id]            BIGINT          IDENTITY (1, 1)  NOT NULL,
        [DbName]        NVARCHAR (128)                   NOT NULL,
        [SpName]        NVARCHAR (256)                   NOT NULL,
        [DurationMs]    BIGINT                           NOT NULL,
        [CpuTimeMs]     BIGINT                           NOT NULL,
        [LogicalReads]  BIGINT                           NOT NULL,
        [PhysicalReads] BIGINT                           NOT NULL,
        [Writes]        BIGINT                           NOT NULL,
        [RowCount]      BIGINT                           NOT NULL,
        [EventTime]     DATETIME2 (3)                    NOT NULL,
        [CollectedAt]   DATETIME2 (3)                    CONSTRAINT [DF_RpcExecutionHistory_CollectedAt] DEFAULT (SYSUTCDATETIME()) NOT NULL,
        CONSTRAINT [PK_RpcExecutionHistory] PRIMARY KEY CLUSTERED ([Id] ASC)
    );

    CREATE NONCLUSTERED INDEX [IX_RpcExecutionHistory_EventTime]
        ON [trace].[RpcExecutionHistory] ([EventTime] ASC);

END
GO
