# End-to-End Metadata-Driven Medallion Data Platform Deployment Guide

Comprehensive deployment, configuration, and operational guide for the enterprise Medallion Data Platform on Microsoft Azure and Databricks.

---

## 📑 Table of Contents
1. [Architecture Overview](#1-architecture-overview)
2. [Prerequisites & Resource Inventory](#2-prerequisites--resource-inventory)
3. [Step 1: Security & Azure Key Vault Secrets](#3-step-1-security--azure-key-vault-secrets)
4. [Step 2: Deploy SQL Control Plane Objects](#4-step-2-deploy-sql-control-plane-objects)
5. [Step 3: Configure Azure Databricks (Unity Catalog & Serverless Jobs)](#5-step-3-configure-azure-databricks-unity-catalog--serverless-jobs)
6. [Step 4: Configure GitHub Actions CI/CD (ADF Auto-Publish & Databricks Auto-Pull)](#6-step-4-configure-github-actions-cicd-adf-auto-publish--databricks-auto-pull)
7. [Step 5: End-to-End Pipeline Execution & Verification](#7-step-5-end-to-end-pipeline-execution--verification)
8. [Step 6: Scheduled Triggers](#8-step-6-scheduled-triggers)
9. [Step 7: Maintenance & 1-Click Environment Reset](#9-step-7-maintenance--1-click-environment-reset)
10. [Security & Credential Best Practices](#10-security--credential-best-practices)

---

## 1. Architecture Overview

This platform implements a robust, metadata-driven architecture connecting an On-Premises / Hybrid SQL Server (`DemoDB`) to Azure Data Lake Storage Gen2 and Azure Databricks, orchestrated by Azure Data Factory:

```
[Source SQL Server (DemoDB)]
           │ (Self-Hosted IR on EC2)
           ▼
[Child 1: Ingestion to ADLS Landing] ──> adls://landing/home/datalake/claims/{Table}/{YYYY}/{MM}/{DD}/*.csv (Pipe |)
           │
           ▼
[Child 2: Ingestion to Bronze Raw]
     ├── Full Load: Snappy Parquet (adls://bronze/{Table}/{Table}.parquet)
     └── Incremental Load: Serverless Databricks Job (Delta MERGE + DQ Null/Duplicate Checks)
           │
           ▼
[Child 3: Bronze to Silver Conformed] ──> Delta Lake (silver_catalog.insurance_conformed)
           │                             (Cleaned Dims: dim_customer, dim_agent, dim_coverage; Facts: fct_policy, fct_claim)
           ▼
[Child 4: Silver to Gold & Semantic]  ──> Star Schema Marts (gold_catalog.insurance_analytics)
                                         Reporting Views (gold_catalog.semantic_reporting)
```

---

## 2. Prerequisites & Resource Inventory

Ensure the following Azure resources are provisioned in your target subscription:

| Resource Type | Resource Name | Purpose / Configuration |
|---|---|---|
| **Resource Group** | `rg-azureproject-dev-01` | Core container in your target region |
| **ADLS Gen2** | `azureprojectdevadls01` | Storage account with **Hierarchical Namespace** enabled (Containers: `landing`, `raw`, `bronze`, `silver`, `gold`) |
| **Azure Key Vault** | `kv-azureproject-dev-01` | Central secret store for database passwords |
| **Azure SQL Database** | `sqldb-azureproject-dev-01` | Serverless Free-Tier SQL DB hosting the metadata control plane |
| **Azure Databricks** | `dbw-azureproject-dev-01` | Premium SKU workspace with Unity Catalog enabled |
| **Access Connector** | `ac-dbw-azureproject-dev-01` | Managed Identity for Databricks to access ADLS Gen2 storage |
| **Azure Data Factory** | `adf-azureproject-dev-01` | v2 factory with System-Assigned Managed Identity |
| **Self-Hosted IR** | `EC2-SQL-IR` | Integration Runtime installed on the source SQL Server network |

---

## 3. Step 1: Security & Azure Key Vault Secrets

All database credentials must be stored in Azure Key Vault. Never hardcode credentials in pipelines or code.

1. Open **`kv-azureproject-dev-01`** in the Azure Portal $\rightarrow$ **Secrets** $\rightarrow$ **Generate/Import**.
2. Create the following secrets:
   - **`asql-pass`**: Password for Azure SQL Database user.
   - **`aws-sql-pass`**: Password for source SQL Server (`DemoDB`) user.
3. Grant Azure Data Factory permission to read secrets:
   - In Key Vault $\rightarrow$ **Access configuration**, ensure Azure RBAC or Access Policies are enabled.
   - Assign the **`Key Vault Secrets User`** role to the Managed Identity of `adf-azureproject-dev-01`.

---

## 4. Step 2: Deploy SQL Control Plane Objects

Execute the SQL scripts against `sqldb-azureproject-dev-01` (using Azure Portal **Query Editor**, SSMS, or Azure Data Studio):

### A. Create Tables & Stored Procedures
Execute [sql/01_create_metadata_and_log_tables.sql](file:///c:/Debaranjan/Git_Projects/home-azure-project/sql/01_create_metadata_and_log_tables.sql):
- Creates control tables:
  - `dbo.IngestionMetadata`: Ingestion configurations, load types (`Full`/`Incremental`), primary keys, and paths.
  - `dbo.WatermarkTable`: High-watermark tracking for incremental extraction.
  - `dbo.PipelineExecutionLog`: Audit log tracking pipeline run status, durations, row counts, and error messages.
- Creates stored procedures: `sp_LogPipelineStart`, `sp_LogPipelineEnd`, `sp_UpdateWatermark`, `sp_GetWatermark`.

### B. Seed Metadata
Execute [sql/02_seed_metadata.sql](file:///c:/Debaranjan/Git_Projects/home-azure-project/sql/02_seed_metadata.sql):
- Registers the 5 core tables:
  - `Policies` (Incremental on `ModifiedDate`, PK: `PolicyID`)
  - `Customers` (Incremental on `ModifiedDate`, PK: `CustomerID`)
  - `CoverageTypes` (Full load, PK: `CoverageCode`)
  - `Claims` (Incremental on `ModifiedDate`, PK: `ClaimID`)
  - `Agents` (Full load, PK: `AgentID`)
- Initializes baseline watermarks (`1900-01-01 00:00:00`) in `dbo.WatermarkTable`.
- Seeds metadata definitions for Silver conformed models and Gold analytical marts.

---

## 5. Step 3: Configure Azure Databricks (Unity Catalog & Serverless Jobs)

### A. Create Azure Key Vault-Backed Secret Scope
1. Log into your Databricks workspace: `https://<databricks-instance>.azuredatabricks.net`
2. Navigate to: `https://<databricks-instance>.azuredatabricks.net#secrets/createScope`
3. Enter the configuration:
   - **Scope Name**: `akv-scope`
   - **Manage Principal**: `Creator`
   - **DNS Name**: `https://kv-azureproject-dev-01.vault.azure.net/`
   - **Resource ID**: `/subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-azureproject-dev-01/providers/Microsoft.KeyVault/vaults/kv-azureproject-dev-01`
4. Click **Create**.

### B. Unity Catalog DDL Setup
1. In Databricks, open the **SQL Editor**.
2. Execute [databricks/sql/01_unity_catalog_setup.sql](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/sql/01_unity_catalog_setup.sql) (replace `<YOUR_SUBSCRIPTION_ID>` with your subscription GUID):
   - **Storage Credential**: `adls_storage_credential` (using Managed Identity `ac-dbw-azureproject-dev-01`).
   - **External Locations**: `ext_loc_landing`, `ext_loc_raw`, `ext_loc_bronze`, `ext_loc_silver`, `ext_loc_gold`.
   - **4 Catalogs**: `landing_catalog`, `bronze_catalog`, `silver_catalog`, `gold_catalog`.
   - **External Volume**: `landing_catalog.source_sql.landing_volume`.

### C. Connect Git Folder in Databricks
1. In Databricks, go to **Workspace** $\rightarrow$ **Repos** (or **Git Folders**).
2. Click **Add Repo** and link your repository:
   - **Git provider**: GitHub
   - **Repository URL**: `https://github.com/debaguddu/home-azure-project.git`
   - **Branch**: `develop` (or `project01`)
3. Note the numeric ID in the URL (`/browse/folders/<numeric-id>`) — this is your `DATABRICKS_REPO_ID`.

### D. Serverless Databricks Workflows (Free-Tier Friendly)
To bypass workspace cluster creation quota limits, all activities run as **Databricks Serverless Jobs**:
- **Landing to Raw Ingestion**: Job ID `202308513646851` ([job_incremental_landing_to_raw.yml](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/workflows/job_incremental_landing_to_raw.yml))
- **Sync Full Load Bronze**: Job ID `308693633677595` ([job_sync_full_load_bronze.yml](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/workflows/job_sync_full_load_bronze.yml))
- **Bronze to Silver**: Job ID `466350837846976` ([job_bronze_to_silver.yml](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/workflows/job_bronze_to_silver.yml))
- **Silver to Gold & Semantic**: Job ID `1076549010168499` ([job_silver_to_gold.yml](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/workflows/job_silver_to_gold.yml))
- **Service Cleanup Utility**: Job ID `734292707355697` ([job_service_cleanup_tables.yml](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/workflows/job_service_cleanup_tables.yml))

---

## 6. Step 4: Configure GitHub Actions CI/CD (ADF Auto-Publish & Databricks Auto-Pull)

Automated publishing ensures that changes pushed to `develop` compile ARM templates into `adf_publish` and update Databricks workspaces without manual clicks.

### Required GitHub Repository Secrets
Navigate to your GitHub repository $\rightarrow$ **Settings** $\rightarrow$ **Secrets and variables** $\rightarrow$ **Actions** $\rightarrow$ **New repository secret**:

| Secret Name | Description / Example Value |
|---|---|
| `AZURE_SUBSCRIPTION_ID` | Your Azure Subscription GUID (`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`) |
| `AZURE_RESOURCE_GROUP` | Resource Group name (`rg-azureproject-dev-01`) |
| `DATABRICKS_TOKEN` | Databricks Personal Access Token (PAT) with `all-apis` or `repos` scope |
| `DATABRICKS_REPO_ID` | Numeric Git folder ID from Databricks URL (e.g., `2906326734200206`) |
| `DATABRICKS_HOST` | *(Optional)* Workspace URL (defaults to `https://adb-7405612959366844.4.azuredatabricks.net`) |

### Workflow Mechanics ([.github/workflows/adf_auto_publish.yml](file:///c:/Debaranjan/Git_Projects/home-azure-project/.github/workflows/adf_auto_publish.yml)):
1. **Trigger**: Any push to branch `develop`.
2. **Step 1 - Build**: Uses `@microsoft/azure-data-factory-utilities` to validate all pipelines/datasets and export ARM templates.
3. **Step 2 - Publish**: Commits and pushes freshly built ARM templates directly to the `adf_publish` branch.
4. **Step 3 - Sync Databricks**: Calls the Databricks Repos REST API (`PATCH /api/2.0/repos/{repo_id}`) to pull the latest `develop` commit into the workspace.

---

## 7. Step 5: End-to-End Pipeline Execution & Verification

### Master Pipeline Execution
1. Open Azure Data Factory Studio $\rightarrow$ **Author** $\rightarrow$ **Pipelines**.
2. Select **`PL_Master_Medallion_End_To_End`**.
3. Click **Debug** or **Trigger Now** with parameters:
   - `LoadType`: `Full` (for initial load) or `Incremental` (for daily delta processing).
   - `TriggerName`: `Manual_Trigger`

```
PL_Master_Medallion_End_To_End
  │
  ├── Stage 1: Ingestion Master (PL_Master_Metadata_Ingestion)
  │     └── ForEach Table (Parallel batching):
  │           ├── PL_Child1_Source_To_Landing (Extracts SQL Server via SHIR to Landing CSV)
  │           └── PL_Child2_Landing_To_Bronze_Raw (Parquet for Full / Databricks Delta MERGE for Incremental)
  │
  ├── Stage 2: Silver Conformed (PL_Child3_Bronze_To_Silver)
  │     └── Databricks Serverless Job (Cleans & conformed dimensions & facts with SCD Type 1 upsert)
  │
  └── Stage 3: Gold Analytics & Semantic Views (PL_Child4_Silver_To_Gold)
        └── Databricks Serverless Job (Calculates Loss Ratio %, Settlement Turnaround, Agent Rankings, and deploys UC Views)
```

### Verification Queries
Run these queries in Azure SQL Database and Databricks to verify execution:

```sql
-- 1. Check Pipeline Audit Log (Azure SQL DB)
SELECT TOP 10 BatchID, PipelineName, TableName, LoadType, Status, RowsRead, RowsCopied, StartTime, EndTime, DurationSeconds
FROM dbo.PipelineExecutionLog
ORDER BY StartTime DESC;

-- 2. Verify Incremental Watermarks (Azure SQL DB)
SELECT TableName, WatermarkColumn, WatermarkValue, LastUpdated
FROM dbo.WatermarkTable;

-- 3. Check Gold Semantic KPIs (Databricks SQL Editor)
SELECT * FROM gold_catalog.semantic_reporting.vw_executive_kpi_dashboard;
SELECT * FROM gold_catalog.semantic_reporting.vw_agent_leaderboard ORDER BY TotalGrossWrittenPremium DESC;
```

---

## 8. Step 6: Scheduled Triggers

Two schedule triggers are configured in ADF for daily automated operation:

| Trigger Name | Schedule (IST) | Target Pipeline | LoadType Parameter |
|---|---|---|---|
| [TR_Medallion_Daily_Full_Load](file:///c:/Debaranjan/Git_Projects/home-azure-project/trigger/TR_Medallion_Daily_Full_Load.json) | Daily at **16:30 IST** | `PL_Master_Medallion_End_To_End` | `Full` |
| [TR_Medallion_Daily_Incremental_Load](file:///c:/Debaranjan/Git_Projects/home-azure-project/trigger/TR_Medallion_Daily_Incremental_Load.json) | Daily at **16:45 IST** | `PL_Master_Medallion_End_To_End` | `Incremental` |

---

## 9. Step 7: Maintenance & 1-Click Environment Reset

If you need to wipe test data, drop test tables, or restart from a clean slate:
1. Open **`PL_Service_Cleanup_Tables`** in ADF Studio.
2. Click **Trigger Now** with parameter:
   - `TableName`: `ALL` (or specify an individual table name, e.g. `Policies`).
3. The serverless cleanup job:
   - Drops Unity Catalog tables in `bronze_catalog`, `silver_catalog`, and `gold_catalog`.
   - Cleans storage files in `raw/delta/` and `bronze/`.
   - Resets watermark timestamps in `dbo.WatermarkTable` back to `1900-01-01 00:00:00`.

---

## 10. Security & Credential Best Practices

1. **Never Commit Secrets**:
   - `terraform.tfvars`, `.env`, and private key files are strictly excluded via `.gitignore`.
   - Always copy `terraform.tfvars.example` to `terraform.tfvars` locally and fill in credentials outside of version control.
2. **Managed Identities (MSI)**:
   - ADF authenticates to Azure Databricks and ADLS Gen2 using Managed Identity — eliminating password expiration risks.
3. **GitHub Actions Secrets**:
   - Cloud subscription IDs, resource group names, and Databricks PATs are passed securely through encrypted GitHub Secrets and never written in public workflow YAML files.
