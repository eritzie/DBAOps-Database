/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting DELETE access. Additive — assign alongside dr_RW or
    dr_RWE for accounts that require row deletion in addition to their base role.
    Never assign in isolation.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_Del' AND type = 'R')
    CREATE ROLE [dr_Del] AUTHORIZATION [dbo];
GO
