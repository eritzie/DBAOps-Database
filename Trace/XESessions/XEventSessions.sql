/*
===================================================================================================
DBAOps - Trace: Extended Events Session Definitions

Description:
    Standard XE session definitions for common DBA diagnostic scenarios.
    These sessions target the DBAOps databases's trace schema where applicable,
    or output to the default XE file target.

    Sessions defined here:
    1. DBAOps_BlockedProcess    — captures blocked process reports (requires
                                  'blocked process threshold' server config)
    2. DBAOps_LongRunningQueries — captures queries exceeding a duration threshold

    These are CREATE EVENT SESSION scripts, not auto-started. Review and customize
    the thresholds, then create and start as needed.

Notes:
    - The system_health session (always on) already captures deadlocks,
      errors with severity >= 20, and memory/scheduler issues. These sessions
      supplement it for specific diagnostic needs.
    - File targets default to the SQL Server log directory. Adjust the path
      for your environment.

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

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
--    Captures completed queries exceeding @DurationThresholdMs.
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