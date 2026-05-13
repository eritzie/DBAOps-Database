--***************************************************************************************************
-- TODO: Update copyright notice for your organization
--
-- NOTE: PLEASE USE THE FOLLOWING NAMING CONVENTION FOR THE SCRIPTS.
--       1a_PBI12345_DatabaseName_Description_PreDeployment.sql
--       1b_PBI12345_DatabaseName_Description_PostDeployment.sql

-- Use the Specify Values for Template Parameters
-- command (Ctrl-Shift-M) to fill in the parameter
-- values below.

--Author:
    DECLARE @DevName nvarchar(255);
    SET @DevName = '<Developer Name,nvarchar(255),Developer_Name>'

--Target Database:
    DECLARE @DatabaseName nvarchar(255);
    SET @DatabaseName = '<Database Name,nvarchar(255),Database_Name>'

--Stored Procedure:
    DECLARE @SprocName nvarchar(1000);
    SET @SprocName = '<Stored Procedure Name,nvarchar(1000),schema.ProcName>';

--Description:
    DECLARE @Descrip nvarchar(255);
    SET @Descrip = '<Description,nvarchar(255),This section should describe the purpose of this deployment.>'

--Release Ticket:
    DECLARE @Ticket nvarchar(50);
    SET @Ticket = '<Ticket Number,nvarchar(50),PBI12345>'
--***************************************************************************************************

SET NOCOUNT ON;

DECLARE @CRLF           char(2)         = CHAR(13) + CHAR(10);
DECLARE @StartTime      datetime        = GETDATE();
DECLARE @SQLVersion     numeric(18,10);
DECLARE @HostPlatform   nvarchar(256);

SET @SQLVersion = CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),
    CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) - 1) + '.' +
    REPLACE(RIGHT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)),
    LEN(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max))) -
    CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max)))), '.', '')
    AS numeric(18,10));

IF @SQLVersion >= 14
    SELECT @HostPlatform = host_platform FROM sys.dm_os_host_info;
ELSE
    SET @HostPlatform = 'Windows';

-----------BEGIN SQL SCRIPT HEADER------------------
PRINT '====================================================================================';
PRINT '---START SQL SCRIPT-----';
PRINT '---SCRIPT START TIME: ' + CONVERT(varchar, @StartTime);
PRINT '---SCRIPT RAN ON DB : ' + DB_NAME();
PRINT '---Machine Name: ' + CAST(SERVERPROPERTY('MachineName') AS varchar);
PRINT '---Platform    : ' + @HostPlatform;
PRINT '---SQL Version : ' + CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(max));
PRINT '---SQL Edition : ' + CAST(SERVERPROPERTY('Edition') AS nvarchar(max));
PRINT '---System User : ' + SUSER_SNAME();
PRINT '---Host        : ' + HOST_NAME();
PRINT '---Application : ' + APP_NAME();
PRINT '---TranCount   : ' + CAST(@@TRANCOUNT AS varchar);
PRINT @CRLF
PRINT '---Target DB   : ' + @DatabaseName;
PRINT '---Target Sproc: ' + @SprocName;
PRINT '---Developer   : ' + @DevName;
PRINT '---Description : ' + @Descrip;
PRINT '---Ticket Num  : ' + @Ticket;
PRINT '====================================================================================';
-----------END SQL SCRIPT HEADER--------------------

-- Rollback strategy: This template uses CREATE OR ALTER, which is idempotent.
-- Rollback is performed by deploying the previous version from source control.
-- No rollback data capture is needed for schema changes.

GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
===================================================================================================
TODO: Update copyright notice for your organization

Description:
    <This section should be used to describe the purpose of this stored procedure.>

Parameters:
    <@param1 varchar(50)>   --Parameter description
                            --DEFAULT: value

    <@param2 int>           --Parameter description
                            --DEFAULT: value

Usage Examples:
    EXEC <sproc name>

Error codes:
    <error code> <description>

Change History:
    Date        Author                           Description                          Release Ticket
    ----------  -------------------------------  -----------------------------------  ----------------

===================================================================================================
*/
CREATE OR ALTER PROCEDURE <Schema_Name, sysname, Schema_Name>.<Procedure_Name, sysname, Procedure_Name>
    <@param1, sysname, @p1> <datatype_for_param1, , int> = <default_value_for_param1, , 0>,
    <@param2, sysname, @p2> <datatype_for_param2, , int> = <default_value_for_param2, , 0>
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY

        -- TODO: Add procedure logic here
        SELECT @p1, @p2;

    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH
END
GO

-----------BEGIN SQL SCRIPT FOOTER------------------
PRINT '====================================================================================';
PRINT '---FINISHED SQL SCRIPT--';
PRINT '---Finished At : ' + CONVERT(varchar, GETDATE());
PRINT '---TranCount   : ' + CONVERT(varchar, @@TRANCOUNT);
PRINT '====================================================================================';
GO
-----------END SQL SCRIPT FOOTER--------------------