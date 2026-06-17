USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns sessions currently experiencing PAGELATCH waits on TempDB allocation pages.
    High counts indicate TempDB file configuration issues.

Usage Example:
    EXEC [dbo].[GetTempdbContention];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetTempdbContention]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
         wt.session_id
        ,wt.exec_context_id
        ,wt.wait_type
        ,wt.wait_duration_ms
        ,wt.resource_description
        ,s.login_name                        AS LoginName
        ,s.host_name                         AS HostName
        ,s.program_name                      AS ProgramName
    FROM sys.dm_os_waiting_tasks             wt
    JOIN sys.dm_exec_sessions                s  ON wt.session_id = s.session_id
    WHERE wt.wait_type LIKE N'PAGELATCH_%'
      AND wt.resource_description LIKE N'2:%'   -- database_id 2 = tempdb
    ORDER BY wt.wait_duration_ms DESC;
END
