/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting read and execute (SELECT, EXECUTE) access to schemas assigned
    to this role. Assign to accounts that query data and call stored procedures but do
    not write data.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_RE' AND type = 'R')
    CREATE ROLE [dr_RE] AUTHORIZATION [dbo];
GO
