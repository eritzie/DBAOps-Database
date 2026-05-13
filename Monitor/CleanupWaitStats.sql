/*
===================================================================================================
DBAOps Database - Monitor: Cleanup Wait Stats Snapshots

Description:
    Removes wait stats snapshot data older than @RetentionDays.
    At a 15-minute capture interval with ~200 wait types, 30 days generates
    roughly 600K rows — manageable but worth trimming periodically.

Parameters:
    @RetentionDays  int     Days of snapshot data to retain (default: 30)
    @WhatIf         bit     1 = preview without making changes

Usage:
    EXEC [monitor].[CleanupWaitStats] @WhatIf = 1;
    EXEC [monitor].[CleanupWaitStats] @RetentionDays = 14;

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

CREATE OR ALTER PROCEDURE [monitor].[CleanupWaitStats]
    @RetentionDays  int = 30,
    @WhatIf         bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cutoff datetime2(0) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowCount int;

    PRINT '====================================================================================';
    PRINT 'Wait Stats Snapshot Cleanup';
    PRINT 'Retention    : ' + CAST(@RetentionDays AS varchar) + ' days';
    PRINT 'Cutoff       : ' + CONVERT(varchar, @Cutoff, 120);
    PRINT 'WhatIf Mode  : ' + CASE @WhatIf WHEN 1 THEN 'Yes' ELSE 'No' END;
    PRINT '====================================================================================';

    IF @WhatIf = 1
    BEGIN
        SELECT
            COUNT(*) AS [RowsToDelete],
            MIN([CapturedAt]) AS [OldestSnapshot],
            MAX([CapturedAt]) AS [NewestDeleted],
            COUNT(DISTINCT [SnapshotId]) AS [SnapshotsToDelete]
        FROM [monitor].[WaitStatsSnapshot]
        WHERE [CapturedAt] < @Cutoff;
    END
    ELSE
    BEGIN
        DELETE FROM [monitor].[WaitStatsSnapshot]
        WHERE [CapturedAt] < @Cutoff;

        SET @RowCount = @@ROWCOUNT;
        PRINT '***** Deleted ' + CAST(@RowCount AS varchar) + ' rows.';
    END

    PRINT '====================================================================================';
END
GO

PRINT '***** Procedure [monitor].[CleanupWaitStats] created.';
GO