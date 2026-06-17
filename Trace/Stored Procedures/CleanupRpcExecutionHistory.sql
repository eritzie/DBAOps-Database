USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deletes rows from trace.RpcExecutionHistory where EventTime is older than @RetentionDays.
    Uses batched deletes of 5,000 rows to avoid log pressure on large tables.
    Run as step 2 of the DBAOps - Capture - RpcExecutions Agent job.

Parameters:
    @RetentionDays   as INT   Days to retain. Rows older than this are deleted. Default: 90.

Usage Example:
    EXEC [trace].[CleanupRpcExecutionHistory] @RetentionDays = 90;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-09  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [trace].[CleanupRpcExecutionHistory]
    @RetentionDays  INT = 90
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Cutoff   DATETIME2(3) = DATEADD(DAY, -@RetentionDays, SYSUTCDATETIME());
    DECLARE @BatchCnt INT          = 1;

    PRINT '====================================================================================';
    PRINT 'RPC Execution History Cleanup';
    PRINT 'Retention    : ' + CAST(@RetentionDays AS varchar) + ' days';
    PRINT 'Cutoff       : ' + CONVERT(varchar, @Cutoff, 120);
    PRINT '====================================================================================';

    /*
      INTENT : Delete rows from trace.RpcExecutionHistory older than @RetentionDays
               in 5,000-row batches to limit log pressure.
      TARGET : DBAOps
      RISK   : None — monitoring history only, no application data
    */
    WHILE @BatchCnt > 0
    BEGIN
        DELETE TOP (5000)
        FROM [trace].[RpcExecutionHistory]
        WHERE [EventTime] < @Cutoff;

        SET @BatchCnt = @@ROWCOUNT;
    END;

    PRINT '***** Cleanup complete.';
    PRINT '====================================================================================';

END
