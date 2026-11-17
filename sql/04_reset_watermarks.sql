-- ==============================================================================
-- 04_reset_watermarks.sql
-- Description: Resets watermark values in dbo.WatermarkTable back to default
--              ('1900-01-01 00:00:00') for full re-ingestion or testing.
-- Database: sqldb-azureproject-dev-01
-- ==============================================================================

-- Option 1: Reset ALL tables to default watermark ('1900-01-01 00:00:00')
UPDATE dbo.WatermarkTable
SET WatermarkValue = '1900-01-01 00:00:00',
    LastUpdatedDate = SYSUTCDATETIME();
GO

-- Option 2: Reset a specific table to default (e.g. Policies)
-- UPDATE dbo.WatermarkTable
-- SET WatermarkValue = '1900-01-01 00:00:00',
--     LastUpdatedDate = SYSUTCDATETIME()
-- WHERE SourceTableName = 'Policies';
-- GO

-- Option 3: Use the stored procedure sp_ResetWatermark
-- Reset all tables:
-- EXEC dbo.sp_ResetWatermark;
--
-- Reset specific table:
-- EXEC dbo.sp_ResetWatermark @SourceTableName = 'Policies';
-- GO

-- Verify current watermark values
SELECT 
    w.WatermarkID,
    w.TableID,
    m.SourceSchema,
    w.SourceTableName,
    w.WatermarkColumn,
    w.WatermarkValue,
    w.LastUpdatedDate,
    m.LoadType,
    m.IsActive
FROM dbo.WatermarkTable w
LEFT JOIN dbo.IngestionMetadata m ON w.TableID = m.TableID
ORDER BY w.TableID;
GO

