/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Ola Hallengren Maintenance Solution command log. Records each command executed by
    DatabaseBackup, DatabaseIntegrityCheck, and IndexOptimize stored procedures.
    Do not modify this table's schema — apply changes by replacing the full script
    from the Hallengren release package (https://ola.hallengren.com).

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF OBJECT_ID(N'[dbo].[CommandLog]', 'U') IS NULL
BEGIN

    CREATE TABLE [dbo].[CommandLog] (
        [ID]              INT            IDENTITY (1, 1) NOT NULL,
        [DatabaseName]    [sysname]      NULL,
        [SchemaName]      [sysname]      NULL,
        [ObjectName]      [sysname]      NULL,
        [ObjectType]      CHAR (2)       NULL,
        [IndexName]       [sysname]      NULL,
        [IndexType]       TINYINT        NULL,
        [StatisticsName]  [sysname]      NULL,
        [PartitionNumber] INT            NULL,
        [ExtendedInfo]    XML            NULL,
        [Command]         NVARCHAR (MAX) NOT NULL,
        [CommandType]     NVARCHAR (60)  NOT NULL,
        [StartTime]       DATETIME2 (7)  NOT NULL,
        [EndTime]         DATETIME2 (7)  NULL,
        [ErrorNumber]     INT            NULL,
        [ErrorMessage]    NVARCHAR (MAX) NULL,
        CONSTRAINT [PK_CommandLog] PRIMARY KEY CLUSTERED ([ID] ASC)
    );

END
GO
