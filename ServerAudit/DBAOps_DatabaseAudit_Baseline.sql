/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys a baseline database audit specification in the target database, bound to the
    DBAOps_ServerAudit server audit. Captures DDL changes within the database (schema
    objects created, altered, or dropped), permission grants and revocations, and database
    role membership changes.

    Run this script against each user database after DBAOps_ServerAudit is deployed and
    running on the instance. The DBAOps_ServerAudit server audit must exist before this
    script can be executed.

    System databases do not require this specification — server-level action groups in
    DBAOps_ServerAudit_Spec cover the significant events on system databases.

    For databases containing sensitive or regulated data, supplement this baseline with
    table-level object access auditing as a separate enhanced specification. See
    Audit-Standards.md for scope and action groups.

    To identify which user databases are missing this specification, run the following
    PowerShell against the instance after deploying the server audit:

        $instance = 'SQL-DEV-01'
        Get-DbaDatabase -SqlInstance $instance -ExcludeSystem |
            ForEach-Object {
                $spec = Invoke-DbaQuery -SqlInstance $instance -Database $_.Name -Query `
                    "SELECT [name] FROM sys.database_audit_specifications WHERE [name] = N'DBAOps_DatabaseAudit_Baseline_Spec'"
                [PSCustomObject]@{
                    Database = $_.Name
                    HasSpec  = $null -ne $spec
                }
            }

Usage Example:
    -- Enable SQLCMD mode, set DatabaseName below, then run this script.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-09  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

-- ============================================================================
-- CONFIGURE: Set target database name. Requires SQLCMD mode.
-- ============================================================================
:setvar DatabaseName "TargetDatabase"

USE [$(DatabaseName)];
GO

-- ============================================================================
-- TEARDOWN: Disable and drop existing specification if present
-- ============================================================================

IF EXISTS (
    SELECT 1 FROM sys.database_audit_specifications
    WHERE [name] = N'DBAOps_DatabaseAudit_Baseline_Spec'
)
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION [DBAOps_DatabaseAudit_Baseline_Spec] WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION [DBAOps_DatabaseAudit_Baseline_Spec];
    PRINT 'Dropped existing DBAOps_DatabaseAudit_Baseline_Spec.';
END
GO

-- ============================================================================
-- DATABASE AUDIT SPECIFICATION: Baseline DDL and permission events
-- ============================================================================

CREATE DATABASE AUDIT SPECIFICATION [DBAOps_DatabaseAudit_Baseline_Spec]
FOR SERVER AUDIT [DBAOps_ServerAudit]
ADD (SCHEMA_OBJECT_CHANGE_GROUP),        -- tables, procs, views, indexes: CREATE/ALTER/DROP
ADD (DATABASE_PERMISSION_CHANGE_GROUP),  -- GRANT, REVOKE, DENY within the database
ADD (DATABASE_ROLE_MEMBER_CHANGE_GROUP)  -- database role membership changes
WITH (STATE = ON);
GO

PRINT 'DBAOps_DatabaseAudit_Baseline_Spec deployed in: ' + DB_NAME() + '.';
GO

-- ============================================================================
-- VERIFY
-- ============================================================================

SELECT
    [name]             AS SpecName,
    [is_state_enabled] AS Enabled,
    DB_NAME()          AS TargetDatabase
FROM sys.database_audit_specifications
WHERE [name] = N'DBAOps_DatabaseAudit_Baseline_Spec';
GO
