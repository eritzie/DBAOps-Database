/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Standard XE session definitions for common DBA diagnostic scenarios.
    All sessions are commented out by default — review thresholds and enable as needed.
    These are server-level objects; deploy manually via SSMS, not via dacpac.

    Sessions defined:
    1. DBAOps_BlockedProcess     — blocked process reports (requires blocked process threshold config)
    2. DBAOps_LongRunningQueries — queries exceeding a configurable duration threshold

Usage Example:
    Uncomment the relevant session block, adjust thresholds, and run against the target instance.
    To start:  ALTER EVENT SESSION [DBAOps_BlockedProcess] ON SERVER STATE = START;
    To stop:   ALTER EVENT SESSION [DBAOps_BlockedProcess] ON SERVER STATE = STOP;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

-------------------------------------------------------------------------------
-- 1. Blocked Process Report capture
--    Requires: EXEC sp_configure 'blocked process threshold (s)', 10; RECONFIGURE;
--    Adjust the threshold (seconds) to match your SLA.
-------------------------------------------------------------------------------

/*  -- Uncomment to create

IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE [name] = N'DBAOps_BlockedProcess')
BEGIN
    CREATE EVENT SESSION [DBAOps_BlockedProcess] ON SERVER
    ADD EVENT sqlserver.blocked_process_report
    (
        ACTION
        (
            sqlserver.database_name,
            sqlserver.session_id,
            sqlserver.sql_text,
            sqlserver.username
        )
    )
    ADD TARGET package0.event_file
    (
        SET filename = N'DBAOps_BlockedProcess.xel',
            max_file_size = 50,     -- MB per file
            max_rollover_files = 5
    )
    WITH
    (
        MAX_MEMORY = 4096 KB,
        EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
        MAX_DISPATCH_LATENCY = 30 SECONDS,
        STARTUP_STATE = OFF         -- Set to ON after testing
    );

    PRINT '***** XE Session [DBAOps_BlockedProcess] created.';
END
GO

-- To start:  ALTER EVENT SESSION [DBAOps_BlockedProcess] ON SERVER STATE = START;
-- To stop:   ALTER EVENT SESSION [DBAOps_BlockedProcess] ON SERVER STATE = STOP;

*/

-------------------------------------------------------------------------------
-- 2. Long-running query capture
--    Captures completed queries exceeding the duration threshold.
--    Adjust the duration predicate to match your environment.
-------------------------------------------------------------------------------

/*  -- Uncomment to create

IF NOT EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE [name] = N'DBAOps_LongRunningQueries')
BEGIN
    CREATE EVENT SESSION [DBAOps_LongRunningQueries] ON SERVER
    ADD EVENT sqlserver.sql_statement_completed
    (
        ACTION
        (
            sqlserver.database_name,
            sqlserver.session_id,
            sqlserver.sql_text,
            sqlserver.username,
            sqlserver.client_hostname,
            sqlserver.client_app_name
        )
        WHERE duration >= 5000000   -- 5 seconds in microseconds
    ),
    ADD EVENT sqlserver.rpc_completed
    (
        ACTION
        (
            sqlserver.database_name,
            sqlserver.session_id,
            sqlserver.sql_text,
            sqlserver.username,
            sqlserver.client_hostname,
            sqlserver.client_app_name
        )
        WHERE duration >= 5000000   -- 5 seconds in microseconds
    )
    ADD TARGET package0.event_file
    (
        SET filename = N'DBAOps_LongRunningQueries.xel',
            max_file_size = 100,    -- MB per file
            max_rollover_files = 5
    )
    WITH
    (
        MAX_MEMORY = 4096 KB,
        EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
        MAX_DISPATCH_LATENCY = 30 SECONDS,
        STARTUP_STATE = OFF         -- Set to ON after testing
    );

    PRINT '***** XE Session [DBAOps_LongRunningQueries] created.';
END
GO

-- To start:  ALTER EVENT SESSION [DBAOps_LongRunningQueries] ON SERVER STATE = START;
-- To stop:   ALTER EVENT SESSION [DBAOps_LongRunningQueries] ON SERVER STATE = STOP;

*/
