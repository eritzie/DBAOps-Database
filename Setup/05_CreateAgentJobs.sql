/*
================================================================================
  DBAOps \ Setup \ 05_CreateAgentJobs.sql  (sa Activity Monitor jobs)

  Purpose : Creates the two SQL Agent jobs required for the sa activity
            capture pipeline on each instance:

              1. DBAOps - Capture sa Activity          (every 10 min)
              2. DBAOps - Cleanup sa Activity History  (weekly, Saturday 02:00)

  Run on  : Each instance where sa_activity_monitor.sql has been deployed
            and DBAOps database is present.

  Prerequisites
  -------------
    - DBAOps database deployed (Setup 01-04)
    - trace.SaLoginHistory table created (Trace\SaLoginHistory.sql)
    - trace.CaptureSaActivity created (Trace\CaptureSaActivity.sql)
    - trace.CleanupSaActivity created (Trace\CleanupSaActivity.sql)
    - sa_activity_monitor XE session running (Trace\sa_activity_monitor.sql)

  Customization
  -------------
    - Pass -XELogsPath to Deploy-DBAOps.ps1 if your XE log folder differs from C:\XEvents\
    - Change @RetentionDays in Step 2 (default 90; consider 180 during remediation)
    - Change @owner_login_name once a dedicated service account replaces sa

  Author  : Eric Ritzie
  Date    : 2026-05-13
  Version : 1.0
================================================================================
*/

USE [msdb];
GO

-- ============================================================================
-- JOB 1: Capture sa Activity  (every 10 minutes)
-- ============================================================================

DECLARE @CaptureJobId UNIQUEIDENTIFIER;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE [name] = N'DBAOps - Capture sa Activity')
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name              = N'DBAOps - Capture sa Activity',
        @delete_unused_schedule = 1;
    PRINT 'Dropped existing job: DBAOps - Capture sa Activity';
END

EXEC msdb.dbo.sp_add_job
    @job_name              = N'DBAOps - Capture sa Activity',
    @enabled               = 1,
    @description           = N'Reads the sa_activity_monitor XE file target and inserts new events into DBAOps.trace.SaLoginHistory every 10 minutes. Part of sa remediation -- captures application inventory while sa cannot yet be disabled.',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',    -- *** Transfer to dedicated service account once sa is disabled ***
    @notify_level_eventlog = 2,        -- Log failures to Windows Event Log
    @job_id                = @CaptureJobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id            = @CaptureJobId,
    @step_name         = N'Capture sa XE Events',
    @step_id           = 1,
    @subsystem         = N'TSQL',
    @command           = N'
EXEC [DBAOps].[trace].[CaptureSaActivity]
    @XELogPath = N''$(XELogsPath)sa_activity*.xel'';
',
    @database_name     = N'DBAOps',
    @on_success_action = 1,   -- Quit with success
    @on_fail_action    = 2,   -- Quit with failure
    @retry_attempts    = 2,
    @retry_interval    = 1;

EXEC msdb.dbo.sp_add_jobschedule
    @job_id               = @CaptureJobId,
    @name                 = N'Every 10 Minutes',
    @enabled              = 1,
    @freq_type            = 4,       -- Daily
    @freq_interval        = 1,
    @freq_subday_type     = 4,       -- Minutes
    @freq_subday_interval = 10,
    @active_start_time    = 000000,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @CaptureJobId,
    @server_name = N'(local)';

PRINT 'Created job: DBAOps - Capture sa Activity';
GO


-- ============================================================================
-- JOB 2: Cleanup sa Activity History  (weekly, Saturday 02:00 AM)
-- ============================================================================

DECLARE @CleanupJobId UNIQUEIDENTIFIER;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE [name] = N'DBAOps - Cleanup sa Activity History')
BEGIN
    EXEC msdb.dbo.sp_delete_job
        @job_name              = N'DBAOps - Cleanup sa Activity History',
        @delete_unused_schedule = 1;
    PRINT 'Dropped existing job: DBAOps - Cleanup sa Activity History';
END

EXEC msdb.dbo.sp_add_job
    @job_name              = N'DBAOps - Cleanup sa Activity History',
    @enabled               = 1,
    @description           = N'Purges trace.SaLoginHistory rows older than the configured retention period. Default 90 days; extend to 180 while sa remediation is active.',
    @category_name         = N'Database Maintenance',
    @owner_login_name      = N'sa',    -- *** Transfer to dedicated service account once sa is disabled ***
    @notify_level_eventlog = 2,
    @job_id                = @CleanupJobId OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
    @job_id            = @CleanupJobId,
    @step_name         = N'Purge Old sa Activity Rows',
    @step_id           = 1,
    @subsystem         = N'TSQL',
    @command           = N'
-- Default 90-day retention.
-- While sa remediation is active, consider extending to 180:
-- EXEC [DBAOps].[trace].[CleanupSaActivity] @RetentionDays = 180;
EXEC [DBAOps].[trace].[CleanupSaActivity] @RetentionDays = 90;
',
    @database_name     = N'DBAOps',
    @on_success_action = 1,
    @on_fail_action    = 2,
    @retry_attempts    = 1,
    @retry_interval    = 5;

-- Weekly, Saturday at 02:00 AM
EXEC msdb.dbo.sp_add_jobschedule
    @job_id                 = @CleanupJobId,
    @name                   = N'Weekly Saturday 02:00',
    @enabled                = 1,
    @freq_type              = 8,      -- Weekly
    @freq_interval          = 64,     -- Saturday
    @freq_recurrence_factor = 1,
    @active_start_time      = 020000;

EXEC msdb.dbo.sp_add_jobserver
    @job_id      = @CleanupJobId,
    @server_name = N'(local)';

PRINT 'Created job: DBAOps - Cleanup sa Activity History';
GO


-- ============================================================================
-- VERIFY: Confirm both jobs were created
-- ============================================================================
SELECT
    [name]         AS JobName,
    [enabled]      AS Enabled,
    [description]  AS Description
FROM msdb.dbo.sysjobs
WHERE [name] IN (
    N'DBAOps - Capture sa Activity',
    N'DBAOps - Cleanup sa Activity History'
)
ORDER BY [name];
GO
