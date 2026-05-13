/*
================================================================================
  DBAOps \ Trace \ CleanupSaActivity.sql

  Purpose : Purges rows from trace.SaLoginHistory older than @RetentionDays.
            Follows the same pattern as CleanupDeadlockHistory and
            CleanupWaitStats -- configurable retention, @WhatIf preview,
            safe defaults.

  Schedule: SQL Agent job, weekly (Saturday night recommended, with other
            DBAOps cleanup jobs). See Setup\05_CreateAgentJobs.sql.

  Parameters
  ----------
    @RetentionDays   INT   Rows older than this many days are deleted.
                           Default 90. Pass -1 to retain indefinitely (no-op).

    @WhatIf          BIT   1 = report row count to be deleted without deleting.
                           Default 0.

  Usage
  -----
    -- Preview: how many rows would be deleted with default retention?
    EXEC [DBAOps].[trace].[CleanupSaActivity] @WhatIf = 1;

    -- Preview with custom retention
    EXEC [DBAOps].[trace].[CleanupSaActivity] @RetentionDays = 180, @WhatIf = 1;

    -- Execute cleanup with default 90-day retention
    EXEC [DBAOps].[trace].[CleanupSaActivity];

    -- Retain indefinitely (skip cleanup)
    EXEC [DBAOps].[trace].[CleanupSaActivity] @RetentionDays = -1;

  Note    : Consider extending retention while the sa remediation project is
            active -- the data supports auditor evidence requests. 180 days
            is reasonable for that period. Revert to 90 once sa is disabled.

  Author  : Eric Ritzie
  Date    : 2026-05-13
  Version : 1.0
================================================================================
*/

USE [DBAOps];
GO

CREATE OR ALTER PROCEDURE [trace].[CleanupSaActivity]
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
        FROM [trace].[SaLoginHistory]
        WHERE [EventTime] < @Cutoff;

        PRINT 'WhatIf mode -- no rows deleted.';
        PRINT '  Cutoff date    : ' + CONVERT(VARCHAR(30), @Cutoff, 120);
        PRINT '  Rows to delete : ' + CAST(@RowCount AS VARCHAR(10));
        RETURN;
    END;

    DELETE FROM [trace].[SaLoginHistory]
    WHERE [EventTime] < @Cutoff;

    SET @RowCount = @@ROWCOUNT;

    PRINT 'CleanupSaActivity: deleted ' + CAST(@RowCount AS VARCHAR(10))
        + ' row(s) older than ' + CAST(@RetentionDays AS VARCHAR(10)) + ' days'
        + ' (cutoff: ' + CONVERT(VARCHAR(30), @Cutoff, 120) + ').';

END;
GO
