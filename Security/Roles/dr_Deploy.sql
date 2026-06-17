/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting full DML and execute access to the deploy schema
    (SELECT, INSERT, UPDATE, DELETE, EXECUTE). Assign to deployment service accounts
    and tooling that manages run-once scripts and rollback data.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_Deploy' AND type = 'R')
    CREATE ROLE [dr_Deploy] AUTHORIZATION [dbo];
GO
