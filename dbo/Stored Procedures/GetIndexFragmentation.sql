USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns index fragmentation for the specified database(s) using SAMPLED mode.
    Filters out indexes below the minimum fragmentation percent and page count thresholds
    to focus on actionable results.

Parameters:
    @Database           as nvarchar(128)   Ola Hallengren-style target: USER_DATABASES, ALL_DATABASES, or a specific database name. Default: USER_DATABASES.
    @MinFragmentation   as float           Minimum avg fragmentation percent to include. Default: 5.0.
    @MinPageCount       as int             Minimum page count to include; filters out tiny indexes. Default: 1000.

Usage Example:
    EXEC [dbo].[GetIndexFragmentation];
    EXEC [dbo].[GetIndexFragmentation] @Database = N'AdventureWorks', @MinFragmentation = 10.0, @MinPageCount = 500;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetIndexFragmentation]
    @Database           nvarchar(128) = N'USER_DATABASES',
    @MinFragmentation   float         = 5.0,
    @MinPageCount       int           = 1000
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

    CREATE TABLE #Results (
         DatabaseName    nvarchar(128)
        ,SchemaName      nvarchar(128)
        ,TableName       nvarchar(128)
        ,IndexName       nvarchar(128)
        ,IndexType       nvarchar(60)
        ,AvgFragPct      float
        ,PageCount       bigint
        ,PartitionNumber int
    );

    DECLARE @CurrentDB  nvarchar(128);
    DECLARE @SQL        nvarchar(MAX);

    -- sys.dm_db_index_physical_stats requires a database ID per call; no cross-database
    -- equivalent exists. The WHILE loop is the only correct approach here.
    WHILE EXISTS (SELECT 1 FROM #Databases)
    BEGIN
        SELECT TOP 1 @CurrentDB = DatabaseName FROM #Databases ORDER BY DatabaseName;

        -- DB_ID is parameterized because sp_executesql runs in the DBAOps context;
        -- DB_ID() inside the batch would return DBAOps, not @CurrentDB.
        -- Catalog view joins use three-part names for the same reason: sys.indexes,
        -- sys.objects, and sys.schemas are database-scoped and would otherwise
        -- resolve against DBAOps.
        SET @SQL = N'
        INSERT INTO #Results
        SELECT
             DB_NAME(@DBID)                              AS DatabaseName
            ,s.name                                      AS SchemaName
            ,t.name                                      AS TableName
            ,i.name                                      AS IndexName
            ,ps.index_type_desc                          AS IndexType
            ,ps.avg_fragmentation_in_percent             AS AvgFragPct
            ,ps.page_count                               AS PageCount
            ,ps.partition_number                         AS PartitionNumber
        FROM sys.dm_db_index_physical_stats(@DBID, NULL, NULL, NULL, N''SAMPLED'')  ps
        JOIN ' + QUOTENAME(@CurrentDB) + N'.[sys].[indexes]  i  ON ps.object_id = i.object_id
                                                                AND ps.index_id  = i.index_id
        JOIN ' + QUOTENAME(@CurrentDB) + N'.[sys].[objects]  t  ON i.object_id  = t.object_id
        JOIN ' + QUOTENAME(@CurrentDB) + N'.[sys].[schemas]  s  ON t.schema_id  = s.schema_id
        WHERE ps.avg_fragmentation_in_percent >= @MinFrag
          AND ps.page_count                   >= @MinPages
          AND i.name IS NOT NULL              -- exclude heaps (no index name)
        ORDER BY ps.avg_fragmentation_in_percent DESC;';

        EXEC sp_executesql @SQL,
            N'@DBID INT, @MinFrag FLOAT, @MinPages INT',
            @DBID     = DB_ID(@CurrentDB),
            @MinFrag  = @MinFragmentation,
            @MinPages = @MinPageCount;

        DELETE FROM #Databases WHERE DatabaseName = @CurrentDB;
    END

    SELECT
         DatabaseName
        ,SchemaName
        ,TableName
        ,IndexName
        ,IndexType
        ,AvgFragPct
        ,PageCount
        ,PartitionNumber
    FROM #Results
    ORDER BY DatabaseName, AvgFragPct DESC;
END
