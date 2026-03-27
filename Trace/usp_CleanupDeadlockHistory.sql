/*
===================================================================================================
DBAOps Database - Trace: Cleanup Deadlock History

Description:
    Removes deadlock history entries older than @RetentionDays.
    Deadlock XML can be large — periodic cleanup keeps the table manageable.

Parameters:
    @RetentionDays  int     Days of deadlock data to retain (default: 90)
    @WhatIf         bit     1 = preview without making changes

Usage:
    EXEC [trace].[usp_CleanupDeadlockHistory] @WhatIf = 1;
    EXEC [trace].[usp_CleanupDeadlockHistory] @RetentionDays = 30;

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

CREATE OR ALTER PROCEDURE [trace].[usp_CleanupDeadlockHistory]
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
GO

PRINT '***** Procedure [trace].[usp_CleanupDeadlockHistory] created.';
GO