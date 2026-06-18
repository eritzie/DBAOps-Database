USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Reads the DBAOps_SaActivityMonitor XE ring buffer and inserts new events into
    audit.SaLoginHistory. Deduplicates on EventTime, EventType, AppName, and ClientHost
    to prevent double-inserts on re-run. Safe to call manually.

Parameters:
    None

Usage Example:
    EXEC [audit].[CaptureSaActivity];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
    2026-06-18  Eric Ritzie (eritzie)            Moved from trace schema to audit schema
    2026-06-18  Eric Ritzie (eritzie)            Switched from file target to ring buffer
===============================================================================================*/

CREATE OR ALTER PROCEDURE [audit].[CaptureSaActivity]
AS
BEGIN
    SET NOCOUNT ON;

    -- -------------------------------------------------------------------------
    -- Read ring buffer
    -- -------------------------------------------------------------------------
    DECLARE @xml xml;

    SELECT @xml = CONVERT(xml, st.[target_data])
    FROM   sys.dm_xe_sessions        s
    JOIN   sys.dm_xe_session_targets st ON s.[address] = st.[event_session_address]
    WHERE  s.[name]         = N'DBAOps_SaActivityMonitor'
      AND  st.[target_name] = N'ring_buffer';

    IF @xml IS NULL RETURN;

    -- -------------------------------------------------------------------------
    -- Shred ring buffer XML into staging table
    -- -------------------------------------------------------------------------
    SELECT
        [EventTime]    = e.value('(@timestamp)[1]',                                       'datetime2(3)'),
        [EventType]    = e.value('(@name)[1]',                                            'varchar(50)'),
        [AppName]      = e.value('(action[@name="client_app_name"]/value)[1]',            'nvarchar(256)'),
        [ClientHost]   = e.value('(action[@name="client_hostname"]/value)[1]',            'nvarchar(256)'),
        [DatabaseName] = e.value('(action[@name="database_name"]/value)[1]',              'nvarchar(256)'),
        [SqlText]      = COALESCE(
                             e.value('(action[@name="sql_text"]/value)[1]',               'nvarchar(max)'),
                             e.value('(data[@name="statement"]/value)[1]',                'nvarchar(max)')
                         )
    INTO #Staged
    FROM @xml.nodes('RingBufferTarget/event') x(e);

    -- -------------------------------------------------------------------------
    -- Insert new events only (dedup on natural key)
    -- -------------------------------------------------------------------------
    INSERT INTO [audit].[SaLoginHistory]
        ([EventTime], [EventType], [AppName], [ClientHost], [DatabaseName], [SqlText])
    SELECT
        s.[EventTime],
        s.[EventType],
        s.[AppName],
        s.[ClientHost],
        s.[DatabaseName],
        s.[SqlText]
    FROM #Staged s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM [audit].[SaLoginHistory] h
        WHERE h.[EventTime]                    = s.[EventTime]
          AND h.[EventType]                    = s.[EventType]
          AND ISNULL(h.[AppName],    N'')  = ISNULL(s.[AppName],    N'')
          AND ISNULL(h.[ClientHost], N'')  = ISNULL(s.[ClientHost], N'')
    );

END;
