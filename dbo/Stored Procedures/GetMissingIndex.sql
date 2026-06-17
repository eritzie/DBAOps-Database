USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns missing index recommendations from the plan cache with an improvement measure
    score. Results are filtered to the specified database(s). Low-scoring recommendations
    are typically noise from infrequent queries and are excluded by @MinImprovementMeasure.

Parameters:
    @Database               as nvarchar(128)   Ola Hallengren-style target: USER_DATABASES, ALL_DATABASES, or a specific database name. Default: USER_DATABASES.
    @MinImprovementMeasure  as float           Minimum improvement measure score to include. Default: 100000.0.

Usage Example:
    EXEC [dbo].[GetMissingIndex];
    EXEC [dbo].[GetMissingIndex] @Database = N'AdventureWorks', @MinImprovementMeasure = 50000.0;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetMissingIndex]
    @Database               nvarchar(128) = N'USER_DATABASES',
    @MinImprovementMeasure  float         = 100000.0
AS
BEGIN
    SET NOCOUNT ON;

    -- sys.dm_db_missing_index_details is instance-wide with a database_id column;
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

    SELECT
         DB_NAME(d.database_id)                          AS DatabaseName
        ,OBJECT_NAME(d.object_id, d.database_id)         AS TableName
        ,d.equality_columns
        ,d.inequality_columns
        ,d.included_columns
        -- Improvement measure: avg_total_user_cost * avg_user_impact * (user_seeks + user_scans).
        -- Represents estimated query cost reduction if the index existed. Scores below
        -- ~100,000 are typically noise from rare or low-cost queries and not worth acting on.
        ,gs.avg_total_user_cost
            * gs.avg_user_impact
            * (gs.user_seeks + gs.user_scans)             AS ImprovementMeasure
        ,gs.user_seeks
        ,gs.user_scans
        ,gs.last_user_seek
        ,gs.last_user_scan
    FROM [sys].[dm_db_missing_index_details]             d
    JOIN [sys].[dm_db_missing_index_groups]              g  ON d.index_handle      = g.index_handle
    JOIN [sys].[dm_db_missing_index_group_stats]         gs ON g.index_group_handle = gs.group_handle
    JOIN #Databases                                      db ON DB_NAME(d.database_id) = db.DatabaseName
    WHERE gs.avg_total_user_cost
            * gs.avg_user_impact
            * (gs.user_seeks + gs.user_scans) >= @MinImprovementMeasure
    ORDER BY ImprovementMeasure DESC;
END
