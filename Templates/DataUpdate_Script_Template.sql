--***************************************************************************************************
-- TODO: Update copyright notice for your organization
--
-- NOTE: PLEASE USE THE FOLLOWING NAMING CONVENTION FOR THE SCRIPTS.
--       1a_PBI12345_DatabaseName_Description_PreDeployment.sql
--       1b_PBI12345_DatabaseName_Description_PostDeployment.sql

-- Use the Specify Values for Template Parameters
-- command (Ctrl-Shift-M) to fill in the parameter
-- values below.

--Script Name:
-- This is the RunOnce guard key. Must match the filename exactly.
    DECLARE @ScriptName nvarchar(255);
    SET @ScriptName = '<Script Name,nvarchar(255),DataUpdate_PBI12345_Description.sql>'

--Author:
    DECLARE @DevName nvarchar(255);
    SET @DevName = '<Developer Name,nvarchar(255),Developer_Name>'

--Target Database:
    DECLARE @DatabaseName nvarchar(255);
    SET @DatabaseName = '<Database Name,nvarchar(255),Database_Name>'

--Release Ticket:
    DECLARE @Ticket nvarchar(50);
    SET @Ticket = '<Ticket Number,nvarchar(50),PBI12345>'

--Deployment ID (optional):
-- Pipeline run ID, PR number, release name, etc. Injected by CI/CD pipeline.
-- Azure DevOps: $(Build.BuildId) or PR-$(System.PullRequest.PullRequestId)
-- GitHub Actions: ${{ github.run_id }}
    DECLARE @DeploymentId nvarchar(100);
    SET @DeploymentId = '<Deployment ID,nvarchar(100),>'

--Utility Database:
-- The DBA operational database where rollback and run-once data is stored.
    DECLARE @UtilityDB nvarchar(128);
    SET @UtilityDB = '<Utility Database,nvarchar(128),DBAOps>'
--***************************************************************************************************
-- Rollback variables
-- If Rollback of data is needed, set @ROLLBACK = 1
DECLARE @ROLLBACK       bit;
SET @ROLLBACK           = <Run Rollback?,bit,0>; --0=FALSE, 1=TRUE

DECLARE @FALSE          tinyint;
DECLARE @TRUE           tinyint;
DECLARE @CRLF           char(2);
DECLARE @ErrorMessage   nvarchar(4000);
DECLARE @StartTime      datetime;
DECLARE @Success        bit;

SET @StartTime          = GETDATE();
SET @FALSE              = 0;
SET @TRUE               = 1;
SET @CRLF               = CHAR(13) + CHAR(10);
SET @ErrorMessage       = '';
SET @Success            = @FALSE;

-----------BEGIN SQL SCRIPT HEADER------------------
PRINT '====================================================================================';
PRINT '---START SQL SCRIPT-----';
PRINT '---SCRIPT START TIME: ' + CONVERT(varchar, @StartTime);
PRINT '---SCRIPT RAN ON DB : ' + DB_NAME();
PRINT '---Machine Name: ' + CAST(SERVERPROPERTY('MachineName') AS varchar);
PRINT '---System User : ' + SUSER_SNAME();
PRINT '---Host        : ' + HOST_NAME();
PRINT '---Application : ' + APP_NAME();
PRINT '---TranCount   : ' + CAST(@@TRANCOUNT AS varchar);
PRINT @CRLF
PRINT '---Script Name : ' + @ScriptName;
PRINT '---Target DB   : ' + @DatabaseName;
PRINT '---Utility DB  : ' + @UtilityDB;
PRINT '---Developer   : ' + @DevName;
PRINT '---Ticket Num  : ' + @Ticket;
PRINT '---Deployment  : ' + ISNULL(@DeploymentId, '(none)');
PRINT '====================================================================================';
-----------END SQL SCRIPT HEADER--------------------

-----------BEGIN SQL CODE-----------

---------------------------------------------------------------------
-- RunOnce guard: skip if this script has already succeeded
---------------------------------------------------------------------
DECLARE @RunOnceCheckCmd nvarchar(max);
DECLARE @AlreadyRan bit = @FALSE;

SET @RunOnceCheckCmd = N'
    SELECT @p_AlreadyRan = CASE WHEN EXISTS (
        SELECT 1 FROM ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RunOnceManifest]
        WHERE [ScriptName] = @p_ScriptName AND [Status] = N''Success''
    ) THEN 1 ELSE 0 END;
';

