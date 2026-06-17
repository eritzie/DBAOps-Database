USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns the most recent backup of each type (Full, Differential, Log) per online user
    database. When @HoursBack is specified, adds a FullBackupOverdue flag for databases
    where the most recent full backup is older than the threshold or missing entirely.
    Databases with no backup history are included via a LEFT JOIN so gaps are visible.

Parameters:
    @HoursBack   as int   Hours threshold for the overdue flag. NULL = show all databases with
                          last backup dates and no threshold applied. Default: NULL.

Usage Example:
    EXEC [dbo].[GetBackupStatus];
    EXEC [dbo].[GetBackupStatus] @HoursBack = 24;

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetBackupStatus]
    @HoursBack int = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH LastBackup AS (
        SELECT
             database_name
            ,type                                                -- D=Full, I=Diff, L=Log
            ,MAX(backup_finish_date)             AS LastBackupDate
        FROM [msdb].[dbo].[backupset]
        WHERE is_copy_only = 0                                   -- exclude copy-only backups; they are not part of a restore chain and should not update currency tracking
        GROUP BY database_name, type
    ),
    Pivoted AS (
        SELECT
             database_name
            ,MAX(CASE type WHEN 'D' THEN LastBackupDate END)    AS LastFullBackup
            ,MAX(CASE type WHEN 'I' THEN LastBackupDate END)    AS LastDiffBackup
            ,MAX(CASE type WHEN 'L' THEN LastBackupDate END)    AS LastLogBackup
        FROM LastBackup
        GROUP BY database_name
    )
    SELECT
         d.name                                                  AS DatabaseName
        ,d.recovery_model_desc                                   AS RecoveryModel
        ,p.LastFullBackup
        ,p.LastDiffBackup
        ,p.LastLogBackup
        ,DATEDIFF(HOUR, p.LastFullBackup, SYSUTCDATETIME())     AS HoursSinceFullBackup
        ,CASE
            WHEN @HoursBack IS NOT NULL
             AND (p.LastFullBackup IS NULL
                  OR DATEDIFF(HOUR, p.LastFullBackup, SYSUTCDATETIME()) > @HoursBack)
            THEN 1 ELSE 0
         END                                                     AS FullBackupOverdue
    FROM [sys].[databases]                                       d
    LEFT JOIN Pivoted                                            p  ON d.name = p.database_name -- LEFT JOIN ensures databases with no backup history appear with NULL dates
    WHERE d.database_id > 4
      AND d.state_desc = N'ONLINE'
    ORDER BY FullBackupOverdue DESC, HoursSinceFullBackup DESC;
END
