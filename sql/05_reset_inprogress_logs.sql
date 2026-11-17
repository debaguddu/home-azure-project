-- ==============================================================================
-- 05_reset_inprogress_logs.sql
-- Description: Queries and resets stuck 'InProgress' records in dbo.PipelineExecutionLog.
--              Useful when ADF pipeline runs were cancelled, failed abruptly, or
--              terminated before sp_LogPipelineEnd was called.
-- Database: sqldb-azureproject-dev-01
-- ==============================================================================

-- 1. Check all current InProgress execution logs
SELECT 
    LogID,
    BatchID,
    PipelineRunID,
    PipelineName,
    TableID,
    TableName,
    LoadType,
    Status,
    StartTime,
    DATEDIFF(MINUTE, StartTime, SYSUTCDATETIME()) AS RunningMinutes
FROM dbo.PipelineExecutionLog
WHERE Status = 'InProgress'
ORDER BY LogID DESC;
GO

-- 2. Stored Procedure: sp_ResetInProgressLogs
IF OBJECT_ID('dbo.sp_ResetInProgressLogs', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ResetInProgressLogs;
GO

CREATE PROCEDURE dbo.sp_ResetInProgressLogs
    @BatchID            VARCHAR(100)  = NULL,                          -- Optional: Reset specific batch only
    @PipelineName       VARCHAR(100)  = NULL,                          -- Optional: Reset specific pipeline only
    @NewStatus          VARCHAR(50)   = 'Failed',                      -- 'Failed' or 'Cancelled'
    @ErrorMessage       NVARCHAR(MAX) = 'Pipeline run terminated or reset manually'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();

    UPDATE dbo.PipelineExecutionLog
    SET Status = @NewStatus,
        EndTime = @CurrentTime,
        DurationInSeconds = DATEDIFF(SECOND, StartTime, @CurrentTime),
        ErrorMessage = @ErrorMessage
    WHERE Status = 'InProgress'
      AND (@BatchID IS NULL OR BatchID = @BatchID)
      AND (@PipelineName IS NULL OR PipelineName = @PipelineName);

    SELECT @@ROWCOUNT AS RowsReset;

    SELECT TOP 25 
        LogID,
        BatchID,
        PipelineRunID,
        PipelineName,
        TableName,
        Status,
        StartTime,
        EndTime,
        DurationInSeconds,
        ErrorMessage
    FROM dbo.PipelineExecutionLog
    ORDER BY LogID DESC;
END;
GO

-- 3. Execute Reset
-- Option A: Reset all InProgress logs via direct UPDATE
UPDATE dbo.PipelineExecutionLog
SET Status = 'Failed',
    EndTime = SYSUTCDATETIME(),
    DurationInSeconds = DATEDIFF(SECOND, StartTime, SYSUTCDATETIME()),
    ErrorMessage = 'Pipeline run terminated or reset manually'
WHERE Status = 'InProgress';
GO

-- Option B: Reset using stored procedure
-- EXEC dbo.sp_ResetInProgressLogs;
-- EXEC dbo.sp_ResetInProgressLogs @NewStatus = 'Cancelled';
-- GO

-- 4. Verify all recent execution logs
SELECT TOP 20
    LogID,
    BatchID,
    PipelineRunID,
    PipelineName,
    TableName,
    LoadType,
    Status,
    RowsCopied,
    StartTime,
    EndTime,
    DurationInSeconds,
    ErrorMessage
FROM dbo.PipelineExecutionLog
ORDER BY LogID DESC;
GO

