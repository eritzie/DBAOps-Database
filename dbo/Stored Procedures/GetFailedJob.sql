USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns Agent jobs that completed with a failed status within the last @HoursBack
    hours, with run date, duration, and error message.

Parameters:
    @HoursBack   as INT   Hours of history to search. Default: 24.

Usage Example:
    EXEC [dbo].[GetFailedJob] @HoursBack = 48;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetFailedJob]
    @HoursBack int = 24
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
         j.name                              AS JobName
        ,msdb.dbo.agent_datetime(
            h.run_date, h.run_time)          AS RunDate   -- converts integer run_date/run_time to datetime
        ,h.run_duration                      AS DurationHHMMSS
        ,h.message                           AS ErrorMessage
    FROM msdb.dbo.sysjobhistory              h
    JOIN msdb.dbo.sysjobs                    j  ON h.job_id = j.job_id
    WHERE h.run_status = 0                   -- 0 = Failed
      AND h.step_id   = 0                    -- step_id 0 = job-level outcome row; avoids duplicating per step
      AND msdb.dbo.agent_datetime(h.run_date, h.run_time)
            >= DATEADD(HOUR, -@HoursBack, SYSUTCDATETIME())
    ORDER BY RunDate DESC;
END
