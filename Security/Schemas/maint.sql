/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Schema for database maintenance objects. Reserved for future DBA maintenance
    stored procedures and supporting tables outside the Ola Hallengren dbo-schema objects.

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-08  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'maint')
    EXEC sp_executesql N'CREATE SCHEMA [maint] AUTHORIZATION [dbo]';
GO
