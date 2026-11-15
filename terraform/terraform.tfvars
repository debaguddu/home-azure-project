# ==============================================================================
# Parameter Configuration for Azure Free Tier Deployment
# ==============================================================================

# Target Azure Region
location     = "northeurope"
sql_location = "centralus" # Region where Azure SQL Server & DB are provisioned

# Project Identifier & Environment
project_identifier = "azureproject"
environment        = "dev"

# ------------------------------------------------------------------------------
# ACCOUNT SWITCHING INDEX (Option A)
# When your free account ends and you register a new one, simply increment this:
# "01" -> "02" -> "03"
# All globally unique names (ADLS, Blob, KV, SQL Server, etc.) update automatically!
# ------------------------------------------------------------------------------
instance = "01"

# ------------------------------------------------------------------------------
# Containers / Folders
# ------------------------------------------------------------------------------
# ADLS Gen2 Hierarchical containers
adls_containers = ["raw", "bronze", "silver", "gold"]

# Blob Storage containers
blob_containers = ["landing"]

# ------------------------------------------------------------------------------
# SQL Server Credentials
# Database uses Azure SQL Lifetime Free Offer (100,000 vCore-sec, 32GB storage, AutoPause)
# ------------------------------------------------------------------------------
sql_admin_username = "admin001"
sql_admin_password = "pass@2026"
asql_password      = "pass@2026"
aws_sql_password   = "Qwerty@9"

# Databricks SKU ("premium" required; Standard is deprecated by Azure Databricks. $0 base fee)
databricks_sku = "premium"

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------
tags = {
  Project     = "azureproject"
  Environment = "dev"
  ManagedBy   = "Terraform"
}

# ------------------------------------------------------------------------------
# Optional Specific Overrides (Leave commented out to use standard naming)
# ------------------------------------------------------------------------------
# resource_group_name_override = "rg-azureproject-dev-01"
# adls_name_override           = "azureprojectdevadls01"
# blob_name_override           = "azureprojectdevblob01"
# adf_name_override            = "adf-azureproject-dev-01"
# key_vault_name_override      = "kv-azureproject-dev-01"
# Server name override in centralus
sql_server_name_override = "sql-azureproject-dev-cus-01"
# sql_database_name_override   = "sqldb-azureproject-dev-01"
# databricks_name_override     = "dbw-azureproject-dev-01"
# logic_app_name_override      = "logic-azureproject-dev-01"
