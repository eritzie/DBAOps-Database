USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns top @Top queries from the plan cache sorted by the specified metric. Reports
    total and average CPU, logical reads, and logical writes for all rows.

Parameters:
    @Top    as INT          Number of rows to return. Default: 25.
    @SortBy as NVARCHAR(32) Sort metric. Valid values: CPU, LogicalReads, LogicalWrites. Default: CPU.

Usage Example:
    EXEC [dbo].[GetTopQuery] @Top = 10, @SortBy = N'LogicalReads';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetTopQuery]
    @Top    int          = 25,
    @SortBy nvarchar(32) = N'CPU'   -- Valid values: CPU, LogicalReads, LogicalWrites
AS
BEGIN
    SET NOCOUNT ON;

    IF @SortBy NOT IN (N'CPU', N'LogicalReads', N'LogicalWrites')
    BEGIN
        RAISERROR('@SortBy must be CPU, LogicalReads, or LogicalWrites.', 16, 1);
        RETURN;
    END

    SELECT TOP (@Top)
         DB_NAME(t.dbid)                             AS DatabaseName
        ,qs.execution_count                          AS ExecutionCount
        -- worker_time and elapsed_time are in microseconds; divide by 1,000,000 for seconds
        ,qs.total_worker_time        / 1000000       AS TotalCpuSec
        ,qs.total_worker_time        / 1000000
            / qs.execution_count                     AS AvgCpuSec
        ,qs.total_logical_reads                      AS TotalLogicalReads
        ,qs.total_logical_reads      / qs.execution_count
                                                     AS AvgLogicalReads
        ,qs.total_logical_writes                     AS TotalLogicalWrites
        ,qs.total_logical_writes     / qs.execution_count
                                                     AS AvgLogicalWrites
        ,qs.total_elapsed_time       / 1000000
            / qs.execution_count                     AS AvgElapsedSec
        ,SUBSTRING(t.text,
            (qs.statement_start_offset / 2) + 1,
            ((CASE qs.statement_end_offset
                WHEN -1 THEN DATALENGTH(t.text)
                ELSE qs.statement_end_offset
              END - qs.statement_start_offset) / 2) + 1
         )                                           AS QueryText
    FROM sys.dm_exec_query_stats                    qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) t
    ORDER BY
        CASE @SortBy
            WHEN N'CPU'           THEN qs.total_worker_time
            WHEN N'LogicalReads'  THEN qs.total_logical_reads
            WHEN N'LogicalWrites' THEN qs.total_logical_writes
        END DESC;
END
