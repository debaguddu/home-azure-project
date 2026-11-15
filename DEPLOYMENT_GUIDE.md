# End-to-End Metadata-Driven Pipeline Framework Deployment Guide

## 1. Overview & Architecture
This framework implements a metadata-driven ingestion architecture connecting an On-Premises / EC2 SQL Server (`DemoDB`) to Azure Data Lake Storage Gen2 (`azureprojectdevadls01`) and Azure Databricks (`dbw-azureproject-dev-01`), coordinated by Azure Data Factory (`adf-azureproject-dev-01`) and Azure SQL Database (`sqldb-azureproject-dev-01`).

```
[On-Prem SQL Server (DemoDB)]
           │ (EC2-SQL-IR)
           ▼
[Child 1: Ingestion to ADLS Landing] ──> adls://landing/{TableName}/YYYY/MM/DD/*.csv
           │
           ▼
[Child 2: Processing to Bronze / Raw]
     ├── Full Load: Copy to Bronze (adls://bronze/{TableName}/{TableName}.csv)
     └── Incremental: Databricks Notebook (Serverless / Auto-cluster)
              │
              ├── Schema Evolution (mergeSchema = true)
              ├── DQ Checks (NULL check & Duplicate check)
              ├── Write to Delta (adls://raw/delta/{TableName})
              └── Return new max(ModifiedDate) to ADF
                        │
                        ▼
           [Update Watermark in ASQL DB]
                        │
                        ▼
           [Log Status & Send Alerts]
```

---

## 2. Step 1: Deploy Azure SQL Database Objects
Run the SQL scripts located in the `sql/` folder against `sqldb-azureproject-dev-01` (using Azure Portal **Query Editor**, SSMS, or Azure Data Studio):

1. **Create Tables & Stored Procedures**:
   - Open and execute [sql/01_create_metadata_and_log_tables.sql](file:///c:/Debaranjan/Git_Projects/home-azure-project/sql/01_create_metadata_and_log_tables.sql).
   - This creates:
     - `dbo.IngestionMetadata`
     - `dbo.WatermarkTable`
     - `dbo.PipelineExecutionLog`
     - Stored procedures: `sp_LogPipelineStart`, `sp_LogPipelineEnd`, `sp_UpdateWatermark`, `sp_GetWatermark`.

2. **Seed Metadata for DemoDB Tables**:
   - Open and execute [sql/02_seed_metadata.sql](file:///c:/Debaranjan/Git_Projects/home-azure-project/sql/02_seed_metadata.sql).
   - Seeds the 5 tables:
     - `Policies` (Incremental on `ModifiedDate`, PK: `PolicyID`)
     - `Customers` (Incremental on `ModifiedDate`, PK: `CustomerID`)
     - `CoverageTypes` (Full load, PK: `CoverageCode`)
     - `Claims` (Incremental on `ModifiedDate`, PK: `ClaimID`)
     - `Agents` (Full load, PK: `AgentID`)
   - Initializes initial watermarks (`1900-01-01 00:00:00`) in `dbo.WatermarkTable`.

---

## 3. Step 2: Deploy Databricks Notebook
The Databricks notebook is located in [databricks/notebooks/](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/notebooks):
- `nb_incremental_landing_to_raw.py`
- `nb_incremental_landing_to_raw.ipynb`

### Deployment Steps:
1. Open the Azure Databricks workspace `dbw-azureproject-dev-01` (`https://adb-7405612959366844.4.azuredatabricks.net`).
2. In the left navigation, click **Workspace** $\rightarrow$ **Shared**.
3. Create a folder named **`home_azure_project`**.
4. Right-click inside `home_azure_project` $\rightarrow$ **Import**.
5. Select and upload [nb_incremental_landing_to_raw.ipynb](file:///c:/Debaranjan/Git_Projects/home-azure-project/databricks/notebooks/nb_incremental_landing_to_raw.ipynb).
6. Verify the path is:
   `/Shared/home_azure_project/nb_incremental_landing_to_raw`
   *(This exact path is pre-configured in ADF Child Pipeline 2)*.

---

## 4. Step 3: Git Commit & Sync to ADF Studio
Commit and push the new ADF pipelines, datasets, and Databricks notebooks to `origin/project01`:
```powershell
git add .
git commit -m "feat: implement metadata-driven ingestion pipelines, ASQL DDL, and Databricks DQ notebook"
git push origin project01
```

Once pushed, switch to **Azure Data Factory Studio**:
- Make sure your working branch is **`project01`**.
- Refresh ADF Studio. You will immediately see:
  - **Pipelines**:
    - `PL_Master_Metadata_Ingestion`
    - `PL_Child1_Source_To_Landing`
    - `PL_Child2_Landing_To_Bronze_Raw`
  - **Datasets**:
    - `DS_SQL_Source`
    - `DS_ASQL_Generic`
    - `DS_ADLS_Landing_CSV`
    - `DS_ADLS_Bronze_CSV`

---

## 5. Step 4: Run & Test the Master Pipeline

### Test 1: Incremental Ingestion
1. Open `PL_Master_Metadata_Ingestion` in ADF Studio.
2. Click **Debug** / **Trigger Now**.
3. Supply parameters:
   - `TriggerName`: `Daily_Trigger`
   - `LoadType`: `Incremental`
4. Pipeline Execution Flow:
   - **Lookup_Log_Batch_Start**: Logs batch `InProgress` with unique BatchID.
   - **Lookup_Get_Metadata**: Retrieves the 3 active incremental tables (`Policies`, `Customers`, `Claims`).
   - **If_Tables_Exist**: Evaluates `count > 0` $\rightarrow$ triggers `ForEach_Table`.
   - **ForEach_Table** (Parallel batch):
     - Executes `PL_Child1_Source_To_Landing`: queries source records where `ModifiedDate > WatermarkValue` and lands CSVs in `landing/{TableName}/YYYY/MM/DD/`.
     - Executes `PL_Child2_Landing_To_Bronze_Raw`: calls Databricks notebook, runs DQ NULL/duplicate checks, appends to Delta table in `raw/delta/{TableName}`, and updates `WatermarkTable`.
   - **Lookup_Log_Batch_End_Success**: Updates batch log to `Success`.

### Test 2: Full Load Ingestion
1. Trigger `PL_Master_Metadata_Ingestion` with parameters:
   - `TriggerName`: `Daily_Trigger`
   - `LoadType`: `Full`
2. Pipeline Execution Flow:
   - Pulls active full-load tables (`CoverageTypes`, `Agents`).
   - Copies full source table to Landing Zone.
   - Child 2 copies Landing Zone CSV directly into Bronze container as `tablename.csv` (full replacement).
   - Logs execution in `PipelineExecutionLog`.

