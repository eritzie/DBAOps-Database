USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Extracts blocked process events from the DBAOps_BlockedProcess XE session ring buffer
    and inserts any events newer than the most recent row in trace.BlockingHistory. On
    first run, looks back 24 hours. Used as step 1 of the
    DBAOps - Capture - Blocking History Agent job.

Usage Example:
    EXEC [trace].[CaptureBlockingHistory];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [trace].[CaptureBlockingHistory]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @LastCapture DATETIME2(3);

    SELECT @LastCapture = MAX([EventTime])
    FROM [trace].[BlockingHistory];

    -- Default to last 24 hours if no prior captures
    IF @LastCapture IS NULL
        SET @LastCapture = DATEADD(HOUR, -24, SYSUTCDATETIME());

    -- The blocked_process_report event stores its payload in a data field
    -- named "blocked_process". The value is a <blocked-process-report> XML element.

    ;WITH BlockingEvents AS
    (
        SELECT
            xdr.value('@timestamp', 'datetime2(3)')                     AS EventTime,
            xdr.query('event/data[@name="blocked_process"]/value/*[1]') AS BlockingXml
        FROM
        (
            SELECT CAST(target_data AS xml) AS TargetData
            FROM sys.dm_xe_session_targets  st
                INNER JOIN sys.dm_xe_sessions s ON s.[address] = st.event_session_address
            WHERE s.[name]       = N'DBAOps_BlockedProcess'
              AND st.target_name = N'ring_buffer'
        ) AS RingBuffer
        CROSS APPLY TargetData.nodes('RingBufferTarget/event[@name="blocked_process_report"]') AS xEvents(xdr)
        WHERE xdr.value('@timestamp', 'datetime2(3)') > @LastCapture
    )
    INSERT INTO [trace].[BlockingHistory] (
        [EventTime],
        [DatabaseName],
        [BlockedSpid],
        [BlockedLogin],
        [BlockedHost],
        [BlockedWaitTime],
        [BlockedSql],
        [BlockingSpid],
        [BlockingLogin],
        [BlockingHost],
        [BlockingStatus],
        [BlockingSql],
        [BlockingGraph]
    )
    SELECT
        be.EventTime,
        be.BlockingXml.value('(blocked-process-report/blocked-process/process/@currentdbname)[1]',  'nvarchar(128)'),
        be.BlockingXml.value('(blocked-process-report/blocked-process/process/@spid)[1]',            'smallint'),
        be.BlockingXml.value('(blocked-process-report/blocked-process/process/@loginname)[1]',       'nvarchar(128)'),
        be.BlockingXml.value('(blocked-process-report/blocked-process/process/@hostname)[1]',        'nvarchar(128)'),
        be.BlockingXml.value('(blocked-process-report/blocked-process/process/@waittime)[1]',        'int'),
        be.BlockingXml.value('(blocked-process-report/blocked-process/process/inputbuf)[1]',         'nvarchar(max)'),
        be.BlockingXml.value('(blocked-process-report/blocking-process/process/@spid)[1]',           'smallint'),
        be.BlockingXml.value('(blocked-process-report/blocking-process/process/@loginname)[1]',      'nvarchar(128)'),
        be.BlockingXml.value('(blocked-process-report/blocking-process/process/@hostname)[1]',       'nvarchar(128)'),
        be.BlockingXml.value('(blocked-process-report/blocking-process/process/@status)[1]',         'nvarchar(32)'),
        -- BlockingSql: sleeping sessions holding open transactions will return empty string or
        -- whitespace. This is expected behavior — see trace.BlockingHistory column extended property.
        be.BlockingXml.value('(blocked-process-report/blocking-process/process/inputbuf)[1]',        'nvarchar(max)'),
        be.BlockingXml.query('blocked-process-report')
    FROM BlockingEvents be;

    PRINT '***** Captured ' + CAST(@@ROWCOUNT AS varchar) + ' new blocking event(s).';
END
