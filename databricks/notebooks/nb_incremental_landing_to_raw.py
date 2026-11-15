# Databricks notebook source
# COMMAND ----------
# MAGIC %md
# MAGIC # Incremental Ingestion: Volume to External Delta Table (Unity Catalog)
# MAGIC **Framework:** Metadata-Driven Pipeline Framework  
# MAGIC **Capabilities:**  
# MAGIC 1. Reads incoming CSV data from ADLS Landing Zone using **Unity Catalog Volume** (`/Volumes/...`).
# MAGIC 2. Performs Data Quality (DQ) checks: NULL checks on mandatory columns and Duplicate checks on primary keys.
# MAGIC 3. Automatically executes **`CREATE SCHEMA IF NOT EXISTS`**.
# MAGIC 4. Automatically executes **`CREATE TABLE IF NOT EXISTS`** as an **External Delta Table** on ADLS Gen2 with schema expansion (`mergeSchema = true`).
# MAGIC 5. Computes the new maximum watermark value (`max(ModifiedDate)`) and returns status JSON back to ADF.

# COMMAND ----------
# 1. Define Input Widgets / Parameters from ADF
dbutils.widgets.text("source_table_name", "", "Source Table Name")
dbutils.widgets.text("folder_date", "", "Folder Date (YYYY/MM/DD)")
dbutils.widgets.text("volume_catalog", "landing_catalog", "Volume Catalog")
dbutils.widgets.text("volume_schema", "source_sql", "Volume Schema")
dbutils.widgets.text("volume_name", "landing_volume", "Volume Name")
dbutils.widgets.text("target_catalog", "bronze_catalog", "Target Catalog")
dbutils.widgets.text("target_schema", "raw_data", "Target Schema")
dbutils.widgets.text("landing_container", "landing", "Landing Container (Fallback)")
dbutils.widgets.text("raw_container", "raw", "Raw Container")
dbutils.widgets.text("storage_account_name", "azureprojectdevadls01", "Storage Account Name")
dbutils.widgets.text("watermark_column", "ModifiedDate", "Watermark Column")
dbutils.widgets.text("primary_keys", "", "Primary Keys (comma-separated)")
dbutils.widgets.text("mandatory_columns", "", "Mandatory Columns (comma-separated)")

source_table_name    = dbutils.widgets.get("source_table_name").strip()
folder_date          = dbutils.widgets.get("folder_date").strip()
volume_catalog       = dbutils.widgets.get("volume_catalog").strip()
volume_schema        = dbutils.widgets.get("volume_schema").strip()
volume_name          = dbutils.widgets.get("volume_name").strip()
target_catalog       = dbutils.widgets.get("target_catalog").strip()
target_schema        = dbutils.widgets.get("target_schema").strip()
landing_container    = dbutils.widgets.get("landing_container").strip()
raw_container        = dbutils.widgets.get("raw_container").strip()
storage_account_name = dbutils.widgets.get("storage_account_name").strip()
watermark_column     = dbutils.widgets.get("watermark_column").strip()
primary_keys_str     = dbutils.widgets.get("primary_keys").strip()
mandatory_columns_str= dbutils.widgets.get("mandatory_columns").strip()

print(f"Processing Source Table: {source_table_name}")
print(f"Folder Date Partition: {folder_date}")
print(f"Target Unity Catalog Table: `{target_catalog}`.`{target_schema}`.`{source_table_name}`")
print(f"Watermark Column: {watermark_column}")
print(f"Primary Keys: {primary_keys_str}")
print(f"Mandatory Columns: {mandatory_columns_str}")

# COMMAND ----------
# 2. Build Volume Source Path and External Delta Storage Path
volume_source_path = f"/Volumes/{volume_catalog}/{volume_schema}/{volume_name}/{source_table_name}/{folder_date}/*.csv"
fallback_abfss_path = f"abfss://{landing_container}@{storage_account_name}.dfs.core.windows.net/{source_table_name}/{folder_date}/*.csv"
external_delta_location = f"abfss://{raw_container}@{storage_account_name}.dfs.core.windows.net/delta/{source_table_name}"
full_table_name = f"`{target_catalog}`.`{target_schema}`.`{source_table_name}`"

print(f"Volume Source Path: {volume_source_path}")
print(f"External Delta ADLS Location: {external_delta_location}")

# COMMAND ----------
# 3. Read Incoming Data Using Volume (with ABFSS Fallback)
import json
from pyspark.sql.functions import col, current_timestamp, input_file_name, max as spark_max

