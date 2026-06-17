/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Schema for performance monitoring objects. Contains tables and stored procedures
    for capturing and retaining wait statistics snapshots and other performance data.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'monitor')
    EXEC sp_executesql N'CREATE SCHEMA [monitor] AUTHORIZATION [dbo]';
GO