EXEC sp_executesql @RunOnceCheckCmd,
    N'@p_ScriptName nvarchar(255), @p_AlreadyRan bit OUTPUT',
    @p_ScriptName = @ScriptName,
    @p_AlreadyRan = @AlreadyRan OUTPUT;

IF @AlreadyRan = @TRUE
BEGIN
    PRINT '***** Script ' + @ScriptName + ' has already been executed successfully. Skipping.';
    GOTO ExitScript;
END

PRINT '***** RunOnce check passed. Script has not yet succeeded.';
PRINT '====================================================================================';

---------------------------------------------------------------------
-- Make sure script is not part of already started transaction
---------------------------------------------------------------------
IF @@TRANCOUNT > 0
BEGIN
    SET @ErrorMessage = '!!!!! ' + CONVERT(VARCHAR, @@TRANCOUNT) + ' Open Transactions detected! Script must not be part of already open transaction.';
    GOTO ErrorHandler;
END
ELSE
BEGIN
    PRINT '***** 0 Open Transactions detected.';
    PRINT '====================================================================================';
END

---------------------------------------------------------------------
-- Processing
---------------------------------------------------------------------

-- NOTE: USE OF THE "USE" STATEMENT SHOULD BE AVOIDED IF POSSIBLE.
--       BEST PRACTICE IS TO USE A FULLY QUALIFIED DATABASE NAME.
--       EXAMPLE: DatabaseName.Schema.TableName

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- TODO: ADD YOUR CUSTOM SCRIPT VARIABLES HERE
--
-- @SourceSchema and @SourceTable identify the table being modified.
-- @VerificationCmd is the query that captures before/after state.
-- These values are also used to register the rollback in the manifest.

DECLARE @SourceSchema nvarchar(128);
SET @SourceSchema = N'dbo';

DECLARE @SourceTable nvarchar(128);
SET @SourceTable = N'<Table Name,nvarchar(128),table1>';

DECLARE @VerificationCmd nvarchar(4000);
SET @VerificationCmd = CONCAT_WS(SPACE(1)
    ,N'SELECT column1, column2'
    ,N'FROM ' + QUOTENAME(@DatabaseName) + N'.' + QUOTENAME(@SourceSchema) + N'.' + QUOTENAME(@SourceTable)
    ,N'WHERE column1 = @param1'
    ,N'AND column2 = @param2'
);

DECLARE @ParameterDefinitions nvarchar(4000);
SET @ParameterDefinitions = N'@param1 int, @param2 varchar(50)';

DECLARE @Example1 int = 0;
DECLARE @Example2 varchar(50) = 'ExampleValue';

--**********************************************************************
-- ROLLBACK DATA REGISTRATION
--
-- Registers this capture in the deploy.RollbackManifest table and
-- creates a rollback data table using the ManifestId for a unique,
-- traceable name: deploy.RB_<ManifestId>_<TableName>

DECLARE @ManifestId         int;
DECLARE @RollbackTableName  nvarchar(255);
DECLARE @RollbackTableFQN   nvarchar(500);
DECLARE @RollbackCmd        nvarchar(max);
DECLARE @CleanupCmd         nvarchar(max);
DECLARE @RowsCaptured       int;
DECLARE @DynCmd             nvarchar(max);

-- Insert manifest row to get the ManifestId
SET @DynCmd = N'
    INSERT INTO ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RollbackManifest]
        ([Ticket], [DeploymentId], [SourceDatabase], [SourceSchema], [SourceTable], [RollbackTableName])
    VALUES
        (@p_Ticket, @p_DeploymentId, @p_Database, @p_Schema, @p_Table, N''(pending)'');
    SET @p_ManifestId = SCOPE_IDENTITY();
';

EXEC sp_executesql @DynCmd,
    N'@p_Ticket nvarchar(50), @p_DeploymentId nvarchar(100), @p_Database nvarchar(128), @p_Schema nvarchar(128), @p_Table nvarchar(128), @p_ManifestId int OUTPUT',
    @p_Ticket       = @Ticket,
    @p_DeploymentId = @DeploymentId,
    @p_Database     = @DatabaseName,
    @p_Schema       = @SourceSchema,
    @p_Table        = @SourceTable,
    @p_ManifestId   = @ManifestId OUTPUT;

-- Build the rollback table name from the ManifestId
SET @RollbackTableName = N'RB_' + CAST(@ManifestId AS nvarchar(10)) + N'_' + @SourceTable;
SET @RollbackTableFQN  = QUOTENAME(@UtilityDB) + N'.[deploy].' + QUOTENAME(@RollbackTableName);

