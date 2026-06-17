USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Reads the DBAOps_SpExecutionCapture XE ring buffer and inserts new events into
    trace.RpcExecutionHistory. Uses MAX(EventTime) as a watermark to avoid inserting
    duplicate rows across consecutive job runs. Events at the exact watermark millisecond
    may occasionally be skipped — acceptable for trending and capacity purposes.

    Run as step 1 of the DBAOps - Capture - RpcExecutions Agent job.
    Recommended schedule: every 30–60 minutes. More frequent runs reduce required
    ring buffer size and the risk of dropped events.

Usage Example:
    EXEC [trace].[CaptureRpcExecutions];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-09  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [trace].[CaptureRpcExecutions]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Watermark DATETIME2(3);

    SELECT @Watermark = ISNULL(MAX([EventTime]), '1900-01-01')
    FROM [trace].[RpcExecutionHistory];

    INSERT INTO [trace].[RpcExecutionHistory] (
        [DbName],
        [SpName],
        [DurationMs],
        [CpuTimeMs],
        [LogicalReads],
        [PhysicalReads],
        [Writes],
        [RowCount],
        [EventTime]
    )
    SELECT
        n.value('(action[@name="database_name"]/value)[1]',  'nvarchar(128)'),
        n.value('(data[@name="object_name"]/value)[1]',      'nvarchar(256)'),
        n.value('(data[@name="duration"]/value)[1]',         'bigint') / 1000,
        n.value('(data[@name="cpu_time"]/value)[1]',         'bigint') / 1000,
        n.value('(data[@name="logical_reads"]/value)[1]',    'bigint'),
        n.value('(data[@name="physical_reads"]/value)[1]',   'bigint'),
        n.value('(data[@name="writes"]/value)[1]',           'bigint'),
        n.value('(data[@name="row_count"]/value)[1]',        'bigint'),
        n.value('(@timestamp)[1]',                           'datetime2(3)')
    FROM (
        SELECT CAST(t.target_data AS XML) AS TargetData
        FROM sys.dm_xe_sessions        AS s
        JOIN sys.dm_xe_session_targets AS t
            ON s.[address] = t.event_session_address
        WHERE s.[name]      = N'DBAOps_SpExecutionCapture'
          AND t.target_name = N'ring_buffer'
    ) AS rb
    CROSS APPLY rb.TargetData.nodes('//RingBufferTarget/event') AS xe(n)
    WHERE n.value('(data[@name="object_name"]/value)[1]', 'nvarchar(256)') <> N''
      AND n.value('(@timestamp)[1]', 'datetime2(3)') > @Watermark;

    PRINT '***** Captured ' + CAST(@@ROWCOUNT AS varchar) + ' new RPC execution event(s).';

END
