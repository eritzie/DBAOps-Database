USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns non-clustered indexes with zero reads since the last SQL Server restart,
    indicating indexes that impose write overhead with no query benefit. Returns the
    SQL Server start time as a first result set so the caller can assess how long the
    sample covers — a short uptime window makes results unreliable.

Parameters:
    @Database   as nvarchar(128)   Ola Hallengren-style target: USER_DATABASES, ALL_DATABASES, or a specific database name. Default: USER_DATABASES.

Usage Example:
    EXEC [dbo].[GetUnusedIndex];
    EXEC [dbo].[GetUnusedIndex] @Database = N'AdventureWorks';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetUnusedIndex]
    @Database nvarchar(128) = N'USER_DATABASES'
AS
BEGIN
    SET NOCOUNT ON;

    -- sys.dm_db_index_usage_stats is instance-wide with a database_id column;
    -- no per-database loop is needed. @Database filters the result set only.
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

    -- Result set 1: SQL Server start time. Usage stats reset at each restart;
    -- a short uptime window (hours or days) is insufficient to identify truly unused indexes —
    -- infrequently-run reports or month-end jobs will not have executed yet.
    SELECT sqlserver_start_time AS SqlServerStartTime
    FROM [sys].[dm_os_sys_info];

    -- Result set 2: non-clustered indexes with zero reads.
    -- Clustered indexes are the physical table itself; they are always "used" by definition
    -- and are never candidates for removal regardless of read counters.
    SELECT
         DB_NAME(u.database_id)                          AS DatabaseName
        ,OBJECT_NAME(u.object_id, u.database_id)         AS TableName
        ,i.name                                          AS IndexName
        ,i.type_desc                                     AS IndexType
        ,u.user_seeks
        ,u.user_scans
        ,u.user_lookups
        ,u.user_updates                                  -- write overhead with no reads
        ,u.last_user_update
    FROM [sys].[dm_db_index_usage_stats]                 u
    JOIN [sys].[indexes]                                 i
        ON u.object_id = i.object_id
       AND u.index_id  = i.index_id
    JOIN #Databases                                      db ON DB_NAME(u.database_id) = db.DatabaseName
    WHERE i.type_desc        = N'NONCLUSTERED'          -- clustered indexes are the table; never "unused"
      AND i.is_primary_key        = 0
      AND i.is_unique_constraint  = 0
      AND u.user_seeks    = 0
      AND u.user_scans    = 0
      AND u.user_lookups  = 0
      AND u.user_updates  > 0                           -- being written to but never read
    ORDER BY u.user_updates DESC;
END
