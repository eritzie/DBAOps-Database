/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Server-scoped XE session that captures DDL object changes (CREATE, ALTER, DROP)
    across all user databases into a 32 MB ring buffer. Events are read by
    audit.CaptureSchemaChanges on a schedule and loaded into audit.SchemaChangeHistory.

    Events captured: object_created, object_altered, object_deleted.

    Filters applied to each event:
      ddl_phase = 1 (Commit only -- each DDL statement fires Begin and Commit; Commit
        only prevents duplicate rows in the capture table)
      object_type <> 21587 (suppress STATISTICS -- auto-stats updates generate
        high-frequency noise)
      database_id <> 2/3/4 (exclude tempdb, model, msdb)
      database_name exclusions for known monitoring and vendor databases

    Ring buffer data is lost on SQL Server restart. Run the capture job frequently
    enough (recommended every 5 minutes) to drain the buffer before restart events.

    Session auto-starts on SQL Server restart (STARTUP_STATE = ON).

Usage Example:
    -- Deploy manually against each instance. Verify:
    SELECT [name], [create_time]
    FROM sys.dm_xe_sessions
    WHERE [name] = N'DBAOps_SchemaChange';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-18  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE [name] = N'DBAOps_SchemaChange')
    DROP EVENT SESSION [DBAOps_SchemaChange] ON SERVER;
GO

CREATE EVENT SESSION [DBAOps_SchemaChange] ON SERVER
ADD EVENT sqlserver.object_altered
(
    SET collect_database_name = (1)
    ACTION
    (
        sqlserver.server_principal_name,
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname
    )
    WHERE [ddl_phase]     = 1
      AND [object_type]   <> 21587
      AND [database_id]   <> 2
      AND [database_id]   <> 3
      AND [database_id]   <> 4
      AND [database_name] <> N'RedGateMonitor'
      AND [database_name] <> N'SolarWindsFlowStorage'
      AND [database_name] <> N'SolarWindsOrion'
      AND [database_name] <> N'SSISDB'
      AND [database_name] <> N'ReportServer'
      AND [database_name] <> N'ReportServerTempDB'
),
ADD EVENT sqlserver.object_created
(
    SET collect_database_name = (1)
    ACTION
    (
        sqlserver.server_principal_name,
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname
    )
    WHERE [ddl_phase]     = 1
      AND [object_type]   <> 21587
      AND [database_id]   <> 2
      AND [database_id]   <> 3
      AND [database_id]   <> 4
      AND [database_name] <> N'RedGateMonitor'
      AND [database_name] <> N'SolarWindsFlowStorage'
      AND [database_name] <> N'SolarWindsOrion'
      AND [database_name] <> N'SSISDB'
      AND [database_name] <> N'ReportServer'
      AND [database_name] <> N'ReportServerTempDB'
),
ADD EVENT sqlserver.object_deleted
(
    SET collect_database_name = (1)
    ACTION
    (
        sqlserver.server_principal_name,
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname
    )
    WHERE [ddl_phase]     = 1
      AND [object_type]   <> 21587
      AND [database_id]   <> 2
      AND [database_id]   <> 3
      AND [database_id]   <> 4
      AND [database_name] <> N'RedGateMonitor'
      AND [database_name] <> N'SolarWindsFlowStorage'
      AND [database_name] <> N'SolarWindsOrion'
      AND [database_name] <> N'SSISDB'
      AND [database_name] <> N'ReportServer'
      AND [database_name] <> N'ReportServerTempDB'
)
ADD TARGET package0.ring_buffer
(
    SET max_memory = 32768  -- 32 MB
)
WITH
(
    MAX_MEMORY             = 4096 KB,
    EVENT_RETENTION_MODE   = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY   = 30 SECONDS,
    MAX_EVENT_SIZE         = 0 KB,
    MEMORY_PARTITION_MODE  = NONE,
    TRACK_CAUSALITY        = OFF,
    STARTUP_STATE          = ON
);
GO

ALTER EVENT SESSION [DBAOps_SchemaChange] ON SERVER STATE = START;
GO
