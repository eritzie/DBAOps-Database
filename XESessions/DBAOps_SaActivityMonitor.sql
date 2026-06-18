/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys the DBAOps_SaActivityMonitor XE session. Captures sql_batch_completed and
    rpc_completed events executed under the sa login. Used as an interim security control
    to record what sa is executing while application re-credentialing is in progress.
    Session auto-starts on SQL Server restart (STARTUP_STATE = ON).

    Login and logout events are not captured here — they are captured at the server level
    by DBAOps_ServerAudit (SUCCESSFUL_LOGIN_GROUP / FAILED_LOGIN_GROUP), which provides
    tamper-evident, compliance-grade login history for all logins including sa.

    Targets:
      Ring buffer (always)  — 32 MB in-memory buffer, read by audit.CaptureSaActivity
                              on a schedule (recommended: every 5 minutes). Events are
                              stored in audit.SaLoginHistory. Buffer wraps on overflow;
                              drain before SQL Server restart to avoid event loss.

      File target (optional) — Uncomment the ADD TARGET block below to also write events
                              to a persistent .xel file. Required if using the legacy
                              trace.CaptureSaActivity proc (file-based reader). File path
                              is set via :setvar XELogsPath — SQLCMD mode required.

Usage Example:
    -- Ring buffer only (default): enable SQLCMD mode is not required.
    -- File target enabled:        enable SQLCMD mode (Query > SQLCMD Mode in SSMS) first.
    -- Verify deployment:
    SELECT [name], [create_time] FROM sys.dm_xe_sessions WHERE [name] = 'DBAOps_SaActivityMonitor';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-05-13  Eric Ritzie (eritzie)            Initial creation
    2026-06-09  Eric Ritzie (eritzie)            Removed login/logout events — now covered
                                                 by DBAOps_ServerAudit server audit
    2026-06-18  Eric Ritzie (eritzie)            Ring buffer added as primary target;
                                                 file target made optional
===============================================================================================*/

-- ============================================================================
-- SESSION
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
ADD EVENT sqlserver.sql_batch_completed
(
    ACTION
    (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.server_principal_name,
        sqlserver.sql_text
    )
    WHERE sqlserver.server_principal_name = N'sa'
),
ADD EVENT sqlserver.rpc_completed
(
    ACTION
    (
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.database_name,
        sqlserver.server_principal_name
    )
    WHERE sqlserver.server_principal_name = N'sa'
)
ADD TARGET package0.ring_buffer
(
    SET max_memory = 32768   -- 32 MB; drain via audit.CaptureSaActivity every 5 minutes
)
-- Optional: uncomment to also write events to a persistent file.
-- Requires SQLCMD mode (Query > SQLCMD Mode in SSMS). Needed only if using
-- trace.CaptureSaActivity (file-based reader).
-- Grant write access first:
--   icacls "C:\XEvents" /grant "NT SERVICE\MSSQL$<instance>:(OI)(CI)F"
--
-- Uncomment the three lines below AND the ADD TARGET block:
-- :setvar XELogsPath "C:\XEvents\"
--
-- ,ADD TARGET package0.asynchronous_file_target
-- (
--     SET filename           = N'$(XELogsPath)sa_activity.xel',
--         max_file_size      = 100,    -- MB per file
--         max_rollover_files = 10      -- 1 GB max total
-- )
WITH
(
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    STARTUP_STATE        = ON
);
GO

ALTER EVENT SESSION [DBAOps_SaActivityMonitor] ON SERVER STATE = START;
GO

PRINT 'DBAOps_SaActivityMonitor deployed and started (ring buffer target).';
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
