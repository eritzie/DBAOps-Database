USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns user sessions with open transactions, including sleeping sessions holding
    locks. Useful for identifying uncommitted transactions blocking other work.

Usage Example:
    EXEC [dbo].[GetOpenTransaction];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetOpenTransaction]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
         s.session_id
        ,s.status                            AS SessionStatus
        ,r.blocking_session_id
        ,s.open_transaction_count
        ,at.transaction_begin_time           AS TranBeginTime
        ,DATEDIFF(SECOND,
            at.transaction_begin_time,
            SYSUTCDATETIME())                AS TranAgeSeconds
        ,DB_NAME(s.database_id)              AS DatabaseName
        ,s.login_name                        AS LoginName
        ,s.host_name                         AS HostName
        ,s.program_name                      AS ProgramName
        ,t.text                              AS SqlText
    FROM sys.dm_exec_sessions                s
    JOIN sys.dm_tran_session_transactions    st ON s.session_id      = st.session_id
    JOIN sys.dm_tran_active_transactions     at ON st.transaction_id = at.transaction_id
    LEFT JOIN sys.dm_exec_requests           r  ON s.session_id      = r.session_id
    -- OUTER APPLY: sleeping sessions have no active request; SqlText will be NULL for those sessions
    OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
    WHERE s.is_user_process = 1
    ORDER BY at.transaction_begin_time ASC;
END
