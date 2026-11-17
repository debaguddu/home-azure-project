-- ==============================================================================
-- 01_create_metadata_and_log_tables.sql
-- Description: DDL script to create Metadata, Watermark, and Pipeline Log tables
--              along with supporting stored procedures in Azure SQL Database.
-- Database: sqldb-azureproject-dev-01
-- ==============================================================================

-- Drop dependent tables with foreign keys first to prevent error 3726
IF OBJECT_ID('dbo.WatermarkTable', 'U') IS NOT NULL
    DROP TABLE dbo.WatermarkTable;
GO

IF OBJECT_ID('dbo.DataTransformMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.DataTransformMetadata;
GO

IF OBJECT_ID('dbo.PipelineExecutionLog', 'U') IS NOT NULL
    DROP TABLE dbo.PipelineExecutionLog;
GO

IF OBJECT_ID('dbo.IngestionMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.IngestionMetadata;
GO

-- 1. Create IngestionMetadata Table
CREATE TABLE dbo.IngestionMetadata (
    TableID                 INT IDENTITY(1,1) PRIMARY KEY,
    TriggerName             VARCHAR(100) NOT NULL,              -- e.g. 'Daily_Trigger', 'Manual_Trigger'
    SourceSchema            VARCHAR(50)  NOT NULL DEFAULT 'dbo',-- e.g. 'dbo'
    SourceTableName         VARCHAR(100) NOT NULL,              -- e.g. 'Policies', 'Customers'
    LoadType                VARCHAR(20)  NOT NULL,              -- 'Full' or 'Incremental'
    WatermarkColumn         VARCHAR(100) NULL,                  -- e.g. 'ModifiedDate' (NULL for Full load)
    TargetContainerLanding  VARCHAR(100) NOT NULL DEFAULT 'landing',
    TargetContainerBronze   VARCHAR(100) NOT NULL DEFAULT 'bronze',
    IsActive                CHAR(1)      NOT NULL DEFAULT 'Y',  -- 'Y' or 'N'
    SendAlert               CHAR(1)      NOT NULL DEFAULT 'Y',  -- 'Y' or 'N'
    PrimaryKeys             VARCHAR(200) NULL,                  -- e.g. 'PolicyID' (used for duplicate checks)
    MandatoryColumns        VARCHAR(500) NULL,                  -- e.g. 'PolicyID,CustomerID' (used for NULL checks)
    CreatedDate             DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedDate             DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- 2. Create WatermarkTable
IF OBJECT_ID('dbo.WatermarkTable', 'U') IS NOT NULL
    DROP TABLE dbo.WatermarkTable;
GO

CREATE TABLE dbo.WatermarkTable (
    WatermarkID             INT IDENTITY(1,1) PRIMARY KEY,
    TableID                 INT NOT NULL FOREIGN KEY REFERENCES dbo.IngestionMetadata(TableID),
    SourceTableName         VARCHAR(100) NOT NULL,
    WatermarkColumn         VARCHAR(100) NOT NULL,
    WatermarkValue          VARCHAR(100) NOT NULL DEFAULT '1900-01-01 00:00:00',
    LastUpdatedDate         DATETIME2    NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

-- 3. Create PipelineExecutionLog Table
IF OBJECT_ID('dbo.PipelineExecutionLog', 'U') IS NOT NULL
    DROP TABLE dbo.PipelineExecutionLog;
GO

CREATE TABLE dbo.PipelineExecutionLog (
    LogID                   INT IDENTITY(1,1) PRIMARY KEY,
    BatchID                 VARCHAR(100) NOT NULL,              -- Master pipeline RunId
    PipelineRunID           VARCHAR(100) NOT NULL,              -- Current pipeline RunId
    PipelineName            VARCHAR(100) NOT NULL,              -- Pipeline Name
    TableID                 INT NULL,
    TableName               VARCHAR(100) NULL,
    LoadType                VARCHAR(20) NULL,
    Status                  VARCHAR(50) NOT NULL,               -- 'InProgress', 'Success', 'Failed'
    RowsCopied              BIGINT NULL,
    ErrorMessage            NVARCHAR(MAX) NULL,
    StartTime               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    EndTime                 DATETIME2 NULL,
    DurationInSeconds       INT NULL
);
GO

-- 4. Create DataTransformMetadata Table (Silver & Gold Orchestration)
IF OBJECT_ID('dbo.DataTransformMetadata', 'U') IS NOT NULL
    DROP TABLE dbo.DataTransformMetadata;
GO

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
GO

-- ==============================================================================
-- STORED PROCEDURES
-- ==============================================================================

-- Stored Procedure: sp_LogPipelineStart
IF OBJECT_ID('dbo.sp_LogPipelineStart', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_LogPipelineStart;
GO

CREATE PROCEDURE dbo.sp_LogPipelineStart
    @BatchID        VARCHAR(100),
    @PipelineRunID  VARCHAR(100),
    @PipelineName   VARCHAR(100),
    @TableID        INT = NULL,
    @TableName      VARCHAR(100) = NULL,
    @LoadType       VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO dbo.PipelineExecutionLog (
        BatchID,
        PipelineRunID,
        PipelineName,
        TableID,
        TableName,
        LoadType,
        Status,
        StartTime
    )
    VALUES (
        @BatchID,
        @PipelineRunID,
        @PipelineName,
        @TableID,
        @TableName,
        @LoadType,
        'InProgress',
        SYSUTCDATETIME()
    );

    SELECT SCOPE_IDENTITY() AS LogID;
END;
GO

-- Stored Procedure: sp_LogPipelineEnd
IF OBJECT_ID('dbo.sp_LogPipelineEnd', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_LogPipelineEnd;
GO

CREATE PROCEDURE dbo.sp_LogPipelineEnd
    @BatchID        VARCHAR(100),
    @PipelineRunID  VARCHAR(100),
    @Status         VARCHAR(50),
    @RowsCopied     BIGINT = NULL,
    @ErrorMessage   NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentTime DATETIME2 = SYSUTCDATETIME();

    UPDATE dbo.PipelineExecutionLog
    SET Status = @Status,
        RowsCopied = @RowsCopied,
        ErrorMessage = @ErrorMessage,
        EndTime = @CurrentTime,
        DurationInSeconds = DATEDIFF(SECOND, StartTime, @CurrentTime)
    WHERE BatchID = @BatchID
      AND PipelineRunID = @PipelineRunID;

    SELECT @@ROWCOUNT AS RowsUpdated;
END;
GO

-- Stored Procedure: sp_UpdateWatermark
IF OBJECT_ID('dbo.sp_UpdateWatermark', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_UpdateWatermark;
GO

CREATE PROCEDURE dbo.sp_UpdateWatermark
    @TableID            INT,
    @NewWatermarkValue  VARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NewWatermarkValue IS NOT NULL AND @NewWatermarkValue <> '' AND @NewWatermarkValue <> 'None'
    BEGIN
        UPDATE dbo.WatermarkTable
        SET WatermarkValue = @NewWatermarkValue,
            LastUpdatedDate = SYSUTCDATETIME()
        WHERE TableID = @TableID;
    END

    SELECT TableID, WatermarkValue, LastUpdatedDate
    FROM dbo.WatermarkTable
    WHERE TableID = @TableID;
END;
GO

-- Stored Procedure: sp_GetWatermark
IF OBJECT_ID('dbo.sp_GetWatermark', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_GetWatermark;
GO

CREATE PROCEDURE dbo.sp_GetWatermark
    @TableID INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT ISNULL(WatermarkValue, '1900-01-01 00:00:00') AS WatermarkValue
    FROM dbo.WatermarkTable
    WHERE TableID = @TableID;
END;
GO

-- Stored Procedure: sp_ResetWatermark
IF OBJECT_ID('dbo.sp_ResetWatermark', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ResetWatermark;
GO

CREATE PROCEDURE dbo.sp_ResetWatermark
    @TableID            INT = NULL,                                    -- NULL to reset all tables
    @SourceTableName    VARCHAR(100) = NULL,                           -- Optional: filter by table name
    @DefaultWatermark   VARCHAR(100) = '1900-01-01 00:00:00'          -- Default starting watermark
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.WatermarkTable
    SET WatermarkValue = @DefaultWatermark,
        LastUpdatedDate = SYSUTCDATETIME()
    WHERE (@TableID IS NULL OR TableID = @TableID)
      AND (@SourceTableName IS NULL OR SourceTableName = @SourceTableName);

    SELECT 
        WatermarkID, 
        TableID, 
        SourceTableName, 
        WatermarkColumn, 
        WatermarkValue, 
        LastUpdatedDate
    FROM dbo.WatermarkTable
    WHERE (@TableID IS NULL OR TableID = @TableID)
      AND (@SourceTableName IS NULL OR SourceTableName = @SourceTableName);
END;
GO

-- Stored Procedure: sp_ResetInProgressLogs
IF OBJECT_ID('dbo.sp_ResetInProgressLogs', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ResetInProgressLogs;
GO

CREATE PROCEDURE dbo.sp_ResetInProgressLogs
    @BatchID            VARCHAR(100)  = NULL,
    @PipelineName       VARCHAR(100)  = NULL,
    @NewStatus          VARCHAR(50)   = 'Failed',
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
END;
GO

