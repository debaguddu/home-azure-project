-- ==============================================================================
-- 02_seed_metadata.sql
-- Description: Seed metadata for the 5 DemoDB tables into IngestionMetadata
--              and initialize initial watermark values in WatermarkTable.
-- Database: sqldb-azureproject-dev-01
-- ==============================================================================

-- 0. Ensure DataTransformMetadata Table Exists (self-healing if 01 was executed earlier)
IF OBJECT_ID('dbo.DataTransformMetadata', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.DataTransformMetadata (
        TransformID             INT IDENTITY(1,1) PRIMARY KEY,
        Layer                   VARCHAR(20) NOT NULL,              -- 'Silver', 'Gold', 'Semantic'
        TargetCatalog           VARCHAR(50) NOT NULL,              -- e.g. 'silver_catalog', 'gold_catalog'
        TargetSchema            VARCHAR(50) NOT NULL,              -- e.g. 'insurance_conformed', 'insurance_analytics'
        TargetTableName         VARCHAR(100) NOT NULL,
        SourceTables            VARCHAR(255) NOT NULL,             -- Source dependencies
        TransformationType      VARCHAR(50) NOT NULL,              -- 'Dimension_SCD1', 'Fact_Incremental', 'Aggregate_Mart', 'Semantic_View'
        ExecutionOrder          INT NOT NULL DEFAULT 1,
        IsActive                CHAR(1) NOT NULL DEFAULT 'Y',
        Description             NVARCHAR(500) NULL,
        CreatedDate             DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
    );
END
GO

-- Clear existing sample records if re-running
IF OBJECT_ID('dbo.WatermarkTable', 'U') IS NOT NULL
    DELETE FROM dbo.WatermarkTable;

IF OBJECT_ID('dbo.DataTransformMetadata', 'U') IS NOT NULL
    DELETE FROM dbo.DataTransformMetadata;

IF OBJECT_ID('dbo.IngestionMetadata', 'U') IS NOT NULL
    DELETE FROM dbo.IngestionMetadata;

IF OBJECT_ID('dbo.IngestionMetadata', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.IngestionMetadata', RESEED, 0);

IF OBJECT_ID('dbo.WatermarkTable', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.WatermarkTable', RESEED, 0);

IF OBJECT_ID('dbo.DataTransformMetadata', 'U') IS NOT NULL
    DBCC CHECKIDENT ('dbo.DataTransformMetadata', RESEED, 0);
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

-- 3. Seed Silver and Gold Transformations Metadata
INSERT INTO dbo.DataTransformMetadata (
    Layer,
    TargetCatalog,
    TargetSchema,
    TargetTableName,
    SourceTables,
    TransformationType,
    ExecutionOrder,
    IsActive,
    Description
)
VALUES
-- Silver Layer: Conformed Dimensions & Facts
('Silver', 'silver_catalog', 'insurance_conformed', 'dim_customer', 'Customers', 'Dimension_SCD1', 1, 'Y', 'Cleansed, deduplicated, standardized Customer Dimension with contact hygiene and customer lifetime tenure'),
('Silver', 'silver_catalog', 'insurance_conformed', 'dim_agent', 'Agents', 'Dimension_SCD1', 1, 'Y', 'Conformed Agent Dimension with branch and sales territory mapping'),
('Silver', 'silver_catalog', 'insurance_conformed', 'dim_coverage', 'CoverageTypes', 'Dimension_SCD1', 1, 'Y', 'Standardized Insurance Coverage Types Reference with normalized policy categories'),
('Silver', 'silver_catalog', 'insurance_conformed', 'fct_policy', 'Policies', 'Fact_Incremental', 2, 'Y', 'Conformed Policy Lifecycle Fact with validated dates, premium formatting, and active status tracking'),
('Silver', 'silver_catalog', 'insurance_conformed', 'fct_claim', 'Claims', 'Fact_Incremental', 2, 'Y', 'Conformed Claims Transactions Fact with loss amounts, settlement flags, and turnaround cycle time'),

-- Gold Layer: Analytical Star Schema & Business Marts
('Gold', 'gold_catalog', 'insurance_analytics', 'fact_policy_performance', 'fct_policy,dim_customer,dim_agent,dim_coverage', 'Curated_Fact', 3, 'Y', 'Curated Policy Performance Fact enriched with Customer, Agent, and Coverage dimensions for underwriting analysis'),
('Gold', 'gold_catalog', 'insurance_analytics', 'fact_claims_settlement', 'fct_claim,fct_policy,dim_customer', 'Curated_Fact', 3, 'Y', 'Claims Adjudication & Settlement Analysis Fact with severity classification and claim ratio'),
('Gold', 'gold_catalog', 'insurance_analytics', 'agg_agent_performance_monthly', 'fct_policy,fct_claim,dim_agent', 'Aggregate_Mart', 4, 'Y', 'Monthly Agent Sales and Loss Performance Mart tracking written premiums vs incurred claims'),
('Gold', 'gold_catalog', 'insurance_analytics', 'agg_claims_loss_ratio_by_coverage', 'fct_policy,fct_claim,dim_coverage', 'Aggregate_Mart', 4, 'Y', 'Monthly Loss Ratio and Profitability Mart aggregated by Coverage Type and Line of Business'),
('Gold', 'gold_catalog', 'insurance_analytics', 'agg_customer_risk_profile', 'fct_policy,fct_claim,dim_customer', 'Aggregate_Mart', 4, 'Y', 'Customer 360 Risk Profile Mart computing lifetime policy value, claim frequency, and risk tier'),

-- Semantic Layer: BI / Power BI Views
('Semantic', 'gold_catalog', 'semantic_reporting', 'vw_executive_kpi_dashboard', 'fact_policy_performance,fact_claims_settlement', 'Semantic_View', 5, 'Y', 'Executive KPI Summary View: Total GWP, Incurred Claims, Loss Ratio %, Active Policy Count'),
('Semantic', 'gold_catalog', 'semantic_reporting', 'vw_claims_analyst_workbench', 'fact_claims_settlement', 'Semantic_View', 5, 'Y', 'Adjudicator Workbench View: High-value pending claims, anomalous payouts, and turnaround breaches'),
('Semantic', 'gold_catalog', 'semantic_reporting', 'vw_agent_leaderboard', 'agg_agent_performance_monthly,dim_agent', 'Semantic_View', 5, 'Y', 'Agent Sales Leaderboard View: Premium rankings, retention rate, and portfolio loss ratio'),
('Semantic', 'gold_catalog', 'semantic_reporting', 'vw_customer_360', 'agg_customer_risk_profile,dim_customer', 'Semantic_View', 5, 'Y', 'Customer 360 View: Unified demographic, policy portfolio, and claim history profile');
GO

-- 4. Verify Seeded Metadata
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

SELECT 
    TransformID,
    Layer,
    TargetCatalog,
    TargetSchema,
    TargetTableName,
    TransformationType,
    ExecutionOrder,
    IsActive
FROM dbo.DataTransformMetadata
ORDER BY ExecutionOrder, TransformID;
GO

