USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Audits SQL logins for policy compliance issues: password policy not enforced,
    expiration not checked, blank passwords, and common weak passwords. Uses PWDCOMPARE()
    to test password hashes without exposing them.

    PWDCOMPARE() requires VIEW SERVER STATE or ALTER ANY LOGIN. Grant this proc to dr_RO
    or equivalent; VIEW SERVER STATE must be granted at the instance level separately.

Usage Example:
    EXEC [dbo].[GetSqlLoginAudit];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetSqlLoginAudit]
AS
BEGIN
    SET NOCOUNT ON;

    -- CTE so WeakPasswordMatch is a real column in ORDER BY scope.
    -- SQL Server allows column aliases as direct ORDER BY references but not inside
    -- expressions (CASE WHEN <alias> IS NOT NULL fails at parse time).
    ;WITH LoginAudit AS (
        SELECT
             l.name                                         AS LoginName
            ,l.is_disabled                                  AS IsDisabled
            ,l.is_policy_checked                            AS PolicyChecked
            ,l.is_expiration_checked                        AS ExpirationChecked
            ,l.create_date                                  AS CreateDate
            ,l.modify_date                                  AS ModifyDate
            -- PWDCOMPARE tests whether a plaintext string matches a stored password hash without
            -- exposing the hash value; returns 1 on match, 0 otherwise.
            ,PWDCOMPARE(N'', l.password_hash)               AS IsBlankPassword
            -- The weak password list below is a starting set covering the most common offenders.
            -- Extend it with organization-specific patterns (application names, company name, etc.)
            -- as needed for your environment.
            ,CASE
                WHEN PWDCOMPARE(N'password',     l.password_hash) = 1 THEN N'password'
                WHEN PWDCOMPARE(N'Password1',    l.password_hash) = 1 THEN N'Password1'
                WHEN PWDCOMPARE(N'password1',    l.password_hash) = 1 THEN N'password1'
                WHEN PWDCOMPARE(N'Password1!',   l.password_hash) = 1 THEN N'Password1!'
                WHEN PWDCOMPARE(N'Welcome1',     l.password_hash) = 1 THEN N'Welcome1'
                WHEN PWDCOMPARE(N'Welcome1!',    l.password_hash) = 1 THEN N'Welcome1!'
                WHEN PWDCOMPARE(N'sa',           l.password_hash) = 1 THEN N'sa'
                WHEN PWDCOMPARE(N'admin',        l.password_hash) = 1 THEN N'admin'
                WHEN PWDCOMPARE(N'Admin1234',    l.password_hash) = 1 THEN N'Admin1234'
                WHEN PWDCOMPARE(N'sql',          l.password_hash) = 1 THEN N'sql'
                WHEN PWDCOMPARE(N'P@ssw0rd',     l.password_hash) = 1 THEN N'P@ssw0rd'
                WHEN PWDCOMPARE(N'P@ssword1',    l.password_hash) = 1 THEN N'P@ssword1'
                -- Common pattern in legacy environments: password set to match the login name
                WHEN PWDCOMPARE(l.name,          l.password_hash) = 1 THEN N'<same as login name>'
                ELSE NULL
             END                                            AS WeakPasswordMatch
        FROM [sys].[sql_logins]                             l
        WHERE l.name NOT LIKE N'##%'                        -- exclude internal certificate-based principals
    )
    SELECT
         LoginName
        ,IsDisabled
        ,PolicyChecked
        ,ExpirationChecked
        ,CreateDate
        ,ModifyDate
        ,IsBlankPassword
        ,WeakPasswordMatch
    FROM LoginAudit
    ORDER BY
         IsBlankPassword DESC
        ,CASE WHEN WeakPasswordMatch IS NOT NULL THEN 0 ELSE 1 END
        ,LoginName;
END
