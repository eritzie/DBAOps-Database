/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Schema for DDL and permission change audit objects. Contains the SchemaChangeHistory
    table and the trg_SchemaChangeCapture database-scoped DDL trigger.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-17  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'audit')
    EXEC sp_executesql N'CREATE SCHEMA [audit] AUTHORIZATION [dbo]';
GO
