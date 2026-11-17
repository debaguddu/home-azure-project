---
marp: true
theme: default
paginate: true
header: "Metadata-Driven Medallion Data Platform"
footer: "Microsoft Azure & Databricks Architecture"
---

# Metadata-Driven Medallion Data Platform
## Architecting Enterprise Data Lakehouse on Azure & Databricks
**Azure Data Factory | Delta Lake | Unity Catalog | Power BI**

---

# Business Objectives & Challenges

* **The Problem:**
  - Siloed on-premises SQL Server data with manual, fragile point-to-point ETL pipelines.
  - High risk of duplicate data loading during frequent intraday pipeline runs.
  - Slow, unoptimized BI query performance on raw data.
  - Lack of centralized access controls, data lineage, and audit trails.

* **The Solution:**
  - **100% Metadata-Driven Ingestion:** Dynamic table ingestion via metadata configuration.
  - **Multi-Hop Medallion Lakehouse:** Bronze (Raw Delta) $\rightarrow$ Silver (Conformed) $\rightarrow$ Gold (Curated Marts) $\rightarrow$ Semantic Reporting Views.
  - **Idempotent Ingestion:** Isolated file parameter binding prevents cross-run duplicate loading.
  - **Unified Governance:** Azure Databricks Unity Catalog 3-level namespace (`catalog.schema.table`).

---

# Medallion Architecture Overview

| Layer | Catalog / Storage Path | Data Maturity | Format | Target Consumer |
|---|---|---|---|---|
| **Landing** | `adls://landing/home/.../{Table}/{Date}/{File}.csv` | Raw Snapshot | CSV | Ephemeral staging |
| **Bronze** | `bronze_catalog.raw_data` | As-Is Ingested | Delta Lake | Data Engineers |
| **Silver** | `silver_catalog.insurance_conformed` | Cleansed, Typed, Conformed | Delta Lake (SCD1) | Analytics Engineers |
| **Gold** | `gold_catalog.insurance_analytics` | Curated Business Marts | Delta Lake (Star Schema) | Data Scientists / Analysts |
| **Semantic** | `gold_catalog.semantic_reporting` | Direct BI Reporting Views | Unity Catalog Views | C-Suite / Power BI |

---

# Core Business Entity Joins & Data Lineage

* **`fact_policy_performance` (Underwriting Mart):**
  - `fct_policy` **LEFT JOIN** `dim_customer` on `CustomerID`
  - **LEFT JOIN** `dim_agent` on `AgentID`
  - **LEFT JOIN** `dim_coverage` on `CoverageCode`
  - **LEFT JOIN** Aggregated `fct_claim` on `PolicyID`
  - *Value:* Computes Net Profit Margin (`Premium - Claims`) and Policy Loss Ratio %.

* **`fact_claims_settlement` (Claims Adjudication Mart):**
  - `fct_claim` **LEFT JOIN** `fct_policy` on `PolicyID`
  - **LEFT JOIN** `dim_customer` on `CustomerID`
  - *Value:* Evaluates Deductible Compliance, Payout Ratio %, and Severity Tiers.

---

# Key Performance Indicators (KPIs)

1. **Portfolio Loss Ratio (%):**
   $$\text{Loss Ratio} = \left(\frac{\text{Total Incurred Claims}}{\text{Gross Written Premium}}\right) \times 100$$
   - $\le 60\%$: Profitable (Healthy)
   - $61\% - 75\%$: Acceptable
   - $> 75\%$: Critical (Loss Incurring)

2. **Claims Payout Settlement Ratio (%):**
   $$\text{Payout Ratio} = \left(\frac{\text{Settled Amount}}{\text{Claim Amount}}\right) \times 100$$

3. **Claims Turnaround Cycle Time (Days):**
   $$\text{Settlement Days} = \text{DATEDIFF}(\text{ClaimDate}, \text{IncidentDate})$$
   - SLA Breach Alert triggered for claims pending $> 30$ days.

---

# Curated Semantic BI Views

* **`vw_executive_kpi_dashboard`**:
  - C-Suite executive summary tracking Gross Written Premium, Loss Ratio trend, and active policy count.

* **`vw_claims_analyst_workbench`**:
  - Operational claims adjuster view with deductible flags, severity tiering, and turnaround alerts.

* **`vw_agent_leaderboard`**:
  - Producer sales rankings, premium volume, and portfolio loss ratio.

* **`vw_customer_360`**:
  - Single customer intelligence profile: Lifetime premium, claim history, and risk classification.

---

# Enterprise Security & Operational Resilience

* **Managed Identity (MSI):** Zero hardcoded credentials or PAT tokens across ADF and Databricks.
* **Idempotent Ingestion:** Passing specific landed filename from ADF Child 1 to Databricks ensures exact file isolation.
* **Environment Maintenance Utility:**
  - Dedicated service pipeline `PL_Service_Cleanup_Tables` and notebook `nb_service_cleanup_tables` enable 1-click test environment resets.
* **Audit & Watermarking:** Centralized logging via `dbo.PipelineExecutionLog` and dynamic watermark tracking via `dbo.WatermarkTable`.

---

# Summary & Next Steps

* **Current State:**
  - All 5 Medallion tiers deployed, tested, and version-controlled on `origin/project01`.
  - Automated ADF orchestration from On-Premises SQL through Semantic Views.

* **Future Enhancements:**
  - **Power BI Direct Lake:** Connect directly to Gold Delta tables without scheduled refreshes.
  - **ML Predictive Models:** Claims fraud detection and policy churn prediction using Databricks MLflow.
  - **CI/CD Automation:** Azure DevOps / GitHub Actions pipeline for automated environment promotion.
