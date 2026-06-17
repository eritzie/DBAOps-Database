USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deletes rows from monitor.WaitStatsSnapshot where CapturedAt is older than
    @RetentionDays. Deletes at the row level rather than by SnapshotId, so a snapshot
    that straddles the retention boundary may be partially present. Used as step 2 of
    the DBAOps - Capture - WaitStats Agent job.

Parameters:
    @RetentionDays   as INT   Days to retain. Snapshots older than this are deleted. Default: 30.
    @WhatIf          as BIT   When 1, reports counts without deleting. Default: 0.

Usage Example:
    EXEC [monitor].[CleanupWaitStats] @RetentionDays = 30;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

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
