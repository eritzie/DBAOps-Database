/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Deploys the DBAOps_ServerAudit server audit and DBAOps_ServerAudit_Spec server audit
    specification. Captures server-level security and operational events: successful and
    failed logins, login and server role changes, audit modification, database DDL, and
    backup/restore operations. Audit files are written to a dedicated directory separate
    from XE diagnostic files.

    Audit file path is configured via the :setvar AuditPath variable — SQLCMD mode
    required (Query > SQLCMD Mode in SSMS). Default path: C:\Audit\. The SQL Server
    service account needs write access; grant with:
        icacls "C:\Audit" /grant "NT SERVICE\MSSQL$<instance>:(OI)(CI)F"
    For a default instance replace MSSQL$<instance> with MSSQLSERVER.

    ON_FAILURE = CONTINUE — SQL Server continues operating if the audit file cannot be
    written. Change to FAIL_OPERATION only when compliance policy requires it; that
    setting blocks all audited operations when the target is unavailable.

    SUCCESSFUL_LOGIN_GROUP captures all logins including sa. Query audit files to
    identify which applications and hosts are connecting via sa during remediation.
    See Audit-Standards.md for query examples.

Usage Example:
    -- Enable SQLCMD mode, then run this script.
    -- Verify deployment:
    SELECT [name], [is_state_enabled] FROM sys.server_audits WHERE [name] = N'DBAOps_ServerAudit';
    SELECT [name], [is_state_enabled] FROM sys.server_audit_specifications WHERE [name] = N'DBAOps_ServerAudit_Spec';

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-09  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

-- ============================================================================
-- CONFIGURE: Set audit file path for this instance. Must end with a backslash.
--            Requires SQLCMD mode (Query > SQLCMD Mode in SSMS).
-- ============================================================================
:setvar AuditPath "C:\Audit\"

-- ============================================================================
-- TEARDOWN: Disable and drop existing spec before dropping the audit.
--           The specification must be off before it can be dropped, and the
--           audit must be off before the specification is dropped.
-- ============================================================================

IF EXISTS (
    SELECT 1 FROM sys.server_audit_specifications
    WHERE [name] = N'DBAOps_ServerAudit_Spec'
)
BEGIN
    ALTER SERVER AUDIT SPECIFICATION [DBAOps_ServerAudit_Spec] WITH (STATE = OFF);
    DROP SERVER AUDIT SPECIFICATION [DBAOps_ServerAudit_Spec];
    PRINT 'Dropped existing DBAOps_ServerAudit_Spec.';
END
GO

IF EXISTS (
    SELECT 1 FROM sys.server_audits
    WHERE [name] = N'DBAOps_ServerAudit'
)
BEGIN
    ALTER SERVER AUDIT [DBAOps_ServerAudit] WITH (STATE = OFF);
    DROP SERVER AUDIT [DBAOps_ServerAudit];
    PRINT 'Dropped existing DBAOps_ServerAudit.';
END
GO

-- ============================================================================
-- SERVER AUDIT: File target, 100 MB per file, 10 rollover files (1 GB max)
-- ============================================================================

CREATE SERVER AUDIT [DBAOps_ServerAudit]
TO FILE (
    FILEPATH           = N'$(AuditPath)',
    MAXSIZE            = 100 MB,
    MAX_ROLLOVER_FILES = 10
)
WITH (
    QUEUE_DELAY = 1000,       -- 1 second; increase if write I/O is a concern
    ON_FAILURE  = CONTINUE    -- *** Change to FAIL_OPERATION if compliance policy requires ***
);
GO

ALTER SERVER AUDIT [DBAOps_ServerAudit] WITH (STATE = ON);
GO

-- ============================================================================
-- SERVER AUDIT SPECIFICATION
--
-- LOGOUT_GROUP intentionally omitted — adds significant volume with limited
-- additional intelligence. Login timestamp is sufficient to establish session
-- boundaries for most compliance purposes. Add back if policy requires it.
-- ============================================================================

CREATE SERVER AUDIT SPECIFICATION [DBAOps_ServerAudit_Spec]
FOR SERVER AUDIT [DBAOps_ServerAudit]
ADD (SUCCESSFUL_LOGIN_GROUP),           -- all successful logins; primary source for sa remediation
ADD (FAILED_LOGIN_GROUP),               -- failed login attempts; brute force and misconfiguration indicator
ADD (SERVER_PRINCIPAL_CHANGE_GROUP),    -- logins created, altered, or dropped
ADD (SERVER_ROLE_MEMBER_CHANGE_GROUP),  -- sysadmin and other server role membership changes
ADD (AUDIT_CHANGE_GROUP),               -- changes to this audit (tamper evidence)
ADD (DATABASE_CHANGE_GROUP),            -- databases created, altered, or dropped
ADD (BACKUP_RESTORE_GROUP)              -- backup and restore operations
WITH (STATE = ON);
GO

PRINT 'DBAOps_ServerAudit deployed and started (file target: $(AuditPath)).';
GO

-- ============================================================================
-- VERIFY
-- ============================================================================

SELECT
    [name]             AS AuditName,
    [is_state_enabled] AS AuditEnabled,
    [type_desc]        AS TargetType
FROM sys.server_audits
WHERE [name] = N'DBAOps_ServerAudit';
GO

SELECT
    [name]             AS SpecName,
    [is_state_enabled] AS SpecEnabled
FROM sys.server_audit_specifications
WHERE [name] = N'DBAOps_ServerAudit_Spec';
GO
