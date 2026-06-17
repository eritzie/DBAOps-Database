/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Takes a cumulative wait stats snapshot from sys.dm_os_wait_stats into
    DBAOps.monitor.WaitStatsSnapshot with benign waits excluded. Purges snapshots
    older than the configured retention period in the same run. Analyze by computing
    deltas between two snapshot IDs.

Schedule:
    None — add schedule appropriate for this instance after deployment.
    Recommended: every 15–30 minutes.

Steps:
    1. Capture wait stats snapshot — inserts one snapshot row per active wait type
    2. Cleanup old snapshots       — purges snapshots older than @RetentionDays (default 30 days)

On Failure:
    Windows Event Log (notify_level_eventlog = 2)
    *** Assign a notification operator before deploying to production ***

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

USE [msdb];
GO

BEGIN TRANSACTION

DECLARE @ReturnCode INT = 0;
DECLARE @JobId      BINARY(16);

-- Ensure category exists
IF NOT EXISTS (
    SELECT 1 FROM msdb.dbo.syscategories
    WHERE [name] = N'Database Maintenance' AND category_class = 1
)
BEGIN
    EXEC @ReturnCode = msdb.dbo.sp_add_category
        @class = N'JOB',
        @type  = N'LOCAL',
        @name  = N'Database Maintenance';
    IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;
END

-- Drop and recreate if exists
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE [name] = N'DBAOps - Capture - WaitStats')
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name               = N'DBAOps - Capture - WaitStats',
        @delete_unused_schedule = 1;
END

EXEC @ReturnCode = msdb.dbo.sp_add_job
    @job_name              = N'DBAOps - Capture - WaitStats',
    @enabled               = 1,
    @notify_level_eventlog = 2,
    @description           = N'Takes a wait stats snapshot from sys.dm_os_wait_stats into DBAOps.monitor.WaitStatsSnapshot and purges snapshots older than 30 days.',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',    -- *** Transfer to DBA service account before production deployment ***
    @job_id                = @JobId OUTPUT;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Step 1: Capture
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id              = @JobId,
    @step_id             = 1,
    @step_name           = N'Capture wait stats snapshot',
    @subsystem           = N'TSQL',
    @command             = N'EXEC [monitor].[CaptureWaitStats];',
    @database_name       = N'DBAOps',
    @on_success_action   = 3,   -- Go to next step
    @on_fail_action      = 2;   -- Quit with failure
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Step 2: Cleanup
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id              = @JobId,
    @step_id             = 2,
    @step_name           = N'Cleanup old snapshots',
    @subsystem           = N'TSQL',
    @command             = N'EXEC [monitor].[CleanupWaitStats] @RetentionDays = 30;',
    @database_name       = N'DBAOps',
    @on_success_action   = 1,   -- Quit with success
    @on_fail_action      = 2;   -- Quit with failure
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_update_job
    @job_id        = @JobId,
    @start_step_id = 1;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- No schedule defined — add one appropriate for this instance after deployment.
-- Recommended: every 15–30 minutes.

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver
    @job_id      = @JobId,
    @server_name = N'(local)';
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

COMMIT TRANSACTION;
GOTO EndSave;

QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION;
EndSave:
GO
