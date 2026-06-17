/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Database role granting read and write (SELECT, INSERT, UPDATE) access to schemas
    assigned to this role. Does not include DELETE or EXECUTE.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'dr_RW' AND type = 'R')
    CREATE ROLE [dr_RW] AUTHORIZATION [dbo];
GO
