USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns transaction log size, used space, and percent used for the specified database(s).
    For USER_DATABASES or ALL_DATABASES, returns a summary result set via DBCC SQLPERF.
    For a single named database, also returns a detailed second result set from
    sys.dm_db_log_space_usage.

Parameters:
    @Database   as nvarchar(128)   Ola Hallengren-style target: USER_DATABASES, ALL_DATABASES, or a specific database name. Default: USER_DATABASES.

Usage Example:
    EXEC [dbo].[GetLogSpaceUsage];
    EXEC [dbo].[GetLogSpaceUsage] @Database = N'AdventureWorks';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetLogSpaceUsage]
    @Database nvarchar(128) = N'USER_DATABASES'
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #Databases (DatabaseName nvarchar(128) NOT NULL);

    IF @Database = N'USER_DATABASES'
        INSERT INTO #Databases
        SELECT [name] FROM sys.databases
        WHERE database_id > 4 AND [state_desc] = N'ONLINE';
    ELSE IF @Database = N'ALL_DATABASES'
        INSERT INTO #Databases
        SELECT [name] FROM sys.databases
        WHERE [state_desc] = N'ONLINE';
    ELSE
        INSERT INTO #Databases VALUES (@Database);

    -- DBCC SQLPERF(LOGSPACE) returns all databases in one shot without a per-database loop.
    -- sys.dm_db_log_space_usage is database-scoped and would require dynamic SQL with USE
    -- for each database; SQLPERF is the correct approach for the multi-database case.
    CREATE TABLE #LogSpace (
         DatabaseName   nvarchar(128)
        ,LogSizeMB      float
        ,LogUsedPct     float
        ,Status         int
    );

    INSERT INTO #LogSpace
    EXEC ('DBCC SQLPERF(LOGSPACE) WITH NO_INFOMSGS');

    -- Result set 1: log space summary
    SELECT
         l.DatabaseName
        ,l.LogSizeMB
        ,l.LogUsedPct
        ,l.LogSizeMB * l.LogUsedPct / 100.0     AS LogUsedMB
        ,l.Status
    FROM #LogSpace                               l
    JOIN #Databases                              db ON l.DatabaseName = db.DatabaseName
    ORDER BY l.LogUsedPct DESC;

    -- Result set 2: detailed log file info, available only for a single named database.
    -- sys.dm_db_log_space_usage is database-scoped; USE inside the dynamic batch switches
    -- context for that execution only and does not affect the outer procedure.
    IF @Database NOT IN (N'USER_DATABASES', N'ALL_DATABASES')
    BEGIN
        DECLARE @SQL nvarchar(MAX) = N'
        USE ' + QUOTENAME(@Database) + N';
        SELECT
             DB_NAME()                          AS DatabaseName
            ,total_log_size_mb
            ,used_log_space_mb
            ,used_log_space_percent
            ,log_backup_time
        FROM [sys].[dm_db_log_space_usage];';

        EXEC sp_executesql @SQL;
    END
END
