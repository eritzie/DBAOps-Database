USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deletes rows from trace.DeadlockHistory where EventTime is older than @RetentionDays.
    Used as step 2 of the DBAOps - Capture - Deadlocks Agent job.

Parameters:
    @RetentionDays   as INT   Days to retain. Rows older than this are deleted. Default: 90.
    @WhatIf          as BIT   When 1, reports counts without deleting. Default: 0.

Usage Example:
    EXEC [trace].[CleanupDeadlockHistory] @RetentionDays = 90;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [trace].[CleanupDeadlockHistory]
    @RetentionDays  int = 90,
    @WhatIf         bit = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cutoff datetime2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowCount int;

    PRINT '====================================================================================';
    PRINT 'Deadlock History Cleanup';
    PRINT 'Retention    : ' + CAST(@RetentionDays AS varchar) + ' days';
    PRINT 'Cutoff       : ' + CONVERT(varchar, @Cutoff, 120);
    PRINT 'WhatIf Mode  : ' + CASE @WhatIf WHEN 1 THEN 'Yes' ELSE 'No' END;
    PRINT '====================================================================================';

    IF @WhatIf = 1
    BEGIN
        SELECT
            COUNT(*) AS [RowsToDelete],
            MIN([EventTime]) AS [OldestEvent],
            MAX([EventTime]) AS [NewestDeleted]
        FROM [trace].[DeadlockHistory]
        WHERE [EventTime] < @Cutoff;
    END
    ELSE
    BEGIN
        DELETE FROM [trace].[DeadlockHistory]
        WHERE [EventTime] < @Cutoff;

        SET @RowCount = @@ROWCOUNT;
        PRINT '***** Deleted ' + CAST(@RowCount AS varchar) + ' deadlock record(s).';
    END

    PRINT '====================================================================================';
END
