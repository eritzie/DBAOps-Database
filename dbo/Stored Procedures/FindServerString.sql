USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Searches the instance for a string across SQL module definitions (stored procedures,
    views, functions, triggers), SQL Agent job step commands, and linked server definitions.
    Mirrors the Find-ServerString PowerShell cmdlet in DbaToolbox.

    @Database applies only to the SQL module search. Agent jobs and linked servers are
    always instance-wide regardless of @Database. Case sensitivity follows the target
    collation.

Parameters:
    @SearchString        as nvarchar(256)   Required. String to search for.
    @Database            as nvarchar(128)   Ola Hallengren-style target for SQL module search: USER_DATABASES, ALL_DATABASES, or a specific database name. Default: USER_DATABASES.
    @SearchModules       as bit             1 = search SQL module definitions. Default: 1.
    @SearchAgentJobs     as bit             1 = search SQL Agent job step commands. Default: 1.
    @SearchLinkedServers as bit             1 = search linked server name, data source, and location. Default: 1.

Usage Example:
    EXEC [dbo].[FindServerString] @SearchString = N'mystring';
    EXEC [dbo].[FindServerString] @SearchString = N'mystring', @Database = N'ALL_DATABASES', @SearchAgentJobs = 0;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[FindServerString]
    @SearchString        nvarchar(256),
    @Database            nvarchar(128) = N'USER_DATABASES',
    @SearchModules       bit           = 1,
    @SearchAgentJobs     bit           = 1,
    @SearchLinkedServers bit           = 1
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #Results (
         SourceType    nvarchar(20)    NOT NULL    -- 'SqlModule', 'AgentJob', 'LinkedServer'
        ,DatabaseName  nvarchar(128)   NULL
        ,SchemaName    nvarchar(128)   NULL
        ,ObjectName    nvarchar(256)   NOT NULL
        ,ObjectType    nvarchar(60)    NOT NULL
        ,MatchContext  nvarchar(MAX)   NULL        -- full definition, command, or data source string
    );

    -- SQL Modules: sys.sql_modules and sys.objects are database-scoped, requiring a per-database
    -- loop. USE inside the dynamic batch switches context so catalog views resolve against the
    -- target database without three-part names. #Results was created in the outer session scope
    -- and remains accessible inside the sp_executesql batch.
    IF @SearchModules = 1
    BEGIN
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

        DECLARE @CurrentDB  nvarchar(128);
        DECLARE @SQL        nvarchar(MAX);

        WHILE EXISTS (SELECT 1 FROM #Databases)
        BEGIN
            SELECT TOP 1 @CurrentDB = DatabaseName FROM #Databases ORDER BY DatabaseName;

            SET @SQL = N'
            USE ' + QUOTENAME(@CurrentDB) + N';
            INSERT INTO #Results (SourceType, DatabaseName, SchemaName, ObjectName, ObjectType, MatchContext)
            SELECT
                 N''SqlModule''
                ,DB_NAME()
                ,s.name
                ,o.name
                ,o.type_desc
                ,m.definition
            FROM [sys].[sql_modules]   m
            JOIN [sys].[objects]       o ON m.object_id = o.object_id
            JOIN [sys].[schemas]       s ON o.schema_id = s.schema_id
            WHERE CHARINDEX(@Pattern, m.definition) > 0;';

            EXEC sp_executesql @SQL, N'@Pattern NVARCHAR(256)', @Pattern = @SearchString;

            DELETE FROM #Databases WHERE DatabaseName = @CurrentDB;
        END
    END

    -- Agent job steps: instance-wide via msdb; no loop needed.
    -- ObjectName packs job name, step ID, and step name to match the Find-ServerString
    -- PowerShell cmdlet output format and make results self-identifying without MatchContext.
    IF @SearchAgentJobs = 1
    BEGIN
        INSERT INTO #Results (SourceType, DatabaseName, SchemaName, ObjectName, ObjectType, MatchContext)
        SELECT
             N'AgentJob'
            ,s.database_name
            ,NULL
            ,j.name + N' / Step ' + CAST(s.step_id AS nvarchar(10)) + N': ' + s.step_name
            ,N'AgentJobStep'
            ,s.command
        FROM [msdb].[dbo].[sysjobsteps]   s
        JOIN [msdb].[dbo].[sysjobs]        j ON s.job_id = j.job_id
        WHERE CHARINDEX(@SearchString, s.command) > 0;
    END

    -- Linked servers: instance-wide. ISNULL wrapping on data_source and location is required
    -- because some providers (e.g. MSOLEDBSQL without a data source) leave these columns NULL;
    -- CHARINDEX with a NULL haystack returns NULL rather than 0 and the row would be silently excluded.
    IF @SearchLinkedServers = 1
    BEGIN
        INSERT INTO #Results (SourceType, DatabaseName, SchemaName, ObjectName, ObjectType, MatchContext)
        SELECT
             N'LinkedServer'
            ,NULL
            ,NULL
            ,s.name
            ,N'LinkedServer'
            ,N'Provider='      + ISNULL(s.provider,    N'')
                + N'; DataSource=' + ISNULL(s.data_source, N'')
                + N'; Location='   + ISNULL(s.location,    N'')
        FROM [sys].[servers]  s
        WHERE s.is_linked = 1
          AND (   CHARINDEX(@SearchString, s.name)                     > 0
               OR CHARINDEX(@SearchString, ISNULL(s.data_source, N'')) > 0
               OR CHARINDEX(@SearchString, ISNULL(s.location,    N'')) > 0
              );
    END

    SELECT
         SourceType
        ,DatabaseName
        ,SchemaName
        ,ObjectName
        ,ObjectType
        ,MatchContext
    FROM #Results
    ORDER BY SourceType, DatabaseName, ObjectName;
END
