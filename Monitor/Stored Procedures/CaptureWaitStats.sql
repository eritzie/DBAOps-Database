USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Inserts one wait stats snapshot into monitor.WaitStatsSnapshot from
    sys.dm_os_wait_stats. Benign and system wait types are excluded. SnapshotId is
    assigned as MAX(SnapshotId)+1 at capture time. Used as step 1 of the
    DBAOps - Capture - WaitStats Agent job.

Usage Example:
    EXEC [monitor].[CaptureWaitStats];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [monitor].[CaptureWaitStats]
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
