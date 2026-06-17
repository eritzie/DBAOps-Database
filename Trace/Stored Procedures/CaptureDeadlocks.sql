USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Extracts deadlock graphs from the system_health XE session ring buffer and inserts
    any events newer than the most recent row in trace.DeadlockHistory. On first run,
    looks back 24 hours. Used as step 1 of the DBAOps - Capture - Deadlocks Agent job.

Usage Example:
    EXEC [trace].[CaptureDeadlocks];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

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
