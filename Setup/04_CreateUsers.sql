/*
===================================================================================================
DBAOps Database - Setup Script 04: Create Contained Users

Description:
    Template for creating contained database users in DBAOps.

    Contained users authenticate directly to the database without server-level logins.
    This makes backup/restore portable across servers and is compatible with Azure SQL.

    Two user types are templated below:
    1. Deployment service account — used by CI/CD pipelines to write rollback data
    2. DBA read access — for querying manifest and rollback data

    Adjust usernames, passwords, and role memberships to fit your environment.

Prerequisites:
    - Run 01 through 03 setup scripts first
    - Execute in the context of [DBAOps]

Notes:
    - For Windows/AD environments, you can also create contained users mapped to
      Windows accounts: CREATE USER [DOMAIN\Account] WITH DEFAULT_SCHEMA = [deploy];
    - For Azure AD: CREATE USER [user@domain.com] FROM EXTERNAL PROVIDER;
    - Passwords shown here are placeholders — use strong passwords or integrate with
      your secret management tooling (Azure Key Vault, AWS Secrets Manager, etc.)

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

USE [DBAOps];
GO

-----------------------------------------------------------------------
-- 1. Deployment Service Account
--    Used by CI/CD pipelines. Needs to:
--    - INSERT into deploy.RollbackManifest
--    - CREATE TABLE in the deploy schema (SELECT INTO for rollback data)
--    - SELECT from deploy schema (for rollback operations)
--    - UPDATE deploy.RollbackManifest (status changes)
-----------------------------------------------------------------------

/*  -- Uncomment and customize for your environment

-- Password-based contained user (SQL auth)
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE [name] = N'DeployAgent')
BEGIN
    CREATE USER [DeployAgent] WITH PASSWORD = N'<STRONG_PASSWORD_HERE>';
    ALTER ROLE db_datareader ADD MEMBER [DeployAgent];
    ALTER ROLE db_datawriter ADD MEMBER [DeployAgent];
    ALTER ROLE db_ddladmin   ADD MEMBER [DeployAgent];  -- Needed for SELECT INTO (creates tables)
    ALTER USER [DeployAgent] WITH DEFAULT_SCHEMA = [deploy];
    PRINT '***** Contained user [DeployAgent] created.';
END
GO

-- Windows/AD contained user (alternative)
-- CREATE USER [DOMAIN\SvcDeployAgent] WITH DEFAULT_SCHEMA = [deploy];
-- ALTER ROLE db_datareader ADD MEMBER [DOMAIN\SvcDeployAgent];
-- ALTER ROLE db_datawriter ADD MEMBER [DOMAIN\SvcDeployAgent];
-- ALTER ROLE db_ddladmin   ADD MEMBER [DOMAIN\SvcDeployAgent];

*/

-----------------------------------------------------------------------
-- 2. DBA Read Access
--    For querying manifest, reviewing rollback data, running cleanup.
-----------------------------------------------------------------------

/*  -- Uncomment and customize for your environment

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE [name] = N'DBAReadUser')
BEGIN
    CREATE USER [DBAReadUser] WITH PASSWORD = N'<STRONG_PASSWORD_HERE>';
    ALTER ROLE db_datareader ADD MEMBER [DBAReadUser];
    ALTER USER [DBAReadUser] WITH DEFAULT_SCHEMA = [deploy];
    PRINT '***** Contained user [DBAReadUser] created.';
END
GO

-- For a DBA who also needs to run cleanup (drop expired rollback tables):
-- ALTER ROLE db_datawriter ADD MEMBER [DBAReadUser];
-- ALTER ROLE db_ddladmin   ADD MEMBER [DBAReadUser];

*/

PRINT '***** User setup template complete. Uncomment and customize the blocks above.';
GO