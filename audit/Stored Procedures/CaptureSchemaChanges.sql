USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Reads the DBAOps_SchemaChange XE ring buffer, deduplicates against
    audit.SchemaChangeHistory, resolves the schema name for each new event, and inserts
    new rows into the permanent table. No existing rows are modified or deleted.

    Schema resolution priority:
    1. Catalog join -- dynamic SQL against <DatabaseName>.sys.objects using ObjectId.
       Works for objects that still exist at capture time.
    2. SqlText parse -- pattern match on schema.objectname or [schema].[objectname]
       in the sql_text action value. Best-effort fallback for dropped objects.
    SchemaResolutionMethod records which method succeeded or 'unresolved' if neither did.

    Safe to call manually. Returns no result set. Returns early if the session is
    stopped or the ring buffer target_data is NULL.

Parameters:
    None

Usage Example:
    EXEC [audit].[CaptureSchemaChanges];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-18  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [audit].[CaptureSchemaChanges]
AS
BEGIN
    SET NOCOUNT ON;

    -- -------------------------------------------------------------------------
    -- Read ring buffer
    -- -------------------------------------------------------------------------
    DECLARE @xml xml;

    SELECT @xml = CONVERT(xml, st.[target_data])
    FROM   sys.dm_xe_sessions        s
    JOIN   sys.dm_xe_session_targets st ON s.[address] = st.[event_session_address]
    WHERE  s.[name]         = N'DBAOps_SchemaChange'
      AND  st.[target_name] = N'ring_buffer';

    IF @xml IS NULL RETURN;

    -- -------------------------------------------------------------------------
    -- Shred ring buffer XML into staging table
    -- -------------------------------------------------------------------------
    SELECT
        [EventName]     = e.value('(@name)[1]',                                       'varchar(50)'),
        [EventTime]     = e.value('(@timestamp)[1]',                                  'datetime2(7)'),
        [TransactionId] = e.value('(data[@name="transaction_id"]/value)[1]',          'bigint'),
        [DatabaseName]  = e.value('(data[@name="database_name"]/value)[1]',           'sysname'),
        [ObjectId]      = e.value('(data[@name="object_id"]/value)[1]',               'int'),
        [ObjectName]    = e.value('(data[@name="object_name"]/value)[1]',             'sysname'),
        [ObjectType]    = e.value('(data[@name="object_type"]/text)[1]',              'varchar(30)'),
        [LoginName]     = e.value('(action[@name="server_principal_name"]/value)[1]', 'sysname'),
        [ClientHost]    = e.value('(action[@name="client_hostname"]/value)[1]',       'nvarchar(128)'),
        [AppName]       = e.value('(action[@name="client_app_name"]/value)[1]',       'nvarchar(128)'),
        [SqlText]       = e.value('(action[@name="sql_text"]/value)[1]',              'nvarchar(max)')
    INTO #Staged
    FROM @xml.nodes('RingBufferTarget/event') x(e);

    -- -------------------------------------------------------------------------
    -- Remove already-captured events (dedup by EventName + TransactionId)
    -- -------------------------------------------------------------------------
    DELETE s
    FROM   #Staged s
    WHERE  EXISTS
    (
        SELECT 1
        FROM   [audit].[SchemaChangeHistory] h
        WHERE  h.[TransactionId] = s.[TransactionId]
          AND  h.[EventName]     = s.[EventName]
    );

    IF NOT EXISTS (SELECT 1 FROM #Staged) RETURN;

    -- -------------------------------------------------------------------------
    -- Schema name resolution
    -- -------------------------------------------------------------------------
    ALTER TABLE #Staged ADD [SchemaName] sysname NULL, [SchemaResolutionMethod] varchar(20) NULL;
    ALTER TABLE #Staged ADD [RowId] int IDENTITY(1,1);

    DECLARE
        @RowId      int,
        @DbName     sysname,
        @ObjId      int,
        @ObjName    sysname,
        @SqlText    nvarchar(max),
        @SchemaName sysname,
        @Method     varchar(20),
        @DynSql     nvarchar(500),
        @DotPos     int,
        @SchemaRaw  nvarchar(256);

    DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
        SELECT [RowId], [DatabaseName], [ObjectId], [ObjectName], [SqlText]
        FROM   #Staged;

    OPEN cur;
    FETCH NEXT FROM cur INTO @RowId, @DbName, @ObjId, @ObjName, @SqlText;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @SchemaName = NULL;
        SET @Method     = NULL;

        -- Approach 1: catalog resolution via dynamic SQL
        IF @ObjId IS NOT NULL AND @ObjId <> 0 AND @DbName IS NOT NULL
        BEGIN
            BEGIN TRY
                SET @DynSql = N'SELECT @sn = SCHEMA_NAME(schema_id) '
                            + N'FROM '  + QUOTENAME(@DbName) + N'.sys.objects '
                            + N'WHERE object_id = @oid;';

                EXEC sp_executesql
                    @DynSql,
                    N'@oid int, @sn sysname OUTPUT',
                    @oid = @ObjId,
                    @sn  = @SchemaName OUTPUT;

                IF @SchemaName IS NOT NULL
                    SET @Method = 'catalog';
            END TRY
            BEGIN CATCH
                -- Database offline or inaccessible -- fall through to parse
            END CATCH;
        END;

        -- Approach 2: sql_text parse (best-effort fallback for dropped objects)
        IF @SchemaName IS NULL AND @SqlText IS NOT NULL AND @ObjName IS NOT NULL
        BEGIN
            SET @DotPos = CHARINDEX(N'.' + @ObjName, @SqlText);

            IF @DotPos = 0
                SET @DotPos = CHARINDEX(N'.[' + @ObjName + N']', @SqlText);

            IF @DotPos > 1
            BEGIN
                SET @SchemaRaw = LTRIM(RTRIM(SUBSTRING(@SqlText, 1, @DotPos - 1)));

                SET @SchemaRaw = REVERSE(
                    SUBSTRING(
                        REVERSE(@SchemaRaw),
                        1,
                        CHARINDEX(' ', REVERSE(@SchemaRaw) + ' ') - 1
                    )
                );

                SET @SchemaName = REPLACE(REPLACE(@SchemaRaw, N'[', N''), N']', N'');

                IF @SchemaName IS NOT NULL AND LEN(@SchemaName) > 0
                    SET @Method = 'parsed';
                ELSE
                    SET @SchemaName = NULL;
            END;
        END;

        IF @SchemaName IS NULL
            SET @Method = 'unresolved';

        UPDATE #Staged
        SET    [SchemaName]             = @SchemaName,
               [SchemaResolutionMethod] = @Method
        WHERE  [RowId] = @RowId;

        FETCH NEXT FROM cur INTO @RowId, @DbName, @ObjId, @ObjName, @SqlText;
    END;

    CLOSE cur;
    DEALLOCATE cur;

    -- -------------------------------------------------------------------------
    -- Insert new rows into permanent table
    -- -------------------------------------------------------------------------
    INSERT INTO [audit].[SchemaChangeHistory]
    (
        [EventName], [EventTime], [TransactionId], [DatabaseName],
        [ObjectId], [ObjectName], [ObjectType],
        [SchemaName], [SchemaResolutionMethod],
        [LoginName], [ClientHost], [AppName], [SqlText]
    )
    SELECT
        [EventName], [EventTime], [TransactionId], [DatabaseName],
        NULLIF([ObjectId], 0), [ObjectName], [ObjectType],
        [SchemaName], [SchemaResolutionMethod],
        [LoginName], [ClientHost], [AppName], [SqlText]
    FROM #Staged;

END;
