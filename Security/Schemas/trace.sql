/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Schema for security auditing and event capture objects. Contains tables and stored
    procedures for capturing sa login activity, deadlock history, and other security
    audit data from XE sessions.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'trace')
    EXEC sp_executesql N'CREATE SCHEMA [trace] AUTHORIZATION [dbo]';
GO
