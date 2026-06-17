/*
===================================================================================================
DBAOps Database - Setup Script 08: Create Agent Jobs

Description:
    Creates all five DBAOps SQL Agent jobs by including the individual job scripts
    from AgentJobs\. Each included script uses drop-and-recreate, so this is safe
    to re-run. Each job is wrapped in its own transaction — a failure on one job
    does not prevent the others from being created.

    Jobs created:
        DBAOps - Capture - Deadlocks          system_health (no XE setup needed)
        DBAOps - Capture - WaitStats           sys.dm_os_wait_stats (no XE setup needed)
        DBAOps - Capture - Blocking History    Requires DBAOps_BlockedProcess XE session
        DBAOps - Capture - RpcExecutions       Requires DBAOps_SpExecutionCapture XE session
        DBAOps - Capture - SaActivity          Requires DBAOps_SaActivityMonitor XE session
                                               and 08_CreateSaPipeline.sql objects

    No schedules are created — add schedules appropriate for each instance after deployment.

    $(XELogsPath) in the SaActivity step is substituted at deploy time by Deploy-DBAOps.ps1.
    For standalone SQLCMD execution: :setvar XELogsPath "C:\XEvents\" before running.

Prerequisites:
    - Run 01 through 07 first
    - Run 08_CreateSaPipeline.sql before the SaActivity job will produce data

Change History:
    Date        Author          Description                          Ticket
    ----------  --------------  -----------------------------------  --------
    2026-06-17  Eric Ritzie     Initial creation

===================================================================================================
*/

:r ..\AgentJobs\DBAOps-CaptureDeadlocks.sql
:r ..\AgentJobs\DBAOps-CaptureWaitStats.sql
:r ..\AgentJobs\DBAOps-CaptureBlockingHistory.sql
:r ..\AgentJobs\DBAOps-CaptureRpcExecutions.sql
:r ..\AgentJobs\DBAOps-CaptureSaActivity.sql

PRINT '***** Agent job setup complete.';
GO
