USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns TempDB file configuration and instance scheduler context. Two result sets:
    (1) file detail with autogrowth analysis; (2) scheduler count for recommended
    file count guidance.

Usage Example:
    EXEC [dbo].[GetTempdbConfig];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetTempdbConfig]
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: TempDB file detail with autogrowth analysis
    SELECT
         f.name                              AS LogicalName
        ,f.type_desc                         AS FileType
        ,f.physical_name                     AS PhysicalName
        ,f.size          * 8 / 1024          AS SizeMB
        ,f.max_size
        ,CASE f.is_percent_growth
            WHEN 1 THEN CAST(f.growth AS VARCHAR(10)) + '%'
            ELSE        CAST(f.growth * 8 / 1024 AS VARCHAR(10)) + ' MB'
         END                                 AS AutoGrowth
        ,CASE f.is_percent_growth
            WHEN 1 THEN 1 ELSE 0
         END                                 AS IsPercentGrowth   -- 1 = not recommended for TempDB
        -- FILEPROPERTY works correctly here because we target tempdb.sys.database_files
        ,FILEPROPERTY(f.name, 'SpaceUsed') * 8 / 1024
                                             AS UsedMB
    FROM tempdb.sys.database_files           f
    ORDER BY f.type, f.file_id;

    -- Result set 2: Scheduler count = recommended number of TempDB data files (cap at 8)
    SELECT
         cpu_count                           AS CpuCount
        ,scheduler_count                     AS SchedulerCount
        ,max_workers_count                   AS MaxWorkerThreads
    FROM sys.dm_os_sys_info;
END
