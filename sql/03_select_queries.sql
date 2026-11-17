SELECT
    *
FROM
    dbo.IngestionMetadata;

SELECT
    *
FROM
    dbo.PipelineExecutionLog;

SELECT
    *
FROM
    dbo.WatermarkTable;

SELECT
    *
FROM
    dbo.DataTransformMetadata;

-- Reset WatermarkTable to default ('1900-01-01 00:00:00')
-- UPDATE dbo.WatermarkTable SET WatermarkValue = '1900-01-01 00:00:00', LastUpdatedDate = SYSUTCDATETIME();
-- EXEC dbo.sp_ResetWatermark;

-- Reset stuck 'InProgress' logs to 'Cancelled' or 'Failed'
-- UPDATE dbo.PipelineExecutionLog
-- SET Status = 'Failed',
--     EndTime = SYSUTCDATETIME(),
--     DurationInSeconds = DATEDIFF(SECOND, StartTime, SYSUTCDATETIME()),
--     ErrorMessage = 'Pipeline run terminated or reset manually'
-- WHERE Status = 'InProgress';

