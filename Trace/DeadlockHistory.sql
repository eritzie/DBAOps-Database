/*
===================================================================================================
DBAOps Database - Trace: Deadlock History

Description:
    Captures deadlock graph data for post-incident analysis. Deadlock graphs are extracted
    from the system_health Extended Events session (always running) or from a custom
    XE session defined in this folder.

    Two components:
    1. trace.DeadlockHistory          — stores parsed deadlock events
    2. trace.CaptureDeadlocks     — proc to extract recent deadlocks from system_health
                                        and insert them into the history table

    The capture proc is designed to be run on a schedule (every 5-15 minutes via SQL Agent)
    or manually after an incident. It tracks what it has already captured to avoid duplicates.

Prerequisites:
    - Run Setup scripts 01-02 first
    - Execute in the context of [DBAOps]

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

-------------------------------------------------------------------------------
-- trace.DeadlockHistory
-------------------------------------------------------------------------------

IF NOT EXISTS (
    SELECT 1
    FROM sys.objects o
        INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id]
    WHERE s.[name] = N'trace'
      AND o.[name] = N'DeadlockHistory'
      AND o.[type] = 'U'
)
BEGIN

    CREATE TABLE [trace].[DeadlockHistory]
    (
        [DeadlockId]        int             IDENTITY(1,1)   NOT NULL,
        [EventTime]         datetime2(3)    NOT NULL,
        [DatabaseName]      nvarchar(128)   NULL,
        [VictimProcess]     nvarchar(128)   NULL,
        [DeadlockGraph]     xml             NOT NULL,
        [CapturedAt]        datetime2(0)    NOT NULL    CONSTRAINT [DF_DeadlockHistory_CapturedAt] DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT [PK_DeadlockHistory] PRIMARY KEY CLUSTERED ([DeadlockId])
    );

    CREATE NONCLUSTERED INDEX [IX_DeadlockHistory_EventTime]
        ON [trace].[DeadlockHistory] ([EventTime] DESC);

    CREATE NONCLUSTERED INDEX [IX_DeadlockHistory_DatabaseName]
        ON [trace].[DeadlockHistory] ([DatabaseName])
        WHERE [DatabaseName] IS NOT NULL;

    PRINT '***** Table [trace].[DeadlockHistory] created.';

END
ELSE
    PRINT '***** Table [trace].[DeadlockHistory] already exists.';
GO

-------------------------------------------------------------------------------
-- trace.CaptureDeadlocks
-------------------------------------------------------------------------------

CREATE OR ALTER PROCEDURE [trace].[CaptureDeadlocks]
AS
BEGIN
    SET NOCOUNT ON;

    -- Extract deadlock graphs from the system_health XE session.
    -- The ring buffer holds recent events; this proc captures any
    -- that are newer than the most recent entry in DeadlockHistory.

    DECLARE @LastCapture datetime2(3);

    SELECT @LastCapture = MAX([EventTime])
    FROM [trace].[DeadlockHistory];

    -- Default to last 24 hours if no prior captures
    IF @LastCapture IS NULL
        SET @LastCapture = DATEADD(HOUR, -24, SYSUTCDATETIME());

    ;WITH DeadlockEvents AS
    (
        SELECT
            xdr.value('@timestamp', 'datetime2(3)') AS EventTime,
            xdr.query('.') AS DeadlockReport
        FROM
        (
            SELECT CAST(target_data AS xml) AS TargetData
            FROM sys.dm_xe_session_targets st
                INNER JOIN sys.dm_xe_sessions s ON s.[address] = st.event_session_address
            WHERE s.[name] = N'system_health'
              AND st.target_name = N'ring_buffer'
        ) AS Data
        CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="xml_deadlock_report"]') AS xEvents(xdr)
        WHERE xdr.value('@timestamp', 'datetime2(3)') > @LastCapture
    )
    INSERT INTO [trace].[DeadlockHistory] ([EventTime], [DatabaseName], [VictimProcess], [DeadlockGraph])
    SELECT
        de.EventTime,
        de.DeadlockReport.value('(event/data[@name="database_name"]/value)[1]', 'nvarchar(128)'),
        de.DeadlockReport.value('(event/data[@name="xml_report"]/value/deadlock/victim-list/victimProcess/@id)[1]', 'nvarchar(128)'),
        de.DeadlockReport.query('event/data[@name="xml_report"]/value/deadlock')
    FROM DeadlockEvents de;

    PRINT '***** Captured ' + CAST(@@ROWCOUNT AS varchar) + ' new deadlock event(s).';
END
GO

PRINT '***** Procedure [trace].[CaptureDeadlocks] created.';
GO