/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Removes old entries from deploy.RunOnceManifest.

    Unlike RollbackManifest, there are no child data tables to drop — this is purely
    row cleanup. Failed entries are removed after @RetentionDays. Successful entries
    are retained longer (@SuccessRetentionDays) since they serve as the guard that
    prevents re-execution.

    WARNING: Deleting a Success row for a script means that script will execute again
    on the next deployment. Only clean up Success rows when you are certain the script
    will never be included in a future deployment (i.e., it has been removed from the
    repo or the RunOnce folder).

Parameters:
    @RetentionDays          int     Days before Failed entries are deleted (default: 90)
    @SuccessRetentionDays   int     Days before Success entries are deleted (default: 365)
                                    Set to -1 to retain Success rows indefinitely.
    @WhatIf                 bit     1 = preview without making changes

Usage Example:
    -- Preview what would be cleaned up
    EXEC [deploy].[CleanupRunOnceManifest] @WhatIf = 1;

    -- Run with defaults (90 days for failures, 365 for successes)
    EXEC [deploy].[CleanupRunOnceManifest];

    -- Keep successes forever, purge failures after 30 days
    EXEC [deploy].[CleanupRunOnceManifest]
        @RetentionDays = 30,
        @SuccessRetentionDays = -1;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-17  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

USE [DBAOps];
GO

CREATE OR ALTER PROCEDURE [deploy].[CleanupRunOnceManifest]
    @RetentionDays          int     = 90,
    @SuccessRetentionDays   int     = 365,
    @WhatIf                 bit     = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now            datetime2(0)    = SYSUTCDATETIME();
    DECLARE @FailedCutoff   datetime2(0)    = DATEADD(DAY, -@RetentionDays, @Now);
    DECLARE @SuccessCutoff  datetime2(0)    = DATEADD(DAY, -@SuccessRetentionDays, @Now);
    DECLARE @FailedCount    int             = 0;
    DECLARE @SuccessCount   int             = 0;

    PRINT '====================================================================================';
    PRINT 'RunOnce Manifest Cleanup';
    PRINT 'Started At             : ' + CONVERT(varchar, @Now, 120);
    PRINT 'Failed retention       : ' + CAST(@RetentionDays AS varchar) + ' days';
    PRINT 'Success retention      : ' + CASE WHEN @SuccessRetentionDays = -1 THEN 'Indefinite' ELSE CAST(@SuccessRetentionDays AS varchar) + ' days' END;
    PRINT 'WhatIf Mode            : ' + CASE @WhatIf WHEN 1 THEN 'Yes (no changes will be made)' ELSE 'No' END;
    PRINT '====================================================================================';

    -----------------------------------------------------------------------
    -- Phase 1: Delete old Failed entries
    -----------------------------------------------------------------------
    PRINT '';
    PRINT '--- Phase 1: Remove Failed entries older than ' + CAST(@RetentionDays AS varchar) + ' days ---';

    IF @WhatIf = 1
    BEGIN
        SELECT
            [RunOnceId],
            [ScriptName],
            [Ticket],
            [DeploymentId],
            [ExecutedAt],
            [Status],
            LEFT([ErrorMessage], 100) AS [ErrorMessage_Truncated],
            'Would delete' AS [Action]
        FROM [deploy].[RunOnceManifest]
        WHERE [Status] = N'Failed'
          AND [ExecutedAt] < @FailedCutoff;

        SET @FailedCount = @@ROWCOUNT;
    END
    ELSE
    BEGIN
        DELETE FROM [deploy].[RunOnceManifest]
        WHERE [Status] = N'Failed'
          AND [ExecutedAt] < @FailedCutoff;

        SET @FailedCount = @@ROWCOUNT;
    END

    PRINT '***** ' + CAST(@FailedCount AS varchar) + ' Failed entries removed.';

    -----------------------------------------------------------------------
    -- Phase 2: Delete old Success entries (if retention is not indefinite)
    -----------------------------------------------------------------------
    IF @SuccessRetentionDays >= 0
    BEGIN
        PRINT '';
        PRINT '--- Phase 2: Remove Success entries older than ' + CAST(@SuccessRetentionDays AS varchar) + ' days ---';

        IF @WhatIf = 1
        BEGIN
            SELECT
                [RunOnceId],
                [ScriptName],
                [Ticket],
                [DeploymentId],
                [ExecutedAt],
                [Status],
                'Would delete' AS [Action]
            FROM [deploy].[RunOnceManifest]
            WHERE [Status] = N'Success'
              AND [ExecutedAt] < @SuccessCutoff;

            SET @SuccessCount = @@ROWCOUNT;
        END
        ELSE
        BEGIN
            DELETE FROM [deploy].[RunOnceManifest]
            WHERE [Status] = N'Success'
              AND [ExecutedAt] < @SuccessCutoff;

            SET @SuccessCount = @@ROWCOUNT;
        END

        PRINT '***** ' + CAST(@SuccessCount AS varchar) + ' Success entries removed.';
    END
    ELSE
    BEGIN
        PRINT '';
        PRINT '--- Phase 2: Skipped (Success retention set to indefinite) ---';
    END

    -----------------------------------------------------------------------
    -- Summary
    -----------------------------------------------------------------------
    PRINT '';
    PRINT '====================================================================================';
    PRINT 'Cleanup Summary:';
    PRINT '  Failed deleted   : ' + CAST(@FailedCount AS varchar);
    PRINT '  Success deleted  : ' + CAST(@SuccessCount AS varchar);
    PRINT 'Completed At       : ' + CONVERT(varchar, SYSUTCDATETIME(), 120);
    PRINT '====================================================================================';
END
GO

PRINT '***** Procedure [deploy].[CleanupRunOnceManifest] created.';
GO
