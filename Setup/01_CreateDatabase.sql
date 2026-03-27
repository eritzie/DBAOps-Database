/*
===================================================================================================
DBAOps Database - Setup Script 01: Create Database

Description:
    Creates the DBAOps contained database. This is the DBA's operational utility database
    for deployment tracking, maintenance logging, trace data, and other
    DBA operational needs.

    Contained database design enables:
    - Portable backup/restore without orphaned users
    - Azure SQL Database compatibility
    - AWS RDS for SQL Server compatibility
    - Self-contained authentication

Prerequisites:
    - sysadmin or dbcreator role membership
    - 'contained database authentication' server option must be enabled (script handles this)

Notes:
    - Custom operational schemas (deploy, trace, etc.) are created in script 02

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------

===================================================================================================
*/

-- Enable contained database authentication if not already enabled
IF NOT EXISTS (
    SELECT 1
    FROM sys.configurations
    WHERE [name] = 'contained database authentication'
      AND value_in_use = 1
)
BEGIN
    PRINT '***** Enabling contained database authentication...';
    EXEC sp_configure 'contained database authentication', 1;
    RECONFIGURE;
    PRINT '***** Contained database authentication enabled.';
END
ELSE
BEGIN
    PRINT '***** Contained database authentication already enabled.';
END
GO

-- Create the database if it does not exist
IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = N'DBAOps')
BEGIN
    PRINT '***** Creating database [DBAOps]...';

    CREATE DATABASE [DBAOps]
        CONTAINMENT = PARTIAL;

    PRINT '***** Database [DBAOps] created.';
END
ELSE
BEGIN
    PRINT '***** Database [DBAOps] already exists.';

    -- Ensure containment is set to PARTIAL if db already exists
    IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE [name] = N'DBAOps' AND containment = 1)
    BEGIN
        PRINT '***** Setting containment to PARTIAL on existing database...';
        ALTER DATABASE [DBAOps] SET CONTAINMENT = PARTIAL;
        PRINT '***** Containment updated.';
    END
END
GO

-- Configure database options
USE [DBAOps];
GO

-- Recovery model: SIMPLE is appropriate for an operational/utility database.
-- There is no user data here worth point-in-time recovery — rollback snapshots
-- can be recaptured from source systems if lost.
ALTER DATABASE [DBAOps] SET RECOVERY SIMPLE;
GO

PRINT '***** DBAOps database setup complete.';
GO