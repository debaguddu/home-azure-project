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

-- Reset WatermarkTable to default ('1900-01-01 00:00:00')
-- UPDATE dbo.WatermarkTable SET WatermarkValue = '1900-01-01 00:00:00', LastUpdatedDate = SYSUTCDATETIME();
-- EXEC dbo.sp_ResetWatermark;
