USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns all logins that are members of high-privilege server roles (sysadmin,
    securityadmin, serveradmin) plus the SA account status. Useful for SOX access reviews
    and CIS Benchmark compliance checks.

    Result sets:
        1. High-privilege role members
        2. SA account status

Usage Example:
    EXEC [dbo].[GetSysadminMembers];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetSysadminMembers]
AS
BEGIN
    SET NOCOUNT ON;

    -- Result set 1: high-privilege role members.
    -- ##% principals are internal SQL Server certificate-based accounts used for system
    -- modules (e.g., ##MS_SQLAuthenticatorCertificate##). They are not real logins and
    -- must be excluded from access reviews; their presence in sysadmin is expected and normal.
    SELECT
         r.name                                         AS RoleName
        ,p.name                                         AS LoginName
        ,p.type_desc                                    AS LoginType
        ,p.is_disabled                                  AS IsDisabled
        ,p.create_date                                  AS CreateDate
        ,p.modify_date                                  AS ModifyDate
    FROM [sys].[server_principals]                      p
    JOIN [sys].[server_role_members]                    rm ON p.principal_id      = rm.member_principal_id
    JOIN [sys].[server_principals]                      r  ON rm.role_principal_id = r.principal_id
    WHERE r.name IN (N'sysadmin', N'securityadmin', N'serveradmin')
      AND p.name NOT LIKE N'##%'                        -- exclude internal certificate-based principals
    ORDER BY r.name, p.name;

    -- Result set 2: SA account status. SA has a fixed SID of 0x01 regardless of whether
    -- the account has been renamed; checking by SID is more reliable than checking by name.
    SELECT
         p.name                                         AS LoginName
        ,p.is_disabled                                  AS IsDisabled
        ,p.type_desc                                    AS LoginType
        ,p.create_date                                  AS CreateDate
        ,p.modify_date                                  AS ModifyDate
    FROM [sys].[server_principals]                      p
    WHERE p.sid = 0x01;                                 -- SA SID is always 0x01
END
