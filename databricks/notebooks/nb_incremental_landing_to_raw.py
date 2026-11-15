# Databricks notebook source
# COMMAND ----------
# MAGIC %md
# MAGIC # Incremental Ingestion: Landing Zone to Raw Delta Table
# MAGIC **Framework:** Metadata-Driven Pipeline Framework  
# MAGIC **Purpose:**  
# MAGIC 1. Ingest incremental CSV data from ADLS Landing Zone for a specific date partition (`YYYY/MM/DD`).
# MAGIC 2. Perform Data Quality (DQ) checks (NULL checks on mandatory columns, Duplicate checks on primary keys).
# MAGIC 3. Add audit columns (`_ingested_at`, `_source_file`).
# MAGIC 4. Perform schema evolution/expansion and write to Delta table in ADLS Raw container.
# MAGIC 5. Compute the new maximum watermark value from the batch and exit back to ADF.

# COMMAND ----------
# 1. Define and Extract Input Widgets / Parameters from ADF
dbutils.widgets.text("source_table_name", "", "Source Table Name")
dbutils.widgets.text("folder_date", "", "Folder Date (YYYY/MM/DD)")
dbutils.widgets.text("landing_container", "landing", "Landing Container")
dbutils.widgets.text("raw_container", "raw", "Raw Container")
dbutils.widgets.text("storage_account_name", "azureprojectdevadls01", "Storage Account Name")
dbutils.widgets.text("watermark_column", "ModifiedDate", "Watermark Column")
dbutils.widgets.text("primary_keys", "", "Primary Keys (comma-separated)")
dbutils.widgets.text("mandatory_columns", "", "Mandatory Columns (comma-separated)")

source_table_name    = dbutils.widgets.get("source_table_name").strip()
folder_date          = dbutils.widgets.get("folder_date").strip()
landing_container    = dbutils.widgets.get("landing_container").strip()
raw_container        = dbutils.widgets.get("raw_container").strip()
storage_account_name = dbutils.widgets.get("storage_account_name").strip()
watermark_column     = dbutils.widgets.get("watermark_column").strip()
primary_keys_str     = dbutils.widgets.get("primary_keys").strip()
mandatory_columns_str= dbutils.widgets.get("mandatory_columns").strip()

print(f"Processing Table: {source_table_name}")
print(f"Folder Date: {folder_date}")
print(f"Watermark Column: {watermark_column}")
print(f"Primary Keys: {primary_keys_str}")
print(f"Mandatory Columns: {mandatory_columns_str}")

# COMMAND ----------
# 2. Build Source and Target Storage Paths
landing_path = f"abfss://{landing_container}@{storage_account_name}.dfs.core.windows.net/{source_table_name}/{folder_date}/*.csv"
raw_delta_path = f"abfss://{raw_container}@{storage_account_name}.dfs.core.windows.net/delta/{source_table_name}"

print(f"Landing Source Path: {landing_path}")
print(f"Raw Delta Target Path: {raw_delta_path}")

# COMMAND ----------
# 3. Read Incoming Data from Landing Zone
import json
from pyspark.sql.functions import col, current_timestamp, input_file_name, max as spark_max

try:
    df_raw = spark.read.format("csv") \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .load(landing_path)
    
    row_count = df_raw.count()
    print(f"Successfully loaded {row_count} rows from landing zone.")
except Exception as e:
    print(f"No files found or error loading path: {str(e)}")
    output = {
        "status": "NoData",
        "table_name": source_table_name,
        "rows_processed": 0,
        "max_watermark_value": None,
        "dq_null_violations": 0,
        "dq_duplicate_violations": 0,
        "message": str(e)
    }
    dbutils.notebook.exit(json.dumps(output))

# COMMAND ----------
# 4. Perform Data Quality (DQ) Checks

# 4a. NULL Check on Mandatory Columns
mandatory_cols = [c.strip() for c in mandatory_columns_str.split(",") if c.strip() and c.strip() in df_raw.columns]
null_violations = 0
dq_null_details = {}

for c in mandatory_cols:
    n_count = df_raw.filter(col(c).isNull()).count()
    if n_count > 0:
        null_violations += n_count
        dq_null_details[c] = n_count
        print(f"[DQ WARNING] Mandatory column '{c}' contains {n_count} NULL values.")

# 4b. Duplicate Check on Primary Keys
pk_cols = [c.strip() for c in primary_keys_str.split(",") if c.strip() and c.strip() in df_raw.columns]
duplicate_violations = 0

if pk_cols:
    total_rows = df_raw.count()
    distinct_rows = df_raw.select(pk_cols).distinct().count()
    duplicate_violations = total_rows - distinct_rows
    if duplicate_violations > 0:
        print(f"[DQ WARNING] Primary key check on {pk_cols} found {duplicate_violations} duplicate records.")

# COMMAND ----------
# 5. Extract Maximum Watermark Value Before Write
max_watermark_val = None

if watermark_column and watermark_column in df_raw.columns:
    max_row = df_raw.select(spark_max(col(watermark_column))).collect()
    if max_row and max_row[0][0] is not None:
        max_watermark_val = str(max_row[0][0])
        print(f"Calculated New Max Watermark Value: {max_watermark_val}")
    else:
        print("Watermark column is empty or contains only nulls.")
else:
    print(f"Watermark column '{watermark_column}' not found in incoming DataFrame.")

# COMMAND ----------
# 6. Add Audit Metadata Columns
df_transformed = df_raw \
    .withColumn("_ingested_at", current_timestamp()) \
    .withColumn("_source_file", input_file_name()) \
    .withColumn("_batch_date", col(watermark_column) if watermark_column in df_raw.columns else current_timestamp())

# COMMAND ----------
# 7. Write to Delta Table with Schema Evolution / Expansion
(df_transformed.write
    .format("delta")
    .mode("append")
    .option("mergeSchema", "true") # Schema expansion enabled
    .save(raw_delta_path))

print(f"Successfully appended {row_count} records to Delta table at {raw_delta_path}")

# COMMAND ----------
# 8. Return Status and Watermark Back to ADF
output = {
    "status": "Success",
    "table_name": source_table_name,
    "rows_processed": row_count,
    "max_watermark_value": max_watermark_val,
    "dq_null_violations": null_violations,
    "dq_duplicate_violations": duplicate_violations
}

dbutils.notebook.exit(json.dumps(output))
