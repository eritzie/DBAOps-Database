USE [DBAOps];
GO

/*===============================================================================================
Copyright (C) 2026 Eric Ritzie. All rights reserved.

Description:
    Returns current replication agent status, last run time, and last message for all
    transactional and merge subscriptions visible from this instance's distributor.
    Must be run on the distributor instance to return meaningful results.
    Returns an informational message and exits cleanly if the distribution database is not
    present on this instance.

    Runstatus values: 1=Started, 2=Succeeded, 3=Active, 4=Idle, 5=Retrying, 6=Failed.

    Result sets:
        1. Transactional subscription status
        2. Merge subscription status
        3. Recent replication errors (last 24 hours, transactional agents only)

Usage Example:
    EXEC [dbo].[GetReplicationStatus];

Change History:
    Date        Author                           Description
    ----------  -------------------------------  ------------------------------------
    2026-06-10  Eric Ritzie (eritzie)            Initial creation
===============================================================================================*/

CREATE OR ALTER PROCEDURE [dbo].[GetReplicationStatus]
AS
BEGIN
    SET NOCOUNT ON;

    -- This proc queries distribution catalog tables which only exist on the distributor.
    -- Querying them from a non-distributor instance would fail; check first and exit cleanly.
    IF DB_ID(N'distribution') IS NULL
    BEGIN
        SELECT 'Distribution database not found on this instance. Run on the distributor.' AS Message;
        RETURN;
    END

    -- Result set 1: transactional subscription status.
    -- runstatus: 1=Started, 2=Succeeded, 3=Active, 4=Idle, 5=Retrying, 6=Failed.
    SELECT
         da.publisher                                    AS Publisher
        ,da.publisher_db                                AS PublisherDb
        ,da.publication                                 AS Publication
        ,da.subscriber                                  AS Subscriber
        ,da.subscriber_db                               AS SubscriberDb
        ,dh.runstatus                                   AS RunStatus
        ,CASE dh.runstatus
            WHEN 1 THEN 'Started'
            WHEN 2 THEN 'Succeeded'
            WHEN 3 THEN 'Active'
            WHEN 4 THEN 'Idle'
            WHEN 5 THEN 'Retrying'
            WHEN 6 THEN 'Failed'
            ELSE        'Unknown'
         END                                            AS RunStatusDesc
        ,dh.start_time                                  AS LastRunStart
        ,dh.time                                        AS LastActionTime
        ,dh.delivered_commands                          AS DeliveredCommands
        ,dh.delivered_transactions                      AS DeliveredTransactions
        ,dh.comments                                    AS LastMessage
    FROM [distribution].[dbo].[MSdistribution_agents]   da
    CROSS APPLY (
        SELECT TOP 1
             runstatus, start_time, [time]
            ,delivered_commands, delivered_transactions, comments
        FROM [distribution].[dbo].[MSdistribution_history]
        WHERE agent_id = da.id
        ORDER BY [timestamp] DESC
    ) dh
    ORDER BY da.publisher, da.publication, da.subscriber;

    -- Result set 2: merge subscription status.
    -- runstatus values are the same mapping as transactional agents above.
    SELECT
         ma.publisher                                   AS Publisher
        ,ma.publisher_db                                AS PublisherDb
        ,ma.publication                                 AS Publication
        ,ma.subscriber                                  AS Subscriber
        ,ma.subscriber_db                               AS SubscriberDb
        ,ms.runstatus                                   AS RunStatus
        ,CASE ms.runstatus
            WHEN 1 THEN 'Started'
            WHEN 2 THEN 'Succeeded'
            WHEN 3 THEN 'Active'
            WHEN 4 THEN 'Idle'
            WHEN 5 THEN 'Retrying'
            WHEN 6 THEN 'Failed'
            ELSE        'Unknown'
         END                                            AS RunStatusDesc
        ,ms.start_time                                  AS LastRunStart
        ,ms.end_time                                    AS LastRunEnd
        ,ms.delivery_rate
        ,ms.last_message                                AS LastMessage
    FROM [distribution].[dbo].[MSmerge_agents]          ma
    CROSS APPLY (
        SELECT TOP 1
             runstatus, start_time, end_time
            ,delivery_rate, last_message
        FROM [distribution].[dbo].[MSmerge_sessions]
        WHERE agent_id = ma.id
        ORDER BY start_time DESC
    ) ms
    ORDER BY ma.publisher, ma.publication, ma.subscriber;

    -- Result set 3: recent replication errors (last 24 hours, transactional agents only).
    SELECT TOP 50
         da.publisher                                   AS Publisher
        ,da.publication                                 AS Publication
        ,da.subscriber                                  AS Subscriber
        ,dh.start_time                                  AS ErrorTime
        ,dh.error_id
        ,dh.comments                                    AS ErrorMessage
    FROM [distribution].[dbo].[MSdistribution_history]  dh
    JOIN [distribution].[dbo].[MSdistribution_agents]   da ON dh.agent_id = da.id
    WHERE dh.runstatus = 6                              -- Failed status only
      AND dh.start_time >= DATEADD(HOUR, -24, SYSUTCDATETIME())
    ORDER BY dh.start_time DESC;
END
