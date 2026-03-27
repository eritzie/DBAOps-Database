/*
===================================================================================================
DBAOps Database - Monitor: Wait Stats Snapshots

Description:
    Periodic capture of sys.dm_os_wait_stats for trend analysis. The DMV reports
    cumulative waits since service restart, so meaningful analysis requires computing
    deltas between snapshots.

    Two components:
    1. monitor.WaitStatsSnapshot      — stores raw cumulative snapshots
    2. monitor.usp_CaptureWaitStats   — proc to capture a snapshot (run on a schedule)

    To analyze deltas between two points in time, compare two snapshots:

        SELECT
            curr.WaitType,
            curr.WaitingTasksCount - prev.WaitingTasksCount AS DeltaTasks,
            curr.WaitTimeMs - prev.WaitTimeMs AS DeltaWaitMs,
            curr.SignalWaitTimeMs - prev.SignalWaitTimeMs AS DeltaSignalMs
        FROM monitor.WaitStatsSnapshot curr
            INNER JOIN monitor.WaitStatsSnapshot prev
                ON curr.WaitType = prev.WaitType
                AND prev.SnapshotId = <previous_id>
        WHERE curr.SnapshotId = <current_id>
          AND curr.WaitingTasksCount - prev.WaitingTasksCount > 0
        ORDER BY DeltaWaitMs DESC;

    Common schedule: every 15-30 minutes via SQL Agent. At ~200 wait types per
    snapshot, a 15-minute interval generates roughly 20K rows/day.

Prerequisites:
    - Run Setup scripts 01-02 first
    - Execute in the context of [DBAOps]

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

-------------------------------------------------------------------------------
-- monitor.WaitStatsSnapshot
-------------------------------------------------------------------------------

IF NOT EXISTS (
    SELECT 1
    FROM sys.objects o
        INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id]
    WHERE s.[name] = N'monitor'
      AND o.[name] = N'WaitStatsSnapshot'
      AND o.[type] = 'U'
)
BEGIN

    CREATE TABLE [monitor].[WaitStatsSnapshot]
    (
        [SnapshotId]            int             NOT NULL,       -- Groups all rows from one capture
        [CapturedAt]            datetime2(0)    NOT NULL,
        [WaitType]              nvarchar(60)    NOT NULL,
        [WaitingTasksCount]     bigint          NOT NULL,
        [WaitTimeMs]            bigint          NOT NULL,
        [MaxWaitTimeMs]         bigint          NOT NULL,
        [SignalWaitTimeMs]      bigint          NOT NULL,

        CONSTRAINT [PK_WaitStatsSnapshot] PRIMARY KEY CLUSTERED ([SnapshotId], [WaitType])
    );

    CREATE NONCLUSTERED INDEX [IX_WaitStatsSnapshot_CapturedAt]
        ON [monitor].[WaitStatsSnapshot] ([CapturedAt] DESC);

    PRINT '***** Table [monitor].[WaitStatsSnapshot] created.';

END
ELSE
    PRINT '***** Table [monitor].[WaitStatsSnapshot] already exists.';
GO

-------------------------------------------------------------------------------
-- monitor.usp_CaptureWaitStats
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE [monitor].[usp_CaptureWaitStats]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SnapshotId int;
    DECLARE @Now datetime2(0) = SYSUTCDATETIME();

    -- Get the next snapshot ID
    SELECT @SnapshotId = ISNULL(MAX([SnapshotId]), 0) + 1
    FROM [monitor].[WaitStatsSnapshot];

    -- Exclude well-known benign waits that add noise to analysis.
    -- This list is based on Paul Randal's standard exclusions.
    -- Adjust for your environment as needed.

    INSERT INTO [monitor].[WaitStatsSnapshot]
        ([SnapshotId], [CapturedAt], [WaitType], [WaitingTasksCount], [WaitTimeMs], [MaxWaitTimeMs], [SignalWaitTimeMs])
    SELECT
        @SnapshotId,
        @Now,
        [wait_type],
        [waiting_tasks_count],
        [wait_time_ms],
        [max_wait_time_ms],
        [signal_wait_time_ms]
    FROM sys.dm_os_wait_stats
    WHERE [waiting_tasks_count] > 0
      AND [wait_type] NOT IN
      (
        -- Benign waits — background/idle/system waits that are always present
        N'BROKER_EVENTHANDLER',         N'BROKER_RECEIVE_WAITFOR',
        N'BROKER_TASK_STOP',            N'BROKER_TO_FLUSH',
        N'BROKER_TRANSMITTER',          N'CHECKPOINT_QUEUE',
        N'CHKPT',                       N'CLR_AUTO_EVENT',
        N'CLR_MANUAL_EVENT',            N'CLR_SEMAPHORE',
        N'DBMIRROR_DBM_EVENT',          N'DBMIRROR_EVENTS_QUEUE',
        N'DBMIRROR_WORKER_QUEUE',       N'DBMIRRORING_CMD',
        N'DIRTY_PAGE_POLL',             N'DISPATCHER_QUEUE_SEMAPHORE',
        N'EXECSYNC',                    N'FSAGENT',
        N'FT_IFTS_SCHEDULER_IDLE_WAIT', N'FT_IFTSHC_MUTEX',
        N'HADR_CLUSAPI_CALL',           N'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        N'HADR_LOGCAPTURE_WAIT',        N'HADR_NOTIFICATION_DEQUEUE',
        N'HADR_TIMER_TASK',             N'HADR_WORK_QUEUE',
        N'KSOURCE_WAKEUP',             N'LAZYWRITER_SLEEP',
        N'LOGMGR_QUEUE',               N'MEMORY_ALLOCATION_EXT',
        N'ONDEMAND_TASK_QUEUE',         N'PARALLEL_REDO_DRAIN_WORKER',
        N'PARALLEL_REDO_LOG_CACHE',     N'PARALLEL_REDO_TRAN_LIST',
        N'PARALLEL_REDO_WORKER_SYNC',   N'PARALLEL_REDO_WORKER_WAIT_WORK',
        N'PREEMPTIVE_OS_FLUSHFILEBUFFERS', N'PREEMPTIVE_XE_GETTARGETSTATE',
        N'PVS_PREALLOCATE',            N'PWAIT_ALL_COMPONENTS_INITIALIZED',
        N'PWAIT_DIRECTLOGCONSUMER_GETNEXT', N'QDS_PERSIST_TASK_MAIN_LOOP_SLEEP',
        N'QDS_ASYNC_QUEUE',            N'QDS_CLEANUP_STALE_QUERIES_TASK_MAIN_LOOP_SLEEP',
        N'QDS_SHUTDOWN_QUEUE',          N'REDO_THREAD_PENDING_WORK',
        N'REQUEST_FOR_DEADLOCK_SEARCH', N'RESOURCE_QUEUE',
        N'SERVER_IDLE_CHECK',           N'SLEEP_BPOOL_FLUSH',
        N'SLEEP_DBSTARTUP',            N'SLEEP_DCOMSTARTUP',
        N'SLEEP_MASTERDBREADY',         N'SLEEP_MASTERMDREADY',
        N'SLEEP_MASTERUPGRADED',        N'SLEEP_MSDBSTARTUP',
        N'SLEEP_SYSTEMTASK',            N'SLEEP_TASK',
        N'SLEEP_TEMPDBSTARTUP',         N'SNI_HTTP_ACCEPT',
        N'SOS_WORK_DISPATCHER',         N'SP_SERVER_DIAGNOSTICS_SLEEP',
        N'SQLTRACE_BUFFER_FLUSH',       N'SQLTRACE_INCREMENTAL_FLUSH_SLEEP',
        N'SQLTRACE_WAIT_ENTRIES',       N'VDI_CLIENT_OTHER',
        N'WAIT_FOR_RESULTS',            N'WAITFOR',
        N'WAITFOR_TASKSHUTDOWN',        N'WAIT_XTP_CKPT_CLOSE',
        N'WAIT_XTP_HOST_WAIT',          N'WAIT_XTP_OFFLINE_CKPT_NEW_LOG',
        N'WAIT_XTP_RECOVERY',           N'XE_BUFFERMGR_ALLPROCESSED_EVENT',
        N'XE_DISPATCHER_JOIN',          N'XE_DISPATCHER_WAIT',
        N'XE_TIMER_EVENT'
      );

    PRINT '***** Wait stats snapshot ' + CAST(@SnapshotId AS varchar) + ' captured at ' + CONVERT(varchar, @Now, 120) + '.';
END
GO

PRINT '***** Procedure [monitor].[usp_CaptureWaitStats] created.';
GO