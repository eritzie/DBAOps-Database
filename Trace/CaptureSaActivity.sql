/*
================================================================================
  DBAOps \ Trace \ CaptureSaActivity.sql

  Purpose : Reads new events from the sa_activity_monitor Extended Events
            file target and inserts them into trace.SaLoginHistory.
            Deduplicates on (EventTime, EventType, AppName, ClientHost) to
            protect against overlap when the Agent job fires while a prior
            run is still executing.

  Depends : trace.SaLoginHistory (SaLoginHistory.sql)
            XE file target at @XELogPath (sa_activity_monitor session,
            deployed via sa_activity_monitor.sql + Deploy-SaActivityMonitor.ps1)

  Schedule: SQL Agent job, every 10 minutes.
            See Setup\05_CreateAgentJobs.sql.

  Parameters
  ----------
    @XELogPath   NVARCHAR(260)  Path pattern for the .xel files on THIS instance.
                                Defaults to 'C:\XELogs\sa_activity*.xel'.
                                Change per instance if your XELogs path differs.

    @Debug       BIT            1 = print row counts, skip INSERT (dry run).
                                Default 0.

  Usage
  -----
    -- Normal capture (called by Agent job)
    EXEC [DBAOps].[trace].[CaptureSaActivity];

    -- Dry run -- shows what would be inserted without writing anything
    EXEC [DBAOps].[trace].[CaptureSaActivity] @Debug = 1;

    -- Non-default XELogs path
    EXEC [DBAOps].[trace].[CaptureSaActivity]
        @XELogPath = N'D:\XELogs\sa_activity*.xel';

  Author  : Eric Ritzie
  Date    : 2026-05-13
  Version : 1.0
================================================================================
*/

USE [DBAOps];
GO

CREATE OR ALTER PROCEDURE [trace].[CaptureSaActivity]
    @XELogPath   NVARCHAR(260) = N'C:\XELogs\sa_activity*.xel',
    @Debug       BIT           = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RowsInserted INT = 0;
    DECLARE @Sql          NVARCHAR(MAX);

    -- == Parse XE file target into a temp table ===============================
    -- fn_xe_file_target_read_file can't take a variable directly; use dynamic SQL.

    IF OBJECT_ID(N'tempdb..#XEStaging') IS NOT NULL
        DROP TABLE #XEStaging;

    CREATE TABLE #XEStaging (
        [EventTime]    DATETIME2(3)   NOT NULL,
        [EventType]    VARCHAR(50)    NOT NULL,
        [AppName]      NVARCHAR(256)  NULL,
        [ClientHost]   NVARCHAR(256)  NULL,
        [DatabaseName] NVARCHAR(256)  NULL,
        [SqlText]      NVARCHAR(MAX)  NULL
    );

    SET @Sql = N'
    INSERT INTO #XEStaging ([EventTime], [EventType], [AppName], [ClientHost], [DatabaseName], [SqlText])
    SELECT
        xdr.value(''@timestamp'',  ''datetime2'')                                              AS EventTime,
        xdr.value(''@name'',       ''varchar(50)'')                                            AS EventType,
        xdr.value(''(action[@name="client_app_name"]/value)[1]'', ''nvarchar(256)'')           AS AppName,
        xdr.value(''(action[@name="client_hostname"]/value)[1]'', ''nvarchar(256)'')           AS ClientHost,
        xdr.value(''(action[@name="database_name"]/value)[1]'',   ''nvarchar(256)'')           AS DatabaseName,
        COALESCE(
            xdr.value(''(action[@name="sql_text"]/value)[1]'',    ''nvarchar(max)''),
            xdr.value(''(action[@name="statement"]/value)[1]'',   ''nvarchar(max)'')
        )                                                                                       AS SqlText
    FROM sys.fn_xe_file_target_read_file(N''' + @XELogPath + N''', NULL, NULL, NULL) f
    CROSS APPLY (SELECT CAST(f.event_data AS XML)) AS x(xdr);
    ';

    BEGIN TRY
        EXEC sp_executesql @Sql;
    END TRY
    BEGIN CATCH
        DECLARE @Msg NVARCHAR(2048) = N'CaptureSaActivity: failed to read XE files from "'
            + @XELogPath + N'". Error: ' + ERROR_MESSAGE();
        RAISERROR(@Msg, 16, 1);
        RETURN;
    END CATCH;

    IF @Debug = 1
    BEGIN
        DECLARE @Total   INT = (SELECT COUNT(*) FROM #XEStaging);
        DECLARE @New     INT;

        SELECT @New = COUNT(*)
        FROM #XEStaging s
        WHERE NOT EXISTS (
            SELECT 1 FROM [trace].[SaLoginHistory] h
            WHERE h.[EventTime]  = s.[EventTime]
              AND h.[EventType]  = s.[EventType]
              AND ISNULL(h.[AppName],    N'') = ISNULL(s.[AppName],    N'')
              AND ISNULL(h.[ClientHost], N'') = ISNULL(s.[ClientHost], N'')
        );

        PRINT 'Debug mode -- no rows written.';
        PRINT '  Events in file target : ' + CAST(@Total AS VARCHAR(10));
        PRINT '  New (not yet stored)  : ' + CAST(@New   AS VARCHAR(10));
        RETURN;
    END;

    -- == Insert new events only (dedup on natural key) ========================
    INSERT INTO [trace].[SaLoginHistory]
        ([EventTime], [EventType], [AppName], [ClientHost], [DatabaseName], [SqlText])
    SELECT
        s.[EventTime],
        s.[EventType],
        s.[AppName],
        s.[ClientHost],
        s.[DatabaseName],
        s.[SqlText]
    FROM #XEStaging s
    WHERE NOT EXISTS (
        SELECT 1 FROM [trace].[SaLoginHistory] h
        WHERE h.[EventTime]  = s.[EventTime]
          AND h.[EventType]  = s.[EventType]
          AND ISNULL(h.[AppName],    N'') = ISNULL(s.[AppName],    N'')
          AND ISNULL(h.[ClientHost], N'') = ISNULL(s.[ClientHost], N'')
    );

    SET @RowsInserted = @@ROWCOUNT;

    IF @RowsInserted > 0
        PRINT 'CaptureSaActivity: inserted ' + CAST(@RowsInserted AS VARCHAR(10)) + ' row(s).';

END;
GO
