/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database-scoped activity audit XE session (DBAOps_DatabaseActivity). Captures connection
    and query activity for a single target database. Useful for pre-migration or decommission
    audits, app connectivity troubleshooting, and identifying unexpected callers.

    Events captured: sql_batch_starting, rpc_starting, attention, error_reported,
    sql_statement_recompile, dtc_transaction, oledb_error. Each event captures:
    database_name, nt_username, client_hostname, client_app_name, server_principal_name,
    session_id.

    Session is commented out by default. Before running, find the target database_id
    (SELECT database_id FROM sys.databases WHERE name = N'YourDB') and replace each
    <database_id> placeholder with the actual integer. Set STARTUP_STATE = ON only
    after testing volume with the event_counter target first.

Usage Example:
    ALTER EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER STATE = START;
    ALTER EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER STATE = STOP;
    DROP  EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

/*  -- Uncomment to create

-- Drop first if re-creating with different filters
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE [name] = N'DBAOps_DatabaseActivity')
    DROP EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER;
GO

CREATE EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER
ADD EVENT sqlserver.sql_batch_starting
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.rpc_starting
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.attention
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.error_reported
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.sql_statement_recompile
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.dtc_transaction
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
),
ADD EVENT sqlserver.oledb_error
(
    ACTION
    (
        sqlserver.database_name,
        sqlserver.nt_username,
        sqlserver.client_hostname,
        sqlserver.client_app_name,
        sqlserver.server_principal_name,
        sqlserver.session_id
    )
    WHERE database_id = <database_id>          -- TODO: Replace with actual database_id
      AND sqlserver.is_system = 0
)
ADD TARGET package0.event_counter,
ADD TARGET package0.event_file
(
    SET filename = N'DBAOps_DatabaseActivity.xel',
        max_file_size = 100,        -- MB per file
        max_rollover_files = 5
)
WITH
(
    MAX_MEMORY = 4096 KB,
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 10 SECONDS,
    STARTUP_STATE = OFF             -- Do NOT auto-start; this is a diagnostic session
);
GO

PRINT '***** XE Session [DBAOps_DatabaseActivity] created.';
GO

-- To start:  ALTER EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER STATE = START;
-- To stop:   ALTER EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER STATE = STOP;
-- To drop:   DROP EVENT SESSION [DBAOps_DatabaseActivity] ON SERVER;

*/

-------------------------------------------------------------------------------
-- Utility queries (run independently, not part of session creation)
-------------------------------------------------------------------------------

-- Check if the session exists and its state
-- SELECT * FROM sys.server_event_sessions WHERE [name] = N'DBAOps_DatabaseActivity';
-- SELECT * FROM sys.dm_xe_sessions WHERE [name] = N'DBAOps_DatabaseActivity';

-- Check event counts (quick activity gauge before reading full file)
-- SELECT CAST(target_data AS xml) AS event_counts
-- FROM sys.dm_xe_session_targets st
--     INNER JOIN sys.dm_xe_sessions s ON s.[address] = st.event_session_address
-- WHERE s.[name] = N'DBAOps_DatabaseActivity'
--   AND st.target_name = N'event_counter';

-- Read from the log file
-- SELECT *, CAST(event_data AS xml) AS event_data_xml
-- FROM sys.fn_xe_file_target_read_file('DBAOps_DatabaseActivity*.xel', NULL, NULL, NULL);
