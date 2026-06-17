/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys the DBAOps_SaActivityMonitor XE session with an async file target. Captures
    sql_batch_completed and rpc_completed events executed under the sa login. Used as an
    interim security control to record what sa is executing while application
    re-credentialing is in progress. Session auto-starts on SQL Server restart
    (STARTUP_STATE = ON).

    Login and logout events are not captured here — they are captured at the server level
    by DBAOps_ServerAudit (SUCCESSFUL_LOGIN_GROUP / FAILED_LOGIN_GROUP), which provides
    tamper-evident, compliance-grade login history for all logins including sa.

    File target path is configured via the :setvar XELogsPath variable — SQLCMD mode
    required (Query > SQLCMD Mode in SSMS). Default path: C:\XEvents\. The SQL Server
    service account needs write access; grant with:
        icacls "C:\XEvents" /grant "NT SERVICE\MSSQL$<instance>:(OI)(CI)F"

    Events are read by the DBAOps - Capture - SaActivity Agent job (recommended: every
    10 minutes) and inserted into DBAOps.trace.SaLoginHistory.

Usage Example:
    -- Enable SQLCMD mode, then run this script.
    -- Verify deployment:
    SELECT [name], [create_time] FROM sys.dm_xe_sessions WHERE [name] = 'DBAOps_SaActivityMonitor';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-05-13  Eric Ritzie (eritzie)            Initial creation
    2026-06-09  Eric Ritzie (eritzie)            Removed login/logout events — now covered
                                                 by DBAOps_ServerAudit server audit
===============================================================================================*/

-- ============================================================================
-- CONFIGURE: Set XE log path for this instance. Must end with a backslash.
--            Requires SQLCMD mode (Query > SQLCMD Mode in SSMS).
-- ============================================================================
:setvar XELogsPath "C:\XEvents\"

-- ============================================================================
-- SESSION: Async File Target (permanent -- STARTUP_STATE = ON)
-- ============================================================================

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions WHERE name = 'DBAOps_SaActivityMonitor'
)
BEGIN
    ALTER EVENT SESSION [DBAOps_SaActivityMonitor] ON SERVER STATE = STOP;
    DROP EVENT SESSION [DBAOps_SaActivityMonitor] ON SERVER;
    PRINT 'Dropped existing DBAOps_SaActivityMonitor session.';
END
GO

CREATE EVENT SESSION [DBAOps_SaActivityMonitor] ON SERVER
ADD EVENT sqlserver.sql_batch_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.server_principal_name,
        sqlserver.sql_text
    )
    WHERE sqlserver.server_principal_name = N'sa'
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.server_principal_name
    )
    WHERE sqlserver.server_principal_name = N'sa'
)
ADD TARGET package0.asynchronous_file_target(
    SET filename           = N'$(XELogsPath)sa_activity.xel',
        max_file_size      = 100,    -- MB per file
        max_rollover_files = 10      -- 1 GB max total
)
WITH (
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    STARTUP_STATE        = ON
);
GO

ALTER EVENT SESSION [DBAOps_SaActivityMonitor] ON SERVER STATE = START;
GO

PRINT 'DBAOps_SaActivityMonitor deployed and started (file target: $(XELogsPath)sa_activity.xel).';
GO

-- ============================================================================
-- VERIFY
-- ============================================================================
SELECT
    s.[name]                     AS SessionName,
    s.[create_time]              AS CreatedAt,
    t.[target_name]              AS TargetType,
    CAST(t.[target_data] AS XML) AS TargetConfig
FROM sys.dm_xe_sessions          s
JOIN sys.dm_xe_session_targets   t ON s.[address] = t.[event_session_address]
WHERE s.[name] = 'DBAOps_SaActivityMonitor';
GO
