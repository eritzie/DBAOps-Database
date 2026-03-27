/*
===================================================================================================
DBAOps - Utility: Search for String

Description:
    Parameterized search scripts for locating a string across SQL Server objects.
    Set @SearchString and run the section(s) you need.

    Sections:
    1. Search object definitions in the current database
       (procs, functions, views, triggers — anything in sys.sql_modules)
    2. Search column names in the current database
    3. Search object definitions across ALL databases
    4. Search SQL Agent job step commands

Notes:
    - Section 3 uses a cursor over sys.databases instead of sp_MSforeachdb,
      which is undocumented and has known issues with databases containing
      special characters or hyphens in the name.
    - These are SSMS-ready scripts — open, set @SearchString, run.

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

DECLARE @SearchString nvarchar(500) = N'YourSearchTerm';  -- TODO: Replace with your search term

-------------------------------------------------------------------------------
-- 1. Search object definitions in the current database
-------------------------------------------------------------------------------

SELECT
    DatabaseName    = DB_NAME(),
    SchemaName      = SCHEMA_NAME(o.[schema_id]),
    ObjectName      = o.[name],
    ObjectType      = o.[type_desc],
    [Definition]    = m.[definition]
FROM sys.sql_modules AS m
    INNER JOIN sys.objects AS o ON m.[object_id] = o.[object_id]
WHERE CHARINDEX(@SearchString, m.[definition]) > 0
ORDER BY SchemaName, ObjectName;

-------------------------------------------------------------------------------
-- 2. Search column names in the current database
-------------------------------------------------------------------------------

SELECT
    TableSchema     = c.[TABLE_SCHEMA],
    TableName       = c.[TABLE_NAME],
    ColumnName      = c.[COLUMN_NAME],
    DataType        = c.[DATA_TYPE],
    MaxLength       = c.[CHARACTER_MAXIMUM_LENGTH]
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE CHARINDEX(@SearchString, c.[COLUMN_NAME]) > 0
ORDER BY c.[TABLE_SCHEMA], c.[TABLE_NAME], c.[COLUMN_NAME];

-------------------------------------------------------------------------------
-- 3. Search object definitions across ALL databases
--    Uses a cursor instead of sp_MSforeachdb for reliability.
-------------------------------------------------------------------------------

/*  -- Uncomment to run (this iterates every user database)

DECLARE @DbName nvarchar(128);
DECLARE @Sql nvarchar(max);

CREATE TABLE #SearchResults
(
    DatabaseName    nvarchar(128),
    SchemaName      nvarchar(128),
    ObjectName      nvarchar(128),
    ObjectType      nvarchar(60),
    [Definition]    nvarchar(max)
);

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT [name]
    FROM sys.databases
    WHERE [state] = 0              -- ONLINE
      AND [database_id] > 4       -- skip system databases
      AND [is_read_only] = 0
    ORDER BY [name];

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DbName;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @Sql = N'
        SELECT
            DB_NAME(),
            SCHEMA_NAME(o.[schema_id]),
            o.[name],
            o.[type_desc],
            m.[definition]
        FROM ' + QUOTENAME(@DbName) + N'.sys.sql_modules AS m
            INNER JOIN ' + QUOTENAME(@DbName) + N'.sys.objects AS o ON m.[object_id] = o.[object_id]
        WHERE CHARINDEX(@p_Search, m.[definition]) > 0;
    ';

    INSERT INTO #SearchResults
    EXEC sp_executesql @Sql, N'@p_Search nvarchar(500)', @p_Search = @SearchString;

    FETCH NEXT FROM db_cursor INTO @DbName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

SELECT * FROM #SearchResults ORDER BY DatabaseName, SchemaName, ObjectName;
DROP TABLE #SearchResults;

*/

-------------------------------------------------------------------------------
-- 4. Search SQL Agent job step commands
-------------------------------------------------------------------------------

SELECT
    JobName         = j.[name],
    StepId          = s.[step_id],
    StepName        = s.[step_name],
    DatabaseName    = s.[database_name],
    SubSystem       = s.[subsystem],
    Command         = s.[command]
FROM msdb.dbo.sysjobsteps AS s
    INNER JOIN msdb.dbo.sysjobs AS j ON s.[job_id] = j.[job_id]
WHERE CHARINDEX(@SearchString, s.[command]) > 0
ORDER BY j.[name], s.[step_id];