-- ==============================================================================
-- 01_unity_catalog_setup.sql
-- Description: Unity Catalog DDL for Storage Credentials, External Locations,
--              Catalogs, Schemas, and External Volumes.
-- Run in: Databricks SQL Editor or Databricks Notebook (as %sql)
-- Workspace: dbw-azureproject-dev-01
-- ==============================================================================

-- 1. Create Storage Credential using the Access Connector Managed Identity
-- Note: Databricks SQL syntax does NOT use "IF NOT EXISTS" for storage credentials.
CREATE STORAGE CREDENTIAL `adls_storage_credential`
WITH (
  AZURE_MANAGED_IDENTITY = (
    ACCESS_CONNECTOR_ID = '/subscriptions/841c4ab4-2ea9-4426-813d-9791abc4cff3/resourceGroups/rg-azureproject-dev-01/providers/Microsoft.Databricks/accessConnectors/ac-dbw-azureproject-dev-01'
  )
)
COMMENT 'Managed Identity Access Connector (ac-dbw-azureproject-dev-01) for ADLS Gen2';

-- 2. Create External Locations for Medallion Architecture Containers
-- Landing
CREATE EXTERNAL LOCATION IF NOT EXISTS `ext_loc_landing`
URL 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/'
WITH (STORAGE CREDENTIAL `adls_storage_credential`)
COMMENT 'External location for Landing container in ADLS Gen2';

-- Raw
CREATE EXTERNAL LOCATION IF NOT EXISTS `ext_loc_raw`
URL 'abfss://raw@azureprojectdevadls01.dfs.core.windows.net/'
WITH (STORAGE CREDENTIAL `adls_storage_credential`)
COMMENT 'External location for Raw container in ADLS Gen2';

-- Bronze
CREATE EXTERNAL LOCATION IF NOT EXISTS `ext_loc_bronze`
URL 'abfss://bronze@azureprojectdevadls01.dfs.core.windows.net/'
WITH (STORAGE CREDENTIAL `adls_storage_credential`)
COMMENT 'External location for Bronze container in ADLS Gen2';

-- Silver
CREATE EXTERNAL LOCATION IF NOT EXISTS `ext_loc_silver`
URL 'abfss://silver@azureprojectdevadls01.dfs.core.windows.net/'
WITH (STORAGE CREDENTIAL `adls_storage_credential`)
COMMENT 'External location for Silver container in ADLS Gen2';

-- Gold
CREATE EXTERNAL LOCATION IF NOT EXISTS `ext_loc_gold`
URL 'abfss://gold@azureprojectdevadls01.dfs.core.windows.net/'
WITH (STORAGE CREDENTIAL `adls_storage_credential`)
COMMENT 'External location for Gold container in ADLS Gen2';

-- 3. Create the 4 Medallion Catalogs
-- Catalog 1: Landing
CREATE CATALOG IF NOT EXISTS `landing_catalog`
MANAGED LOCATION 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/managed'
COMMENT 'Catalog for landing zone files and external volumes';

-- Catalog 2: Bronze
CREATE CATALOG IF NOT EXISTS `bronze_catalog`
MANAGED LOCATION 'abfss://bronze@azureprojectdevadls01.dfs.core.windows.net/managed'
COMMENT 'Catalog for Bronze layer ingested delta tables';

-- Catalog 3: Silver
CREATE CATALOG IF NOT EXISTS `silver_catalog`
MANAGED LOCATION 'abfss://silver@azureprojectdevadls01.dfs.core.windows.net/managed'
COMMENT 'Catalog for Silver layer cleaned and conformed delta tables';

-- Catalog 4: Gold
CREATE CATALOG IF NOT EXISTS `gold_catalog`
MANAGED LOCATION 'abfss://gold@azureprojectdevadls01.dfs.core.windows.net/managed'
COMMENT 'Catalog for Gold layer aggregated business delta tables and marts';

-- 4. Create Schemas
CREATE SCHEMA IF NOT EXISTS `landing_catalog`.`source_sql`
COMMENT 'Schema for incoming raw SQL source files';

CREATE SCHEMA IF NOT EXISTS `bronze_catalog`.`raw_data`
COMMENT 'Schema for Bronze raw Delta tables';

CREATE SCHEMA IF NOT EXISTS `silver_catalog`.`conformed`
COMMENT 'Schema for conformed business domain tables';

CREATE SCHEMA IF NOT EXISTS `gold_catalog`.`analytics`
COMMENT 'Schema for reporting and BI analytics';

-- 5. Create External Volumes for Landing CSV Files (Table-specific paths)
-- Volumes are registered pointing directly to each table's folder in ADLS Gen2:
CREATE EXTERNAL VOLUME IF NOT EXISTS `landing_catalog`.`source_sql`.`vol_policies`
LOCATION 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/home/datalake/claims/Policies'
COMMENT 'External landing volume for Policies table';

CREATE EXTERNAL VOLUME IF NOT EXISTS `landing_catalog`.`source_sql`.`vol_customers`
LOCATION 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/home/datalake/claims/Customers'
COMMENT 'External landing volume for Customers table';

CREATE EXTERNAL VOLUME IF NOT EXISTS `landing_catalog`.`source_sql`.`vol_coveragetypes`
LOCATION 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/home/datalake/claims/CoverageTypes'
COMMENT 'External landing volume for CoverageTypes table';

CREATE EXTERNAL VOLUME IF NOT EXISTS `landing_catalog`.`source_sql`.`vol_claims`
LOCATION 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/home/datalake/claims/Claims'
COMMENT 'External landing volume for Claims table';

CREATE EXTERNAL VOLUME IF NOT EXISTS `landing_catalog`.`source_sql`.`vol_agents`
LOCATION 'abfss://landing@azureprojectdevadls01.dfs.core.windows.net/home/datalake/claims/Agents'
COMMENT 'External landing volume for Agents table';

-- 6. Verification Queries
SHOW STORAGE CREDENTIALS;
SHOW EXTERNAL LOCATIONS;
SHOW CATALOGS;
SHOW VOLUMES IN `landing_catalog`.`source_sql`;
