/*
===================================================================================================
DBAOps Database - Maintenance: Cleanup Expired Rollbacks

Description:
    Manages the lifecycle of rollback data captured by deployment scripts.

    Workflow:
    1. Marks Active entries older than @RetentionDays as 'Expired'
    2. Drops rollback data tables for Expired entries older than @GracePeriodDays
    3. Optionally deletes manifest rows for dropped tables (controlled by @PurgeManifest)

    The two-phase approach (Expire → Drop) ensures that:
    - Active rollback data is never touched
    - Expired data sits for a grace period before physical deletion
    - The manifest retains an audit trail even after data tables are dropped

    Run as a SQL Agent job on a schedule (weekly is typical), or manually.

Parameters:
    @RetentionDays      int     Days after capture before Active → Expired (default: 30)
    @GracePeriodDays    int     Days after Expired before rollback tables are dropped (default: 14)
    @PurgeManifest      bit     0 = keep manifest rows after drop (audit trail), 1 = delete them
    @WhatIf             bit     1 = print what would happen without making changes

Usage:
    -- Preview what would be cleaned up
    EXEC [deploy].[CleanupRollbackData] @WhatIf = 1;

    -- Run with defaults (30-day retention, 14-day grace, keep manifest rows)
    EXEC [deploy].[CleanupRollbackData];

    -- Aggressive cleanup: 7-day retention, no grace period, purge manifest
    EXEC [deploy].[CleanupRollbackData]
        @RetentionDays = 7,
        @GracePeriodDays = 0,
        @PurgeManifest = 1;

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

CREATE OR ALTER PROCEDURE [deploy].[CleanupRollbackData]
    @RetentionDays      int     = 30,
    @GracePeriodDays    int     = 14,
    @PurgeManifest      bit     = 0,
    @WhatIf             bit     = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now            datetime2(0)    = SYSUTCDATETIME();
    DECLARE @RetentionCutoff datetime2(0)   = DATEADD(DAY, -@RetentionDays, @Now);
    DECLARE @GraceCutoff    datetime2(0)    = DATEADD(DAY, -@GracePeriodDays, @Now);
    DECLARE @Sql            nvarchar(max);
    DECLARE @TableFQN       nvarchar(500);
    DECLARE @ManifestId     int;
    DECLARE @ExpiredCount   int = 0;
    DECLARE @DroppedCount   int = 0;
    DECLARE @PurgedCount    int = 0;

    PRINT '====================================================================================';
    PRINT 'Rollback Data Cleanup';
    PRINT 'Started At     : ' + CONVERT(varchar, @Now, 120);
    PRINT 'Retention Days : ' + CAST(@RetentionDays AS varchar);
    PRINT 'Grace Period   : ' + CAST(@GracePeriodDays AS varchar) + ' days';
    PRINT 'Purge Manifest : ' + CASE @PurgeManifest WHEN 1 THEN 'Yes' ELSE 'No' END;
    PRINT 'WhatIf Mode    : ' + CASE @WhatIf WHEN 1 THEN 'Yes (no changes will be made)' ELSE 'No' END;
    PRINT '====================================================================================';

    -----------------------------------------------------------------------
    -- Phase 1: Mark Active entries as Expired
    -----------------------------------------------------------------------
    PRINT '';
    PRINT '--- Phase 1: Expire Active entries older than ' + CAST(@RetentionDays AS varchar) + ' days ---';

    IF @WhatIf = 1
    BEGIN
        SELECT
            ManifestId,
            Ticket,
            DeploymentId,
            SourceDatabase,
            SourceSchema,
            SourceTable,
            RollbackTableName,
            CapturedAt,
            'Would expire' AS [Action]
        FROM [deploy].[RollbackManifest]
        WHERE [Status] = N'Active'
          AND [CapturedAt] < @RetentionCutoff;

        SELECT @ExpiredCount = @@ROWCOUNT;
    END
    ELSE
    BEGIN
        UPDATE [deploy].[RollbackManifest]
        SET [Status]          = N'Expired',
            [StatusUpdatedAt] = @Now,
            [StatusUpdatedBy] = SUSER_SNAME()
        WHERE [Status] = N'Active'
          AND [CapturedAt] < @RetentionCutoff;

        SET @ExpiredCount = @@ROWCOUNT;
    END

    PRINT '***** ' + CAST(@ExpiredCount AS varchar) + ' entries marked as Expired.';

    -----------------------------------------------------------------------
    -- Phase 2: Drop rollback data tables for Expired entries past grace
    -----------------------------------------------------------------------
    PRINT '';
    PRINT '--- Phase 2: Drop rollback tables expired more than ' + CAST(@GracePeriodDays AS varchar) + ' days ago ---';

    DECLARE cur_drop CURSOR LOCAL FAST_FORWARD FOR
        SELECT
            ManifestId,
            QUOTENAME([RollbackTableSchema]) + N'.' + QUOTENAME([RollbackTableName])
        FROM [deploy].[RollbackManifest]
        WHERE [Status] = N'Expired'
          AND [StatusUpdatedAt] < @GraceCutoff;

    OPEN cur_drop;
    FETCH NEXT FROM cur_drop INTO @ManifestId, @TableFQN;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Verify the table actually exists before trying to drop
        IF EXISTS (
            SELECT 1
            FROM sys.objects o
                INNER JOIN sys.schemas s ON o.[schema_id] = s.[schema_id]
            WHERE QUOTENAME(s.[name]) + N'.' + QUOTENAME(o.[name]) = @TableFQN
              AND o.[type] = 'U'
        )
        BEGIN
            IF @WhatIf = 1
                PRINT 'Would drop: ' + @TableFQN + ' (ManifestId: ' + CAST(@ManifestId AS varchar) + ')';
            ELSE
            BEGIN
                SET @Sql = N'DROP TABLE ' + @TableFQN + N';';
                EXEC sp_executesql @Sql;
                PRINT 'Dropped: ' + @TableFQN + ' (ManifestId: ' + CAST(@ManifestId AS varchar) + ')';
            END

            SET @DroppedCount += 1;
        END
        ELSE
        BEGIN
            PRINT 'Table not found (already dropped?): ' + @TableFQN + ' (ManifestId: ' + CAST(@ManifestId AS varchar) + ')';
        END

        -- Update status to Archived (table is gone)
        IF @WhatIf = 0
        BEGIN
            UPDATE [deploy].[RollbackManifest]
            SET [Status]          = N'Archived',
                [StatusUpdatedAt] = @Now,
                [StatusUpdatedBy] = SUSER_SNAME()
            WHERE [ManifestId] = @ManifestId;
        END

        FETCH NEXT FROM cur_drop INTO @ManifestId, @TableFQN;
    END

    CLOSE cur_drop;
    DEALLOCATE cur_drop;

    PRINT '***** ' + CAST(@DroppedCount AS varchar) + ' rollback tables dropped.';

    -----------------------------------------------------------------------
    -- Phase 3 (optional): Purge manifest rows for Archived entries
    -----------------------------------------------------------------------
    IF @PurgeManifest = 1
    BEGIN
        PRINT '';
        PRINT '--- Phase 3: Purge Archived manifest rows ---';

        IF @WhatIf = 1
        BEGIN
            SELECT COUNT(*) AS [WouldPurge]
            FROM [deploy].[RollbackManifest]
            WHERE [Status] = N'Archived';

            SET @PurgedCount = (SELECT COUNT(*) FROM [deploy].[RollbackManifest] WHERE [Status] = N'Archived');
        END
        ELSE
        BEGIN
            DELETE FROM [deploy].[RollbackManifest]
            WHERE [Status] = N'Archived';

            SET @PurgedCount = @@ROWCOUNT;
        END

        PRINT '***** ' + CAST(@PurgedCount AS varchar) + ' manifest rows purged.';
    END

    -----------------------------------------------------------------------
    -- Summary
    -----------------------------------------------------------------------
    PRINT '';
    PRINT '====================================================================================';
    PRINT 'Cleanup Summary:';
    PRINT '  Entries expired  : ' + CAST(@ExpiredCount AS varchar);
    PRINT '  Tables dropped   : ' + CAST(@DroppedCount AS varchar);
    PRINT '  Manifest purged  : ' + CAST(@PurgedCount AS varchar);
    PRINT 'Completed At       : ' + CONVERT(varchar, SYSUTCDATETIME(), 120);
    PRINT '====================================================================================';
END
GO

PRINT '***** Procedure [deploy].[CleanupRollbackData] created.';
GO