-- Update manifest with the actual table name
SET @DynCmd = N'
    UPDATE ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RollbackManifest]
    SET [RollbackTableName] = @p_TableName
    WHERE [ManifestId] = @p_ManifestId;
';

EXEC sp_executesql @DynCmd,
    N'@p_TableName nvarchar(255), @p_ManifestId int',
    @p_TableName  = @RollbackTableName,
    @p_ManifestId = @ManifestId;

PRINT '***** Registered rollback manifest entry (ManifestId: ' + CAST(@ManifestId AS varchar) + ').';
--**********************************************************************
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-- Perform BEFORE image for data change comparison
PRINT '#############################################################';
PRINT 'BEFORE IMAGE:';
PRINT '-------------------------------------------------------------';

EXECUTE sys.sp_executesql @VerificationCmd, @ParameterDefinitions, @param1 = @Example1, @param2 = @Example2;

PRINT '#############################################################';
PRINT @CRLF

--**********************************************************************
-- Capture rollback data via SELECT INTO

-- Drop rollback table if it exists from a prior run
SET @CleanupCmd = N'DROP TABLE IF EXISTS ' + @RollbackTableFQN;
EXEC sp_executesql @CleanupCmd;

PRINT '***** Capturing rollback data to ' + @RollbackTableFQN + '...';

-- Build the SELECT INTO dynamically
SET @RollbackCmd = N'SELECT * INTO ' + @RollbackTableFQN + N'
    FROM ' + QUOTENAME(@DatabaseName) + N'.' + QUOTENAME(@SourceSchema) + N'.' + QUOTENAME(@SourceTable) + N'
    WHERE 1=1';
-- TODO: Add your WHERE clause filters here to match @VerificationCmd.
--       Capturing the full table is safe but may be slow for large tables.
--       For targeted captures, replace the WHERE clause above.

EXEC sp_executesql @RollbackCmd;
SET @RowsCaptured = @@ROWCOUNT;

-- Update manifest with row count
SET @DynCmd = N'
    UPDATE ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RollbackManifest]
    SET [RowsCaptured] = @p_Rows
    WHERE [ManifestId] = @p_ManifestId;
';

EXEC sp_executesql @DynCmd,
    N'@p_Rows int, @p_ManifestId int',
    @p_Rows       = @RowsCaptured,
    @p_ManifestId = @ManifestId;

PRINT '***** Rollback data captured: ' + CAST(@RowsCaptured AS varchar) + ' rows.';
--**********************************************************************

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- APPLY DATA CHANGES
IF @ROLLBACK = @FALSE
BEGIN
    PRINT '***** Applying data changes for ' + QUOTENAME(@SourceSchema) + '.' + QUOTENAME(@SourceTable);

    BEGIN TRANSACTION;
    BEGIN TRY
        -- TODO: Perform updates to desired tables
        UPDATE dbo.table1  -- TODO: Replace with fully qualified table reference
        SET column1 = 'value'
        WHERE column2 = 'some value';

        COMMIT TRANSACTION;
        SET @Success = @TRUE;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        GOTO ErrorHandler;
    END CATCH

    PRINT '***** Application of data changes complete.';
END
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- ROLLBACK DATA CHANGES
IF @ROLLBACK = @TRUE
BEGIN
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
    PRINT '***** Rolling Back changes using ManifestId: ' + CAST(@ManifestId AS varchar);
    PRINT '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!';
    PRINT @CRLF;

    -- NOTE: When running a rollback, you will typically want to set @ManifestId
    -- to the value from the original deployment, not the one generated above.
    -- Query the manifest to find the right one:
    --   SELECT * FROM [DBAOps].[deploy].[RollbackManifest]
    --   WHERE Ticket = 'PBI12345' AND [Status] = 'Active';
    --
    -- Then use the RollbackTableFQN from that entry in your UPDATE ... FROM below.

    BEGIN TRANSACTION;
    BEGIN TRY
        -- TODO: Perform updates to desired tables to restore from rollback data
        -- UPDATE <target table>
        -- SET column1 = rb.column1
        -- FROM <RollbackTableFQN> rb
        -- WHERE <target>.column2 = rb.column2;

        COMMIT TRANSACTION;
        SET @Success = @TRUE;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();
        GOTO ErrorHandler;
    END CATCH

    -- Mark manifest entry as rolled back
    SET @DynCmd = N'
        UPDATE ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RollbackManifest]
        SET [Status]          = N''RolledBack'',
            [StatusUpdatedAt] = SYSUTCDATETIME(),
            [StatusUpdatedBy] = SUSER_SNAME()
        WHERE [ManifestId] = @p_ManifestId;
    ';

    EXEC sp_executesql @DynCmd,
        N'@p_ManifestId int',
        @p_ManifestId = @ManifestId;

    PRINT '***** Rollback complete. Manifest status updated.';
