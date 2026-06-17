USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns version store space consumption by database and TempDB totals. Three result
    sets: (1) per-database usage; (2) TempDB file space breakdown; (3) databases with
    snapshot isolation enabled.

Usage Example:
    EXEC [dbo].[GetVersionStoreUsage];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetVersionStoreUsage]
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: per-database version store usage.
    -- sys.dm_tran_version_store_space_usage requires SQL Server 2016 SP2 or later.
    -- This DMV exposes only reserved_page_count; there is no separate used_page_count column.
    SELECT
         DB_NAME(database_id)                AS DatabaseName
        ,reserved_page_count * 8 / 1024      AS ReservedMB
    FROM sys.dm_tran_version_store_space_usage
    ORDER BY reserved_page_count DESC;

    -- Result set 2: TempDB file space totals.
    -- sys.dm_db_file_space_usage is database-scoped; querying it from DBAOps context returns
    -- DBAOps file data, not tempdb. USE tempdb inside the dynamic batch switches context so
    -- the DMV returns tempdb pages. SUM aggregates across all tempdb data files.
    -- version_store_reserved_page_count is the only version store column in this DMV;
    -- there is no version_store_used_page_count.
    DECLARE @TempdbSQL nvarchar(MAX) = N'
    USE tempdb;
    SELECT
         SUM(version_store_reserved_page_count)  * 8 / 1024   AS VersionStoreReservedMB
        ,SUM(user_object_reserved_page_count)     * 8 / 1024   AS UserObjectReservedMB
        ,SUM(internal_object_reserved_page_count) * 8 / 1024   AS InternalObjectReservedMB
    FROM [sys].[dm_db_file_space_usage];';

    EXEC sp_executesql @TempdbSQL;

    -- Result set 3: databases with snapshot isolation enabled
    SELECT
         name                                AS DatabaseName
        ,snapshot_isolation_state_desc       AS SnapshotState
        ,is_read_committed_snapshot_on       AS RCSIEnabled
    FROM sys.databases
    WHERE snapshot_isolation_state > 0
       OR is_read_committed_snapshot_on = 1
    ORDER BY name;
END
