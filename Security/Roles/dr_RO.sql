/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting read-only (SELECT) access to schemas assigned to this role.
    Assign to logins or application accounts that require query access only.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_RO' AND type = 'R')
    CREATE ROLE [dr_RO] AUTHORIZATION [dbo];
GO
