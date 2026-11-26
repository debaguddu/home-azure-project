# Databricks Delta Live Tables (DLT) Masterclass Pipeline
# Target Audience: Azure Data Engineers & Senior Technical Interviews
# Purpose: Comprehensive declarative Medallion pipeline covering Auto Loader,
# Data Quality Expectations (@dlt.expect, @dlt.expect_or_drop, @dlt.expect_or_fail),
# Intermediate In-Memory Views, Quarantine Pattern, and CDC/SCD with dlt.apply_changes().

import dlt
from pyspark.sql.functions import col, current_timestamp, initcap, trim, expr, when, count, sum, avg, max, round

# -----------------------------------------------------------------------------
# 0. PIPELINE CONFIGURATION & INPUT PATH
# In DLT Settings, specify: "dlt_input_path": "abfss://raw@azureprojectdevadls01.dfs.core.windows.net/dlt_policies_input/"
# If not specified, defaults to the ADLS Gen2 landing path or DBFS fallback.
# -----------------------------------------------------------------------------
try:
    input_path = spark.conf.get("dlt_input_path")
except Exception:
    input_path = "abfss://raw@azureprojectdevadls01.dfs.core.windows.net/dlt_policies_input/"

# -----------------------------------------------------------------------------
# 1. BRONZE LAYER: Raw Streaming Ingestion with Auto Loader (cloudFiles)
# Features:
# - Schema inference & evolution
# - _rescued_data column to capture corrupt/unparseable records
# - Incrementally detects new CSV files dropped into storage
# -----------------------------------------------------------------------------
@dlt.table(
    name="bronze_policies_raw",
    comment="Raw streaming ingestion of policy files from ADLS Gen2 via Auto Loader",
    table_properties={
        "quality": "bronze",
        "pipelines.autoOptimize.zOrderCols": "PolicyID"
    }
)
def bronze_policies_raw():
    return (
        spark.readStream.format("cloudFiles")
            .option("cloudFiles.format", "csv")
            .option("header", "true")
            .option("cloudFiles.inferColumnTypes", "true")
            .option("cloudFiles.schemaLocation", f"{input_path}/_schema_checkpoint")
            .option("cloudFiles.rescuedDataColumn", "_rescued_data")
            .load(input_path)
    )

# -----------------------------------------------------------------------------
# 2. SILVER LAYER: Data Cleansing & Data Quality Expectations
# Demonstrates all 3 DLT Expectation Action Modes:
# 1. @dlt.expect_or_fail -> Halts pipeline if critical PK is NULL
# 2. @dlt.expect_or_drop -> Silently drops invalid records (e.g. negative premium)
# 3. @dlt.expect         -> Keeps record, but tracks data quality alert in UI metrics
# -----------------------------------------------------------------------------
@dlt.table(
    name="silver_policies_cleaned",
    comment="Cleansed policies with strict quality constraints enforced",
    table_properties={"quality": "silver"}
)
@dlt.expect_or_fail("valid_policy_id", "PolicyID IS NOT NULL")
@dlt.expect_or_drop("valid_premium_amount", "PremiumAmount > 0")
@dlt.expect("warn_high_deductible", "DeductibleAmount <= 10000")
def silver_policies_cleaned():
    return (
        dlt.read_stream("bronze_policies_raw")
            .withColumn("PolicyType", initcap(trim(col("PolicyType"))))
            .withColumn("CustomerCity", initcap(trim(col("CustomerCity"))))
            .withColumn("SilverIngestedAt", current_timestamp())
    )

# -----------------------------------------------------------------------------
# 3. QUARANTINE PATTERN (Capturing Rejected Records for Data Governance Audits)
# Routes dirty records that violated quality rules into a separate quarantine table
# -----------------------------------------------------------------------------
@dlt.table(
    name="silver_policies_quarantine",
    comment="Quarantine table capturing records rejected by data quality constraints",
    table_properties={"quality": "quarantine"}
)
def silver_policies_quarantine():
    return (
        dlt.read_stream("bronze_policies_raw")
            .filter("PremiumAmount <= 0 OR PolicyID IS NULL OR _rescued_data IS NOT NULL")
            .withColumn("QuarantinedAt", current_timestamp())
    )

# -----------------------------------------------------------------------------
# 4. INTERMEDIATE DLT VIEW (Zero Storage Cost)
# DLT Views exist only in memory during execution DAG computation.
# They are NOT materialized to Delta storage, saving disk space and I/O.
# -----------------------------------------------------------------------------
@dlt.view(
    name="vw_active_policies",
    comment="Intermediate in-memory view filtering active policies without storage cost"
)
def vw_active_policies():
    return (
        dlt.read("silver_policies_cleaned")
            .filter(col("PolicyStatus") == "ACTIVE")
    )

# -----------------------------------------------------------------------------
# 5. GOLD LAYER: Business Reporting & KPI Aggregation
# Materialized analytical table consumed by BI tools (PowerBI, Tableau)
# -----------------------------------------------------------------------------
@dlt.table(
    name="gold_policy_executive_kpi",
    comment="Executive summary metrics aggregated by Policy Type and Customer City",
    table_properties={"quality": "gold"}
)
def gold_policy_executive_kpi():
    return (
        dlt.read("vw_active_policies")
            .groupBy("PolicyType", "CustomerCity")
            .agg(
                count("PolicyID").alias("ActivePolicyCount"),
                round(sum("PremiumAmount"), 2).alias("TotalWrittenPremium"),
                round(avg("PremiumAmount"), 2).alias("AveragePremium"),
                round(max("DeductibleAmount"), 2).alias("MaxDeductible")
            )
    )

# -----------------------------------------------------------------------------
# 6. CHANGE DATA CAPTURE (CDC) & AUTOMATIC SCD WITH dlt.apply_changes()
# Demonstrates DLT's most powerful enterprise feature:
# Declarative SCD Type 1 (in-place overwrite) and SCD Type 2 (full history tracking)
# without writing a single line of procedural MERGE code!
# -----------------------------------------------------------------------------

# --- SCD Type 1 Table: In-place update (Current State Only) ---
dlt.create_streaming_table(
    name="silver_customer_dim_scd1",
    comment="Customer Dimension with in-place updates (SCD Type 1)",
    table_properties={"quality": "silver"}
)

dlt.apply_changes(
    target="silver_customer_dim_scd1",
    source="bronze_policies_raw",
    keys=["CustomerID"],
    sequence_by="SequenceTimestamp",
    apply_as_deletes=expr("Operation = 'DELETE'"),
    except_column_list=["Operation", "_rescued_data"],
    stored_as_scd_type="1"
)

# --- SCD Type 2 Table: Historical Tracking (__START_AT, __END_AT) ---
dlt.create_streaming_table(
    name="silver_customer_dim_scd2",
    comment="Customer Dimension with full audit history tracking (SCD Type 2)",
    table_properties={"quality": "silver"}
)

dlt.apply_changes(
    target="silver_customer_dim_scd2",
    source="bronze_policies_raw",
    keys=["CustomerID"],
    sequence_by="SequenceTimestamp",
    apply_as_deletes=expr("Operation = 'DELETE'"),
    except_column_list=["Operation", "_rescued_data"],
    stored_as_scd_type="2"
)
