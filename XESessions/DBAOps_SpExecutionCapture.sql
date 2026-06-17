/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys the DBAOps_SpExecutionCapture XE session with a ring buffer target. Captures
    rpc_completed events for all named stored procedures. Used as the event source for
    DBAOps.trace.RpcExecutionHistory, populated by the DBAOps - Capture - RpcExecutions
    Agent job (recommended: every 30–60 minutes).

    Ring buffer size is 512MB (max_memory = 524288 KB). If more events are generated
    between collections than the buffer can hold, older events are silently dropped.
    After first collection run, verify no data loss:

        SELECT CAST(t.target_data AS XML)
               .value('(RingBufferTarget/@droppedCount)[1]', 'bigint') AS dropped
        FROM sys.dm_xe_sessions s
        JOIN sys.dm_xe_session_targets t ON s.address = t.event_session_address
        WHERE s.name = N'DBAOps_SpExecutionCapture'
          AND t.target_name = N'ring_buffer';

    If dropped > 0: increase max_memory or run the collection job more frequently.

    Session does NOT start automatically (STARTUP_STATE = OFF). Start manually
    after verifying the deployment, then enable the Agent job.
    All databases are captured including system DBs. Uncomment the filter line
    in the session DDL to exclude master, msdb, tempdb, model, and SSISDB.

Usage Example:
    -- Run in SSMS against the target instance.
    -- Verify deployment:
    SELECT [name], [create_time] FROM sys.dm_xe_sessions WHERE [name] = N'DBAOps_SpExecutionCapture';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-09  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF EXISTS (
    SELECT 1 FROM sys.server_event_sessions
    WHERE [name] = N'DBAOps_SpExecutionCapture'
)
BEGIN
    ALTER EVENT SESSION [DBAOps_SpExecutionCapture] ON SERVER STATE = STOP;
    DROP EVENT SESSION [DBAOps_SpExecutionCapture] ON SERVER;
    PRINT 'Dropped existing DBAOps_SpExecutionCapture session.';
END
GO

CREATE EVENT SESSION [DBAOps_SpExecutionCapture] ON SERVER
ADD EVENT sqlserver.rpc_completed (
    ACTION (sqlserver.database_name)
    WHERE [object_name] <> N''
    -- Uncomment to exclude system databases:
    -- AND [sqlserver].[database_name] NOT IN (N'master', N'msdb', N'tempdb', N'model', N'SSISDB')
)
ADD TARGET package0.ring_buffer (
    SET max_memory = 524288     -- 512MB in KB
)
WITH (
    MAX_DISPATCH_LATENCY    = 30 SECONDS,
    EVENT_RETENTION_MODE    = ALLOW_SINGLE_EVENT_LOSS,
    STARTUP_STATE           = OFF
);
GO

PRINT 'DBAOps_SpExecutionCapture deployed. Session is NOT started — start manually after verification.';
PRINT 'To start: ALTER EVENT SESSION [DBAOps_SpExecutionCapture] ON SERVER STATE = START;';
GO

-- ============================================================================
-- VERIFY (uses server_event_sessions — visible whether started or not)
-- ============================================================================
SELECT
    [event_session_id] AS SessionId,
    [name]             AS SessionName,
    [startup_state]    AS AutoStart
FROM sys.server_event_sessions
WHERE [name] = N'DBAOps_SpExecutionCapture';
GO
