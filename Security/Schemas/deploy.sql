/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Schema for deployment infrastructure objects. Contains tables and stored procedures
    supporting run-once script tracking (RunOnceManifest) and pre-deployment rollback
    data capture (RollbackManifest).

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'deploy')
    EXEC sp_executesql N'CREATE SCHEMA [deploy] AUTHORIZATION [dbo]';
GO

GRANT UPDATE  ON SCHEMA::[deploy] TO [dr_Deploy];
GRANT SELECT  ON SCHEMA::[deploy] TO [dr_Deploy];
GRANT INSERT  ON SCHEMA::[deploy] TO [dr_Deploy];
GRANT EXECUTE ON SCHEMA::[deploy] TO [dr_Deploy];
GRANT DELETE  ON SCHEMA::[deploy] TO [dr_Deploy];
GO
