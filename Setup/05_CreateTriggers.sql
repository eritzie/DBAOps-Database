/*
===================================================================================================
DBAOps Database - Setup Script 05: Create Triggers

Description:
    Deploys the trg_SchemaChangeCapture database-scoped DDL trigger to the DBAOps
    database itself. This captures DDL and permission changes made to DBAOps objects.

    To deploy to additional user databases (for broader schema change auditing),
    run Triggers\trg_SchemaChangeCapture_MANUAL-SETUP.sql directly against each
    target database in SSMS with SQLCMD Mode enabled, or via sqlcmd.exe.

    The trigger script is idempotent: the trigger is dropped and recreated on each
    run so the definition is always current.

Prerequisites:
    - Run 01 through 04 first (audit.SchemaChangeHistory must exist from 03)

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Initial creation

===================================================================================================
*/

USE [DBAOps];
GO

:r ..\Triggers\trg_SchemaChangeCapture.sql

PRINT '***** Trigger setup complete.';
GO