df_raw = None
read_source = None

# Attempt reading via Unity Catalog Volume first
try:
    print(f"Attempting to read via Volume path: {volume_source_path}")
    df_raw = spark.read.format("csv") \
        .option("header", "true") \
        .option("inferSchema", "true") \
        .load(volume_source_path)
    read_source = "Volume"
    print("Successfully read data using Unity Catalog Volume.")
except Exception as e_vol:
    print(f"Volume read attempt failed: {str(e_vol)}. Attempting fallback to direct ABFSS URL...")
    try:
        df_raw = spark.read.format("csv") \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .load(fallback_abfss_path)
        read_source = "Direct ABFSS"
        print("Successfully read data using direct ABFSS URL.")
    except Exception as e_abfss:
        print(f"Error loading path: {str(e_abfss)}")
        output = {
            "status": "NoData",
            "table_name": source_table_name,
            "rows_processed": 0,
            "max_watermark_value": None,
            "dq_null_violations": 0,
            "dq_duplicate_violations": 0,
            "message": f"Volume error: {str(e_vol)}; ABFSS error: {str(e_abfss)}"
        }
        dbutils.notebook.exit(json.dumps(output))

row_count = df_raw.count()
print(f"Total Rows Loaded ({read_source}): {row_count}")

# COMMAND ----------
# 4. Perform Data Quality (DQ) Checks

# 4a. NULL Checks on Mandatory Columns
mandatory_cols = [c.strip() for c in mandatory_columns_str.split(",") if c.strip() and c.strip() in df_raw.columns]
null_violations = 0
dq_null_summary = {}

for col_name in mandatory_cols:
    null_cnt = df_raw.filter(col(col_name).isNull()).count()
    if null_cnt > 0:
        null_violations += null_cnt
        dq_null_summary[col_name] = null_cnt
        print(f"[DQ WARNING] Mandatory column '{col_name}' has {null_cnt} NULL value(s).")

# 4b. Duplicate Checks on Primary Keys
pk_cols = [c.strip() for c in primary_keys_str.split(",") if c.strip() and c.strip() in df_raw.columns]
duplicate_violations = 0

if pk_cols:
    total_records = df_raw.count()
    distinct_records = df_raw.select(pk_cols).distinct().count()
    duplicate_violations = total_records - distinct_records
    if duplicate_violations > 0:
        print(f"[DQ WARNING] Duplicate check on primary keys {pk_cols} revealed {duplicate_violations} duplicate record(s).")

# COMMAND ----------
# 5. Extract Maximum Watermark Value Before Write
max_watermark_val = None

if watermark_column and watermark_column in df_raw.columns:
    max_row = df_raw.select(spark_max(col(watermark_column))).collect()
    if max_row and max_row[0][0] is not None:
        max_watermark_val = str(max_row[0][0])
        print(f"Calculated New Max Watermark Value: {max_watermark_val}")
    else:
        print("Watermark column contains only null values in this batch.")
else:
    print(f"Watermark column '{watermark_column}' not found in incoming dataset.")

# COMMAND ----------
# 6. Add Audit Metadata Columns
df_transformed = df_raw \
    .withColumn("_ingested_at", current_timestamp()) \
    .withColumn("_source_file", input_file_name()) \
    .withColumn("_data_source_mode", col(watermark_column) if watermark_column in df_raw.columns else current_timestamp())

# COMMAND ----------
# 7. Create Schema If Not Exists & Create External Delta Table If Not Exists
print(f"Ensuring target schema `{target_catalog}`.`{target_schema}` exists...")
spark.sql(f"CREATE SCHEMA IF NOT EXISTS `{target_catalog}`.`{target_schema}`")

print(f"Writing to External Delta Table: {full_table_name} at {external_delta_location}...")
(df_transformed.write
    .format("delta")
    .mode("append")
    .option("mergeSchema", "true")              # Enable schema expansion
    .option("path", external_delta_location)     # External location on ADLS Gen2
    .saveAsTable(full_table_name))               # Registers External Table in Unity Catalog

print(f"Successfully appended {row_count} records into {full_table_name}.")

# COMMAND ----------
# 8. Return Status and New Watermark Value Back to ADF
output = {
    "status": "Success",
    "table_name": source_table_name,
    "rows_processed": row_count,
    "max_watermark_value": max_watermark_val,
    "dq_null_violations": null_violations,
    "dq_duplicate_violations": duplicate_violations,
    "target_table": full_table_name,
    "external_location": external_delta_location
}

dbutils.notebook.exit(json.dumps(output))
