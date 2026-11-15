-- ==============================================================================
-- 02_seed_metadata.sql
-- Description: Seed metadata for the 5 DemoDB tables into IngestionMetadata
--              and initialize initial watermark values in WatermarkTable.
-- Database: sqldb-azureproject-dev-01
-- ==============================================================================

-- Clear existing sample records if re-running
DELETE FROM dbo.WatermarkTable;
DELETE FROM dbo.IngestionMetadata;
DBCC CHECKIDENT ('dbo.IngestionMetadata', RESEED, 0);
DBCC CHECKIDENT ('dbo.WatermarkTable', RESEED, 0);
GO

-- 1. Insert Metadata Records
INSERT INTO dbo.IngestionMetadata (
    TriggerName,
    SourceSchema,
    SourceTableName,
    LoadType,
    WatermarkColumn,
    TargetContainerLanding,
    TargetContainerBronze,
    TargetContainerRaw,
    IsActive,
    SendAlert,
    PrimaryKeys,
    MandatoryColumns
)
VALUES
-- Table 1: Policies (Incremental)
(
    'Daily_Trigger',
    'dbo',
    'Policies',
    'Incremental',
    'ModifiedDate',
    'landing',
    'bronze',
    'raw',
    'Y',
    'Y',
    'PolicyID',
    'PolicyID,CustomerID,CoverageCode,PremiumAmount'
),
-- Table 2: Customers (Incremental)
(
    'Daily_Trigger',
    'dbo',
    'Customers',
    'Incremental',
    'ModifiedDate',
    'landing',
    'bronze',
    'raw',
    'Y',
    'Y',
    'CustomerID',
    'CustomerID,FirstName,LastName'
),
-- Table 3: CoverageTypes (Full Load - Reference / Dimension)
(
    'Daily_Trigger',
    'dbo',
    'CoverageTypes',
    'Full',
    NULL,
    'landing',
    'bronze',
    'raw',
    'Y',
    'Y',
    'CoverageCode',
    'CoverageCode,CoverageName'
),
-- Table 4: Claims (Incremental)
(
    'Daily_Trigger',
    'dbo',
    'Claims',
    'Incremental',
    'ModifiedDate',
    'landing',
    'bronze',
    'raw',
    'Y',
    'Y',
    'ClaimID',
    'ClaimID,PolicyID,ClaimAmount'
),
-- Table 5: Agents (Full Load - Reference / Dimension)
(
    'Daily_Trigger',
    'dbo',
    'Agents',
    'Full',
    NULL,
    'landing',
    'bronze',
    'raw',
    'Y',
    'Y',
    'AgentID',
    'AgentID,FirstName,LastName'
);
GO

-- 2. Initialize Watermark Table for Incremental Tables
INSERT INTO dbo.WatermarkTable (
    TableID,
    SourceTableName,
    WatermarkColumn,
    WatermarkValue,
    LastUpdatedDate
)
SELECT 
    TableID,
    SourceTableName,
    WatermarkColumn,
    '1900-01-01 00:00:00' AS WatermarkValue,
    SYSUTCDATETIME()
FROM dbo.IngestionMetadata
WHERE LoadType = 'Incremental';
GO

-- 3. Verify Seeded Metadata
SELECT 
    m.TableID,
    m.TriggerName,
    m.SourceTableName,
    m.LoadType,
    m.WatermarkColumn,
    w.WatermarkValue AS CurrentWatermark,
    m.IsActive,
    m.SendAlert,
    m.PrimaryKeys,
    m.MandatoryColumns
FROM dbo.IngestionMetadata m
LEFT JOIN dbo.WatermarkTable w ON m.TableID = w.TableID;
GO
