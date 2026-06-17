USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns Agent jobs currently running longer than @Multiplier times their average
    successful run duration over the past 30 days.

Parameters:
    @Multiplier   as FLOAT   Duration multiple threshold. Default: 2.0.

Usage Example:
    EXEC [dbo].[GetLongRunningJob] @Multiplier = 3.0;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetLongRunningJob]
    @Multiplier float = 2.0
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH RunningJobs AS (
        SELECT
             ja.job_id
            ,ja.start_execution_date
            ,DATEDIFF(SECOND,
                ja.start_execution_date,
                SYSUTCDATETIME())            AS CurrentSeconds
        FROM msdb.dbo.sysjobactivity         ja
        JOIN (
            -- Most recent activity session per job
            SELECT job_id, MAX(session_id) AS MaxSession
            FROM msdb.dbo.sysjobactivity
            GROUP BY job_id
        ) last ON ja.job_id      = last.job_id
               AND ja.session_id = last.MaxSession
        WHERE ja.start_execution_date IS NOT NULL
          AND ja.stop_execution_date  IS NULL       -- currently running
    ),
    AvgDurations AS (
        SELECT
             job_id
            -- run_duration is stored as HHMMSS integer, not seconds; unpack to seconds
            ,AVG(
                  (run_duration / 10000)         * 3600
                + ((run_duration % 10000) / 100) * 60
                +  (run_duration % 100)
             )                                   AS AvgSeconds
        FROM msdb.dbo.sysjobhistory
        WHERE run_status = 1                 -- Succeeded
          AND step_id    = 0                 -- job-level outcome row
          AND run_date  >= CONVERT(INT,
                FORMAT(DATEADD(DAY, -30, SYSUTCDATETIME()), 'yyyyMMdd'))
        GROUP BY job_id
    )
    SELECT
         j.name                              AS JobName
        ,rj.start_execution_date             AS StartDate
        ,rj.CurrentSeconds                   AS CurrentDurationSeconds
        ,ad.AvgSeconds                       AS AvgDurationSeconds
        ,CAST(rj.CurrentSeconds AS FLOAT)
            / NULLIF(ad.AvgSeconds, 0)       AS DurationMultiple  -- NULLIF guards divide-by-zero
        ,@Multiplier                         AS ThresholdMultiplier
    FROM RunningJobs                         rj
    JOIN msdb.dbo.sysjobs                    j  ON rj.job_id = j.job_id
    JOIN AvgDurations                        ad ON rj.job_id = ad.job_id
    WHERE rj.CurrentSeconds > ad.AvgSeconds * @Multiplier
    ORDER BY DurationMultiple DESC;
END
