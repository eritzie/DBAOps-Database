/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting execute-only (EXECUTE) access to schemas assigned to this
    role. Assign to accounts that call stored procedures only and have no direct table
    access.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_EO' AND type = 'R')
    CREATE ROLE [dr_EO] AUTHORIZATION [dbo];
GO
