/*
================================================================================
  sa Activity Monitor -- Extended Events Session (File Target)
  OutdoorNetwork.com | SQL Server Security Remediation
  Author : Eric Ritzie, Sr. DBA
  Date   : 2026-05-13

  Purpose: Capture all activity performed under the sa login across all
           instances. Used as an interim security control while application
           re-credentialing is in progress.

  Target : Async file target -> DBAOps.trace.SaLoginHistory
           Events are read by trace.CaptureSaActivity (SQL Agent job,
           every 10 minutes) and inserted into the DBAOps database for
           centralized querying and retention management.

  Deployment
  ----------
  Option 1 -- PowerShell (all instances at once):
    .\Deploy-SaActivityMonitor.ps1  (uncomment the Deploy-XESession call)

  Option 2 -- Manual per instance:
    1. Create C:\XELogs\ on the target server (or adjust path below).
    2. Run this script.
    3. Verify: SELECT * FROM sys.dm_xe_sessions WHERE name = 'sa_activity_monitor'
    4. Run Setup\CreateAgentJobs.sql to create the capture and cleanup Agent jobs.

  XELogs folder
  -------------
  Default path: C:\XELogs\
  - Create this folder on each instance before deploying.
  - SQL Server service account needs write access.
  - Grant: icacls "C:\XELogs" /grant "NT SERVICE\MSSQL$<instance>:(OI)(CI)F"
    Adjust service account name per instance (see SQL Server Configuration Manager).

  Files: sa_activity_<timestamp>.xel  (100 MB per file, 10-file rollover = 1 GB max)
================================================================================
*/

-- ============================================================================
-- SESSION: Async File Target (permanent -- STARTUP_STATE = ON)
-- ============================================================================

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions WHERE name = 'sa_activity_monitor'
)
BEGIN
    ALTER EVENT SESSION [sa_activity_monitor] ON SERVER STATE = STOP;
    DROP EVENT SESSION [sa_activity_monitor] ON SERVER;
    PRINT 'Dropped existing sa_activity_monitor session.';
END
GO

CREATE EVENT SESSION [sa_activity_monitor] ON SERVER
ADD EVENT sqlserver.login(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.nt_username,
        sqlserver.server_principal_name,
        sqlserver.sql_text
    )
    WHERE sqlserver.server_principal_name = N'sa'
),
ADD EVENT sqlserver.logout(
    ACTION(
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.server_principal_name
    )
    WHERE sqlserver.server_principal_name = N'sa'
),
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
        sqlserver.server_principal_name,
        sqlserver.statement
    )
    WHERE sqlserver.server_principal_name = N'sa'
)
ADD TARGET package0.asynchronous_file_target(
    SET filename           = N'C:\XELogs\sa_activity.xel',
        max_file_size      = 100,    -- MB per file
        max_rollover_files = 10      -- 1 GB max total
)
WITH (
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    STARTUP_STATE        = ON
);
GO

ALTER EVENT SESSION [sa_activity_monitor] ON SERVER STATE = START;
GO

PRINT 'sa_activity_monitor deployed and started (file target: C:\XELogs\sa_activity.xel).';
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
WHERE s.[name] = 'sa_activity_monitor';
GO
