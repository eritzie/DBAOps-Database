/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting read, write, and execute (SELECT, INSERT, UPDATE, EXECUTE)
    access to schemas assigned to this role. Standard role for application accounts
    that read, write, and call stored procedures.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_RWE' AND type = 'R')
    CREATE ROLE [dr_RWE] AUTHORIZATION [dbo];
GO
