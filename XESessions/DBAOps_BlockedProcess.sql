/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys the DBAOps_BlockedProcess XE session with a ring buffer target. Captures
    blocked_process_report events when a session has been blocked for longer than the
    'blocked process threshold (s)' configuration value (currently 5 seconds on the
    target instance). Used as the event source for DBAOps.trace.BlockingHistory,
    populated by the DBAOps - Capture - Blocking History Agent job
    (recommended: every 5 minutes).

    Prerequisite: 'blocked process threshold (s)' must be greater than 0. Verify:

        SELECT name, value_in_use
        FROM sys.configurations
        WHERE name = 'blocked process threshold (s)';

    Ring buffer size is 32MB (max_memory = 32768 KB). If more events are generated
    between collections than the buffer can hold, older events are silently dropped.
    After first collection run, verify no data loss:

        SELECT CAST(t.target_data AS XML)
               .value('(RingBufferTarget/@droppedCount)[1]', 'bigint') AS dropped
        FROM sys.dm_xe_sessions s
        JOIN sys.dm_xe_session_targets t ON s.address = t.event_session_address
        WHERE s.name = N'DBAOps_BlockedProcess'
          AND t.target_name = N'ring_buffer';

    If dropped > 0: increase max_memory or run the collection job more frequently.

    Session does NOT start automatically (STARTUP_STATE = OFF). Start manually
    after verifying the deployment, then enable the Agent job.

Usage Example:
    -- Run in SSMS against the target instance.
    -- Verify deployment:
    SELECT [name], [create_time] FROM sys.dm_xe_sessions WHERE [name] = N'DBAOps_BlockedProcess';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions
    WHERE [name] = N'DBAOps_BlockedProcess'
)
BEGIN
    ALTER EVENT SESSION [DBAOps_BlockedProcess] ON SERVER STATE = STOP;
    DROP EVENT SESSION [DBAOps_BlockedProcess] ON SERVER;
    PRINT 'Dropped existing DBAOps_BlockedProcess session.';
END
GO

CREATE EVENT SESSION [DBAOps_BlockedProcess] ON SERVER
ADD EVENT sqlserver.blocked_process_report
ADD TARGET package0.ring_buffer (
    SET max_memory = 32768      -- 32MB in KB; increase if droppedCount > 0 after first collection
)
WITH (
    MAX_DISPATCH_LATENCY    = 30 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    STARTUP_STATE           = OFF
);
GO

PRINT 'DBAOps_BlockedProcess deployed. Session is NOT started — start manually after verification.';
PRINT 'To start: ALTER EVENT SESSION [DBAOps_BlockedProcess] ON SERVER STATE = START;';
GO

-- ============================================================================
-- VERIFY (uses server_event_sessions — visible whether started or not)
-- ============================================================================
SELECT
    [event_session_id] AS SessionId,
    [name]             AS SessionName,
    [startup_state]    AS AutoStart
FROM sys.server_event_sessions
WHERE [name] = N'DBAOps_BlockedProcess';
GO
