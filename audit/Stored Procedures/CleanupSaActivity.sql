USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deletes rows from audit.SaLoginHistory where EventTime is older than @RetentionDays.
    Pass @RetentionDays = -1 to retain all rows indefinitely. Used as step 2 of the
    DBAOps - Capture - SaActivity Agent job.

Parameters:
    @RetentionDays   as INT   Days to retain. Rows older than this are deleted. Default: 90. -1 = retain all.
    @WhatIf          as BIT   When 1, prints counts without deleting. Default: 0.

Usage Example:
    EXEC [audit].[CleanupSaActivity] @RetentionDays = 90;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
    2026-06-18  Eric Ritzie (eritzie)            Moved from trace schema to audit schema
===============================================================================================*/

CREATE OR ALTER PROCEDURE [audit].[CleanupSaActivity]
    @RetentionDays  INT = 90,
    @WhatIf         BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @RetentionDays = -1
    BEGIN
        PRINT 'CleanupSaActivity: @RetentionDays = -1, retaining all rows.';
        RETURN;
    END;

    DECLARE @Cutoff    DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @RowCount  INT;

    IF @WhatIf = 1
    BEGIN
        SELECT @RowCount = COUNT(*)
        FROM [audit].[SaLoginHistory]
        WHERE [EventTime] < @Cutoff;

        PRINT 'WhatIf mode -- no rows deleted.';
        PRINT '  Cutoff date    : ' + CONVERT(VARCHAR(30), @Cutoff, 120);
        PRINT '  Rows to delete : ' + CAST(@RowCount AS VARCHAR(10));
        RETURN;
    END;

    /*
      INTENT : Remove sa activity history older than @RetentionDays
      TARGET : audit.SaLoginHistory
      RISK   : None outside retention window
    */
    DELETE FROM [audit].[SaLoginHistory]
    WHERE [EventTime] < @Cutoff;

    SET @RowCount = @@ROWCOUNT;

    PRINT 'CleanupSaActivity: deleted ' + CAST(@RowCount AS VARCHAR(10))
        + ' row(s) older than ' + CAST(@RetentionDays AS VARCHAR(10)) + ' days'
        + ' (cutoff: ' + CONVERT(VARCHAR(30), @Cutoff, 120) + ').';

END;
