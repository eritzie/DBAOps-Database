/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Captures deadlock events from the system_health XE session into
    DBAOps.trace.DeadlockHistory. Purges records older than the configured
    retention period in the same run.

Schedule:
    None — add schedule appropriate for this instance after deployment.
    Recommended: every 5 minutes.

Steps:
    1. Capture from system_health — reads ring buffer, deduplicates, inserts new events
    2. Cleanup old records        — purges rows older than @RetentionDays (default 90 days)

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
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE [name] = N'DBAOps - Capture - Deadlocks')
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name               = N'DBAOps - Capture - Deadlocks',
        @delete_unused_schedule = 1;
END

EXEC @ReturnCode = msdb.dbo.sp_add_job
    @job_name              = N'DBAOps - Capture - Deadlocks',
    @enabled               = 1,
    @notify_level_eventlog = 2,
    @description           = N'Captures deadlock events from system_health into DBAOps.trace.DeadlockHistory and purges records older than 90 days.',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',    -- *** Transfer to DBA service account before production deployment ***
    @job_id                = @JobId OUTPUT;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Step 1: Capture
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id              = @JobId,
    @step_id             = 1,
    @step_name           = N'Capture from system_health',
    @subsystem           = N'TSQL',
    @command             = N'EXEC [trace].[CaptureDeadlocks];',
    @database_name       = N'DBAOps',
    @on_success_action   = 3,   -- Go to next step
    @on_fail_action      = 2;   -- Quit with failure
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- Step 2: Cleanup
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep
    @job_id              = @JobId,
    @step_id             = 2,
    @step_name           = N'Cleanup old records',
    @subsystem           = N'TSQL',
    @command             = N'EXEC [trace].[CleanupDeadlockHistory] @RetentionDays = 90;',
    @database_name       = N'DBAOps',
    @on_success_action   = 1,   -- Quit with success
    @on_fail_action      = 2;   -- Quit with failure
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

EXEC @ReturnCode = msdb.dbo.sp_update_job
    @job_id        = @JobId,
    @start_step_id = 1;
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback;

-- No schedule defined — add one appropriate for this instance after deployment.
-- Recommended: every 5 minutes.

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
