USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns all sessions currently blocked or acting as a blocking head, with SQL text
    and wait details. Useful for identifying active blocking chains.

Usage Example:
    EXEC [dbo].[GetBlockingSession];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetBlockingSession]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
         r.session_id                        AS BlockedSpid
        ,r.blocking_session_id               AS BlockingSpid
        ,r.wait_type
        ,r.wait_time                         AS WaitTimeMs
        ,r.status
        ,DB_NAME(r.database_id)              AS DatabaseName
        ,s.login_name                        AS LoginName
        ,s.host_name                         AS HostName
        ,s.program_name                      AS ProgramName
        ,t.text                              AS SqlText
    FROM sys.dm_exec_requests                r
    JOIN sys.dm_exec_sessions                s  ON r.session_id        = s.session_id
    CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE r.blocking_session_id > 0
    ORDER BY r.wait_time DESC;
END
