USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns active user session counts grouped by database, login, host, program, and
    status. Optional filters narrow results before grouping.

Parameters:
    @Database   as NVARCHAR(128)   Filter by database name. NULL returns all databases.
    @Login      as NVARCHAR(128)   Filter by login name. NULL returns all logins.
    @HostName   as NVARCHAR(128)   Filter by host name. NULL returns all hosts.

Usage Example:
    EXEC [dbo].[GetConnectionSummary] @Database = N'DBAOps';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetConnectionSummary]
    @Database   nvarchar(128) = NULL,
    @Login      nvarchar(128) = NULL,
    @HostName   nvarchar(128) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
         DB_NAME(s.database_id)             AS DatabaseName
        ,p.name                             AS LoginName
        ,s.host_name                        AS HostName
        ,s.program_name                     AS ProgramName
        ,s.status                           AS SessionStatus
        ,r.status                           AS RequestStatus
        ,r.command
        ,COUNT(*)                           AS ConnectionCount
    FROM sys.dm_exec_sessions               s
    JOIN sys.server_principals              p  ON s.security_id    = p.sid
    LEFT JOIN sys.dm_exec_requests          r  ON s.session_id     = r.session_id
    WHERE s.is_user_process = 1
      AND (@Database IS NULL OR DB_NAME(s.database_id) = @Database)
      AND (@Login    IS NULL OR p.name                 = @Login)
      AND (@HostName IS NULL OR s.host_name            = @HostName)
    GROUP BY
         s.database_id
        ,p.name
        ,s.host_name
        ,s.program_name
        ,s.status
        ,r.status
        ,r.command
    ORDER BY
         DatabaseName
        ,LoginName;
END
