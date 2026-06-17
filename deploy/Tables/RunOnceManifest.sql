/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Registry of run-once deployment scripts. Each script checks this table on startup —
    if a row exists with Status = 'Success' for that script name, execution is skipped.
    Failed runs are recorded but do not block retries. Enables idempotent run-once scripts
    in CI/CD pipelines without manual tracking or archive steps.

    Each environment (Dev, Test, Prod) has its own DBAOps instance, so the same script
    runs once per environment automatically.

Schema Notes:
    UX_RunOnceManifest_ScriptName_Success is the guard index. The unique filtered index
    on ScriptName WHERE Status = 'Success' means only one successful execution can be
    recorded per script. This is what the RunOnce guard check queries.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[deploy].[RunOnceManifest]', 'U') IS NULL
BEGIN

    CREATE TABLE [deploy].[RunOnceManifest]
    (
        [RunOnceId]             int             IDENTITY(1,1)   NOT NULL,

        [ScriptName]            nvarchar(255)   NOT NULL,

        [Ticket]                nvarchar(50)    NULL,
        [DeploymentId]          nvarchar(100)   NULL,

        [TargetDatabase]        nvarchar(128)   NULL,

        [ExecutedAt]            datetime2(0)    NOT NULL        CONSTRAINT [DF_RunOnceManifest_ExecutedAt] DEFAULT (SYSUTCDATETIME()),
        [ExecutedBy]            nvarchar(128)   NOT NULL        CONSTRAINT [DF_RunOnceManifest_ExecutedBy] DEFAULT (SUSER_SNAME()),
        [ExecutedFrom]          nvarchar(128)   NOT NULL        CONSTRAINT [DF_RunOnceManifest_ExecutedFrom] DEFAULT (HOST_NAME()),
        [DurationMs]            int             NULL,

        [Status]                nvarchar(20)    NOT NULL        CONSTRAINT [DF_RunOnceManifest_Status] DEFAULT (N'Success'),
        [ErrorMessage]          nvarchar(4000)  NULL,

        [Notes]                 nvarchar(1000)  NULL,

        CONSTRAINT [PK_RunOnceManifest] PRIMARY KEY CLUSTERED ([RunOnceId]),

        CONSTRAINT [CK_RunOnceManifest_Status] CHECK (
            [Status] IN (N'Success', N'Failed')
        )
    );

    CREATE UNIQUE NONCLUSTERED INDEX [UX_RunOnceManifest_ScriptName_Success]
        ON [deploy].[RunOnceManifest] ([ScriptName])
        WHERE [Status] = N'Success';

    CREATE NONCLUSTERED INDEX [IX_RunOnceManifest_Ticket]
        ON [deploy].[RunOnceManifest] ([Ticket])
        WHERE [Ticket] IS NOT NULL;

    CREATE NONCLUSTERED INDEX [IX_RunOnceManifest_DeploymentId]
        ON [deploy].[RunOnceManifest] ([DeploymentId])
        WHERE [DeploymentId] IS NOT NULL;

    PRINT '***** Table [deploy].[RunOnceManifest] created.';

END
ELSE
    PRINT '***** Table [deploy].[RunOnceManifest] already exists.';
GO
