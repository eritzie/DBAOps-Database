USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns currently executing requests that have been running longer than
    @ThresholdSeconds, with elapsed time, SQL text, and blocking status.

Parameters:
    @ThresholdSeconds   as INT   Minimum elapsed seconds to include. Default: 5.

Usage Example:
    EXEC [dbo].[GetLongRunningQuery] @ThresholdSeconds = 30;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetLongRunningQuery]
    @ThresholdSeconds int = 5
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
         r.session_id
        ,r.blocking_session_id
        ,r.status
        ,r.wait_type
        ,r.wait_time                         AS WaitTimeMs
        ,r.total_elapsed_time / 1000         AS ElapsedSeconds   -- total_elapsed_time is milliseconds; divide by 1000 for seconds
        ,DB_NAME(r.database_id)              AS DatabaseName
        ,s.login_name                        AS LoginName
        ,s.host_name                         AS HostName
        ,s.program_name                      AS ProgramName
        ,t.text                              AS SqlText
    FROM sys.dm_exec_requests                r
    JOIN sys.dm_exec_sessions                s  ON r.session_id = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE s.is_user_process = 1
      AND r.total_elapsed_time / 1000 > @ThresholdSeconds
    ORDER BY r.total_elapsed_time DESC;
END
