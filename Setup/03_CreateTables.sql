/*
===================================================================================================
DBAOps Database - Setup Script 03: Create Tables

Description:
    Creates the core tables for the deploy schema.

    deploy.RollbackManifest
        Central registry of all rollback data captures. Every time a deployment script
        captures before-image data, it registers here. The manifest tracks:
        - What deployment the data belongs to (ticket, PR, pipeline run)
        - Where the data came from (server, database, schema, table)
        - Where the rollback data is stored (table name in deploy schema)
        - Lifecycle status (Active → RolledBack | Expired)

    Rollback data tables are created dynamically by deployment scripts using
    SELECT INTO [DBAOps].[deploy].[RB_<ManifestId>_<TableName>].
    These tables are not defined here — they inherit schema from the source.

    deploy.RunOnceManifest
        Registry of run-once deployment scripts. Each script checks this table on
        startup — if a row exists with Status = 'Success', the script skips execution.
        Failed runs are recorded but do not block retries. This enables idempotent
        run-once scripts in CI/CD pipelines without manual tracking or archive steps.

Prerequisites:
    - Run 01_CreateDatabase.sql and 02_CreateSchemas.sql first
    - Execute in the context of [DBAOps]

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.objects o
        INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id]
    WHERE s.[name] = N'deploy'
      AND o.[name] = N'RollbackManifest'
      AND o.[type] = 'U'
)
BEGIN

    CREATE TABLE [deploy].[RollbackManifest]
    (
        -- Identity
        [ManifestId]            int             IDENTITY(1,1)   NOT NULL,

        -- Deployment context — at least one of these should be populated
        [Ticket]                nvarchar(50)    NULL,           -- Work item (PBI-12345, JIRA-678, etc.)
        [DeploymentId]          nvarchar(100)   NULL,           -- Pipeline run ID, PR number, release name
        [DeploymentLabel]       nvarchar(255)   NULL,           -- Free-text description of the deployment

        -- Source identification
        [SourceServer]          nvarchar(128)   NULL,           -- @@SERVERNAME of source (NULL = same server)
        [SourceDatabase]        nvarchar(128)   NOT NULL,
        [SourceSchema]          nvarchar(128)   NOT NULL,
        [SourceTable]           nvarchar(128)   NOT NULL,

        -- Rollback data location
        [RollbackTableSchema]   nvarchar(128)   NOT NULL        CONSTRAINT [DF_RollbackManifest_RollbackTableSchema] DEFAULT (N'deploy'),
        [RollbackTableName]     nvarchar(255)   NOT NULL,       -- e.g. RB_42_Customers

        -- Capture metadata
        [RowsCaptured]          int             NULL,           -- Populated after SELECT INTO
        [CapturedAt]            datetime2(0)    NOT NULL        CONSTRAINT [DF_RollbackManifest_CapturedAt] DEFAULT (SYSUTCDATETIME()),
        [CapturedBy]            nvarchar(128)   NOT NULL        CONSTRAINT [DF_RollbackManifest_CapturedBy] DEFAULT (SUSER_SNAME()),
        [CapturedFrom]          nvarchar(128)   NOT NULL        CONSTRAINT [DF_RollbackManifest_CapturedFrom] DEFAULT (HOST_NAME()),

        -- Lifecycle
        [Status]                nvarchar(20)    NOT NULL        CONSTRAINT [DF_RollbackManifest_Status] DEFAULT (N'Active'),
        [StatusUpdatedAt]       datetime2(0)    NULL,
        [StatusUpdatedBy]       nvarchar(128)   NULL,

        -- Notes
        [Notes]                 nvarchar(1000)  NULL,

        -- Constraints
        CONSTRAINT [PK_RollbackManifest] PRIMARY KEY CLUSTERED ([ManifestId]),

        CONSTRAINT [CK_RollbackManifest_Status] CHECK (
            [Status] IN (N'Active', N'RolledBack', N'Expired', N'Archived')
        ),

        CONSTRAINT [CK_RollbackManifest_HasIdentifier] CHECK (
            [Ticket] IS NOT NULL OR [DeploymentId] IS NOT NULL OR [DeploymentLabel] IS NOT NULL
        )
    );

    PRINT '***** Table [deploy].[RollbackManifest] created.';

    -- Indexes for common access patterns

    -- Find all rollback entries for a given ticket
    CREATE NONCLUSTERED INDEX [IX_RollbackManifest_Ticket]
        ON [deploy].[RollbackManifest] ([Ticket])
        WHERE [Ticket] IS NOT NULL;

    -- Find all rollback entries for a pipeline run
    CREATE NONCLUSTERED INDEX [IX_RollbackManifest_DeploymentId]
        ON [deploy].[RollbackManifest] ([DeploymentId])
        WHERE [DeploymentId] IS NOT NULL;

    -- Cleanup queries: find Active entries older than retention period
    CREATE NONCLUSTERED INDEX [IX_RollbackManifest_Status_CapturedAt]
        ON [deploy].[RollbackManifest] ([Status], [CapturedAt]);

    PRINT '***** Indexes created on [deploy].[RollbackManifest].';

END
ELSE
    PRINT '***** Table [deploy].[RollbackManifest] already exists.';
GO

-------------------------------------------------------------------------------
-- deploy.RunOnceManifest
-------------------------------------------------------------------------------

IF NOT EXISTS (
    SELECT 1
    FROM sys.objects o
        INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id]
    WHERE s.[name] = N'deploy'
      AND o.[name] = N'RunOnceManifest'
      AND o.[type] = 'U'
)
BEGIN

    CREATE TABLE [deploy].[RunOnceManifest]
    (
        -- Identity
        [RunOnceId]             int             IDENTITY(1,1)   NOT NULL,

        -- Script identification — ScriptName is the natural key for the guard check
        [ScriptName]            nvarchar(255)   NOT NULL,       -- Filename: DataUpdate_PBI12345_BackfillWidgets.sql

        -- Deployment context
        [Ticket]                nvarchar(50)    NULL,           -- Work item (PBI-12345, JIRA-678, etc.)
        [DeploymentId]          nvarchar(100)   NULL,           -- Pipeline run ID, PR number, release name

        -- Target context
        [TargetDatabase]        nvarchar(128)   NULL,           -- Database the script modified

        -- Execution metadata
        [ExecutedAt]            datetime2(0)    NOT NULL        CONSTRAINT [DF_RunOnceManifest_ExecutedAt] DEFAULT (SYSUTCDATETIME()),
        [ExecutedBy]            nvarchar(128)   NOT NULL        CONSTRAINT [DF_RunOnceManifest_ExecutedBy] DEFAULT (SUSER_SNAME()),
        [ExecutedFrom]          nvarchar(128)   NOT NULL        CONSTRAINT [DF_RunOnceManifest_ExecutedFrom] DEFAULT (HOST_NAME()),
        [DurationMs]            int             NULL,           -- Elapsed time in milliseconds

        -- Result
        [Status]                nvarchar(20)    NOT NULL        CONSTRAINT [DF_RunOnceManifest_Status] DEFAULT (N'Success'),
        [ErrorMessage]          nvarchar(4000)  NULL,           -- NULL on success, error text on failure

        -- Notes
        [Notes]                 nvarchar(1000)  NULL,

        -- Constraints
        CONSTRAINT [PK_RunOnceManifest] PRIMARY KEY CLUSTERED ([RunOnceId]),

        CONSTRAINT [CK_RunOnceManifest_Status] CHECK (
            [Status] IN (N'Success', N'Failed')
        )
    );

    PRINT '***** Table [deploy].[RunOnceManifest] created.';

    -- The guard query: WHERE ScriptName = @ScriptName AND Status = 'Success'
    CREATE UNIQUE NONCLUSTERED INDEX [UX_RunOnceManifest_ScriptName_Success]
        ON [deploy].[RunOnceManifest] ([ScriptName])
        WHERE [Status] = N'Success';

    -- Find all entries for a given ticket
    CREATE NONCLUSTERED INDEX [IX_RunOnceManifest_Ticket]
        ON [deploy].[RunOnceManifest] ([Ticket])
        WHERE [Ticket] IS NOT NULL;

    -- Find all entries for a pipeline run
    CREATE NONCLUSTERED INDEX [IX_RunOnceManifest_DeploymentId]
        ON [deploy].[RunOnceManifest] ([DeploymentId])
        WHERE [DeploymentId] IS NOT NULL;

    PRINT '***** Indexes created on [deploy].[RunOnceManifest].';

END
ELSE
    PRINT '***** Table [deploy].[RunOnceManifest] already exists.';
GO

PRINT '***** Table setup complete.';
GO