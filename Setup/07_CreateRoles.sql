/*
===================================================================================================
DBAOps Database - Setup Script 07: Create Database Roles

Description:
    Creates all DBAOps database roles by including the individual role scripts from
    Security\Roles\. Run in DBAOps context. Each included script uses IF NOT EXISTS
    so this is safe to re-run.

    dr_RO      Read-only (SELECT)
    dr_RW      Read + write (SELECT, INSERT, UPDATE)
    dr_RWE     Read + write + execute (SELECT, INSERT, UPDATE, EXECUTE)
    dr_EO      Execute-only (EXECUTE)
    dr_RE      Read + execute (SELECT, EXECUTE)
    dr_Del     DELETE — additive, assign alongside dr_RW or dr_RWE
    dr_Deploy  Full deploy schema access

Prerequisites:
    - Run 01 through 06 first

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Initial creation

===================================================================================================
*/

USE [DBAOps];
GO

:r ..\Security\Roles\dr_RO.sql
:r ..\Security\Roles\dr_RW.sql
:r ..\Security\Roles\dr_RWE.sql
:r ..\Security\Roles\dr_EO.sql
:r ..\Security\Roles\dr_RE.sql
:r ..\Security\Roles\dr_Del.sql
:r ..\Security\Roles\dr_Deploy.sql

PRINT '***** Role setup complete.';
GO