END
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-- Perform AFTER image for data change comparison (only on success)
IF @Success = @TRUE
BEGIN
    PRINT @CRLF
    PRINT '#############################################################';
    PRINT 'AFTER IMAGE:';
    PRINT '-------------------------------------------------------------';

    EXECUTE sys.sp_executesql @VerificationCmd, @ParameterDefinitions, @param1 = @Example1, @param2 = @Example2;

    PRINT '#############################################################';
END

--**********************************************************************
-- REGISTER SUCCESS IN RUNONCE MANIFEST
--**********************************************************************
IF @Success = @TRUE
BEGIN
    SET @DynCmd = N'
        INSERT INTO ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RunOnceManifest]
            ([ScriptName], [Ticket], [DeploymentId], [TargetDatabase], [DurationMs], [Status])
        VALUES
            (@p_ScriptName, @p_Ticket, @p_DeploymentId, @p_Database,
             DATEDIFF(MILLISECOND, @p_StartTime, GETDATE()), N''Success'');
    ';

    EXEC sp_executesql @DynCmd,
        N'@p_ScriptName nvarchar(255), @p_Ticket nvarchar(50), @p_DeploymentId nvarchar(100), @p_Database nvarchar(128), @p_StartTime datetime',
        @p_ScriptName   = @ScriptName,
        @p_Ticket       = @Ticket,
        @p_DeploymentId = @DeploymentId,
        @p_Database     = @DatabaseName,
        @p_StartTime    = @StartTime;

    PRINT '***** Registered in RunOnceManifest as Success.';
END

GOTO ExitScript;

-----------END SQL CODE-----------

-----------BEGIN ERROR HANDLER BLOCK-----------
ErrorHandler:

-- Register failure in RunOnce manifest before raising the error
BEGIN TRY
    SET @DynCmd = N'
        INSERT INTO ' + QUOTENAME(@UtilityDB) + N'.[deploy].[RunOnceManifest]
            ([ScriptName], [Ticket], [DeploymentId], [TargetDatabase], [DurationMs], [Status], [ErrorMessage])
        VALUES
            (@p_ScriptName, @p_Ticket, @p_DeploymentId, @p_Database,
             DATEDIFF(MILLISECOND, @p_StartTime, GETDATE()), N''Failed'', @p_ErrorMessage);
    ';

    EXEC sp_executesql @DynCmd,
        N'@p_ScriptName nvarchar(255), @p_Ticket nvarchar(50), @p_DeploymentId nvarchar(100), @p_Database nvarchar(128), @p_StartTime datetime, @p_ErrorMessage nvarchar(4000)',
        @p_ScriptName   = @ScriptName,
        @p_Ticket       = @Ticket,
        @p_DeploymentId = @DeploymentId,
        @p_Database     = @DatabaseName,
        @p_StartTime    = @StartTime,
        @p_ErrorMessage = @ErrorMessage;

    PRINT '***** Registered in RunOnceManifest as Failed.';
END TRY
BEGIN CATCH
    -- If we can't even write to the manifest, don't mask the original error
    PRINT '!!!!! WARNING: Failed to register in RunOnceManifest: ' + ERROR_MESSAGE();
END CATCH

RAISERROR(@ErrorMessage, 16, 1);

---------------------------------------------------------------------
-- Exit script
---------------------------------------------------------------------
ExitScript:

-----------BEGIN SQL SCRIPT FOOTER------------------
PRINT '====================================================================================';
PRINT '---FINISHED SQL SCRIPT--';
PRINT '---Finished At : ' + CONVERT(varchar, GETDATE());
PRINT '---Duration Ms : ' + CAST(DATEDIFF(MILLISECOND, @StartTime, GETDATE()) AS varchar);
PRINT '---TranCount   : ' + CONVERT(varchar, @@TRANCOUNT);
PRINT '---ManifestId  : ' + ISNULL(CAST(@ManifestId AS varchar), '(none)');
PRINT '====================================================================================';
GO
-----------END SQL SCRIPT FOOTER--------------------