/*
===================================================================================================
DBAOps Database - Setup Script 09: Create XE Sessions  [MANUAL-SETUP]

Description:
    Deploys all five DBAOps Extended Events sessions. This script is NOT run automatically
    by Deploy-DBAOps.ps1 — XE sessions require per-instance review of ring buffer sizes,
    file paths, and thresholds before enabling.

    Run in SSMS with SQLCMD Mode enabled, or via sqlcmd.exe. Set :setvar XELogsPath
    below before running. Each session is dropped and recreated if it already exists.

    Sessions deployed:
        DBAOps_BlockedProcess         Ring buffer — blocked process capture
                                      Prerequisite for: DBAOps - Capture - Blocking History job
                                      Requires: blocked process threshold (s) > 0

        DBAOps_SpExecutionCapture     Ring buffer — stored procedure execution detail
                                      Prerequisite for: DBAOps - Capture - RpcExecutions job

        DBAOps_SaActivityMonitor      File target  — sa login activity capture
                                      Prerequisite for: DBAOps - Capture - SaActivity job
                                      Requires: $(XELogsPath) directory with SQL Server
                                                service account write access

        DBAOps_DatabaseActivity       File target  — database-scoped activity audit
                                      Targeted use: pre-migration, decommission, connectivity.
                                      Commented out by default — set database_id before enabling.

        DBAOps_PerformanceDiagnostics Template sessions for blocked process and long-running
                                      query capture. Commented out by default — review
                                      thresholds and uncomment before deploying.

    Usage:
        :setvar XELogsPath "C:\XEvents\"
        Then execute this script in SSMS with SQLCMD Mode enabled.

Prerequisites:
    - sysadmin or ALTER ANY EVENT SESSION permission on the target instance
    - $(XELogsPath) directory must exist before DBAOps_SaActivityMonitor will start

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Initial creation
    2026-06-17  Eric Ritzie     Add DBAOps_DatabaseActivity and DBAOps_PerformanceDiagnostics

===================================================================================================
*/

-- Capture pipeline prerequisites (ring buffer and file-target sessions)
:r ..\XESessions\DBAOps_BlockedProcess.sql
:r ..\XESessions\DBAOps_SpExecutionCapture.sql
:r ..\XESessions\DBAOps_SaActivityMonitor.sql

-- Diagnostic / ad-hoc sessions (commented out by default in each script)
:r ..\XESessions\DBAOps_DatabaseActivity.sql
:r ..\XESessions\DBAOps_PerformanceDiagnostics.sql

PRINT '***** XE session setup complete.';
GO
