USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deletes rows from trace.BlockingHistory where EventTime is older than @RetentionDays.
    Used as step 2 of the DBAOps - Capture - Blocking History Agent job.

Parameters:
    @RetentionDays   as INT   Days to retain. Rows older than this are deleted. Default: 90.
    @WhatIf          as BIT   When 1, reports counts without deleting. Default: 0.

Usage Example:
    EXEC [trace].[CleanupBlockingHistory] @RetentionDays = 90;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [trace].[CleanupBlockingHistory]
    @RetentionDays  INT = 90,
    @WhatIf         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cutoff DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowCount INT;

    PRINT '====================================================================================';
    PRINT 'Blocking History Cleanup';
    PRINT 'Retention    : ' + CAST(@RetentionDays AS varchar) + ' days';
    PRINT 'Cutoff       : ' + CONVERT(varchar, @Cutoff, 120);
    PRINT 'WhatIf Mode  : ' + CASE @WhatIf WHEN 1 THEN 'Yes' ELSE 'No' END;
    PRINT '====================================================================================';

    IF @WhatIf = 1
    BEGIN
        SELECT
            COUNT(*)         AS [RowsToDelete],
            MIN([EventTime]) AS [OldestEvent],
            MAX([EventTime]) AS [NewestDeleted]
        FROM [trace].[BlockingHistory]
        WHERE [EventTime] < @Cutoff;
    END
    ELSE
    BEGIN
        /*
          INTENT : Remove blocking history rows older than @RetentionDays
          TARGET : SQL-DEV-01 (default); verify target before executing on other instances
          RISK   : None — DBAOps.trace only, no application data
        */
        DELETE FROM [trace].[BlockingHistory]
        WHERE [EventTime] < @Cutoff;

        SET @RowCount = @@ROWCOUNT;
        PRINT '***** Deleted ' + CAST(@RowCount AS varchar) + ' blocking record(s).';
    END

    PRINT '====================================================================================';
END
