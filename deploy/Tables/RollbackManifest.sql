/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Central registry of all rollback data captures. Every time a deployment script
    captures before-image data, it registers here. The manifest tracks what deployment
    the data belongs to, where the data came from, where the rollback snapshot is stored,
    and lifecycle status (Active → RolledBack | Expired → Archived).

    Rollback data tables are created dynamically by deployment scripts using
    SELECT INTO [DBAOps].[deploy].[RB_<ManifestId>_<TableName>].
    Those tables are not defined here — they inherit schema from the source table.

Schema Notes:
    At least one of Ticket, DeploymentId, or DeploymentLabel must be non-null
    (enforced by CK_RollbackManifest_HasIdentifier).

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[deploy].[RollbackManifest]', 'U') IS NULL
BEGIN

    CREATE TABLE [deploy].[RollbackManifest]
    (
        [ManifestId]            int             IDENTITY(1,1)   NOT NULL,

        [Ticket]                nvarchar(50)    NULL,
        [DeploymentId]          nvarchar(100)   NULL,
        [DeploymentLabel]       nvarchar(255)   NULL,

        [SourceServer]          nvarchar(128)   NULL,
        [SourceDatabase]        nvarchar(128)   NOT NULL,
        [SourceSchema]          nvarchar(128)   NOT NULL,
        [SourceTable]           nvarchar(128)   NOT NULL,

        [RollbackTableSchema]   nvarchar(128)   NOT NULL        CONSTRAINT [DF_RollbackManifest_RollbackTableSchema] DEFAULT (N'deploy'),
        [RollbackTableName]     nvarchar(255)   NOT NULL,

        [RowsCaptured]          int             NULL,
        [CapturedAt]            datetime2(0)    NOT NULL        CONSTRAINT [DF_RollbackManifest_CapturedAt] DEFAULT (SYSUTCDATETIME()),
        [CapturedBy]            nvarchar(128)   NOT NULL        CONSTRAINT [DF_RollbackManifest_CapturedBy] DEFAULT (SUSER_SNAME()),
        [CapturedFrom]          nvarchar(128)   NOT NULL        CONSTRAINT [DF_RollbackManifest_CapturedFrom] DEFAULT (HOST_NAME()),

        [Status]                nvarchar(20)    NOT NULL        CONSTRAINT [DF_RollbackManifest_Status] DEFAULT (N'Active'),
        [StatusUpdatedAt]       datetime2(0)    NULL,
        [StatusUpdatedBy]       nvarchar(128)   NULL,

        [Notes]                 nvarchar(1000)  NULL,

        CONSTRAINT [PK_RollbackManifest] PRIMARY KEY CLUSTERED ([ManifestId]),

        CONSTRAINT [CK_RollbackManifest_Status] CHECK (
            [Status] IN (N'Active', N'RolledBack', N'Expired', N'Archived')
        ),

        CONSTRAINT [CK_RollbackManifest_HasIdentifier] CHECK (
            [Ticket] IS NOT NULL OR [DeploymentId] IS NOT NULL OR [DeploymentLabel] IS NOT NULL
        )
    );

    CREATE NONCLUSTERED INDEX [IX_RollbackManifest_Ticket]
        ON [deploy].[RollbackManifest] ([Ticket])
        WHERE [Ticket] IS NOT NULL;

    CREATE NONCLUSTERED INDEX [IX_RollbackManifest_DeploymentId]
        ON [deploy].[RollbackManifest] ([DeploymentId])
        WHERE [DeploymentId] IS NOT NULL;

    CREATE NONCLUSTERED INDEX [IX_RollbackManifest_Status_CapturedAt]
        ON [deploy].[RollbackManifest] ([Status], [CapturedAt]);

    PRINT '***** Table [deploy].[RollbackManifest] created.';

END
ELSE
    PRINT '***** Table [deploy].[RollbackManifest] already exists.';
GO
