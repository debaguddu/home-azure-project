# ------------------------------------------------------------------------------
# Naming Locals & Rules
# ------------------------------------------------------------------------------
locals {
  # Clean versions for storage accounts (no hyphens, lowercase only, max 24 chars)
  clean_project = lower(replace(var.project_identifier, "-", ""))
  clean_env     = lower(replace(var.environment, "-", ""))
  clean_inst    = lower(replace(var.instance, "-", ""))

  # Standard naming format: <type>-<project>-<env>-<instance>
  resource_group_name = var.resource_group_name_override != "" ? var.resource_group_name_override : "rg-${var.project_identifier}-${var.environment}-${var.instance}"

  # Storage accounts: strictly lowercase alphanumeric <= 24 chars
  # e.g. "azureprojectdevadls01" (21 chars)
  adls_name = var.adls_name_override != "" ? var.adls_name_override : "${local.clean_project}${local.clean_env}adls${local.clean_inst}"
  blob_name = var.blob_name_override != "" ? var.blob_name_override : "${local.clean_project}${local.clean_env}blob${local.clean_inst}"

  # Key Vault: alphanumeric + hyphens <= 24 chars
  # e.g. "kv-azureproject-dev-01" (21 chars)
  key_vault_name = var.key_vault_name_override != "" ? var.key_vault_name_override : "kv-${var.project_identifier}-${var.environment}-${var.instance}"

  # Azure Data Factory
  adf_name = var.adf_name_override != "" ? var.adf_name_override : "adf-${var.project_identifier}-${var.environment}-${var.instance}"

  # Azure SQL Server & Database
  sql_server_name   = var.sql_server_name_override != "" ? var.sql_server_name_override : "sql-${var.project_identifier}-${var.environment}-${var.instance}"
  sql_database_name = var.sql_database_name_override != "" ? var.sql_database_name_override : "sqldb-${var.project_identifier}-${var.environment}-${var.instance}"

  # Databricks Workspace
  databricks_name = var.databricks_name_override != "" ? var.databricks_name_override : "dbw-${var.project_identifier}-${var.environment}-${var.instance}"

  # Logic App
  logic_app_name = var.logic_app_name_override != "" ? var.logic_app_name_override : "logic-${var.project_identifier}-${var.environment}-${var.instance}"
}

# ------------------------------------------------------------------------------
# Current Azure Tenant & Client Context
# ------------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

# ------------------------------------------------------------------------------
# Resource Group
# ------------------------------------------------------------------------------
resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# ------------------------------------------------------------------------------
# 1. ADLS Gen2 (Hierarchical Namespace Enabled)
# ------------------------------------------------------------------------------
resource "azurerm_storage_account" "adls" {
  name                     = local.adls_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = true # Hierarchical Namespace
  tags                     = var.tags
}

resource "azurerm_storage_data_lake_gen2_filesystem" "adls_containers" {
  for_each           = toset(var.adls_containers)
  name               = each.key
  storage_account_id = azurerm_storage_account.adls.id
}

# ------------------------------------------------------------------------------
# 2. Blob Storage (Standard Flat Blob Storage, No Hierarchical Namespace)
# ------------------------------------------------------------------------------
resource "azurerm_storage_account" "blob" {
  name                     = local.blob_name
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  is_hns_enabled           = false # Standard Blob
  tags                     = var.tags
}

resource "azurerm_storage_container" "blob_containers" {
  for_each              = toset(var.blob_containers)
  name                  = each.key
  storage_account_name  = azurerm_storage_account.blob.name
  container_access_type = "private"
}

# ------------------------------------------------------------------------------
# 3. Azure Data Factory (ADF)
# ------------------------------------------------------------------------------
resource "azurerm_data_factory" "adf" {
  name                = local.adf_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# ------------------------------------------------------------------------------
# 4. Azure Key Vault (AKV)
# ------------------------------------------------------------------------------
resource "azurerm_key_vault" "kv" {
  name                       = local.key_vault_name
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Facilitates easy cleanup on free accounts
  tags                       = var.tags

  lifecycle {
    ignore_changes = [access_policy]
  }
}

# Store secrets in Key Vault automatically
resource "azurerm_key_vault_secret" "asql_pass" {
  name         = "asql-pass"
  value        = var.asql_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "aws_sql_pass" {
  name         = "aws-sql-pass"
  value        = var.aws_sql_password
  key_vault_id = azurerm_key_vault.kv.id
}

resource "azurerm_key_vault_secret" "sql_admin_secret" {
  name         = "sql-admin-password"
  value        = var.sql_admin_password
  key_vault_id = azurerm_key_vault.kv.id
}

# ------------------------------------------------------------------------------
# 5. Azure SQL Database (Server + Lifetime Free Offer Database)
# Free offer: 100,000 vCore-seconds, 32GB data storage, 32GB backup storage/month
# Automatically pauses when free limit is reached (AutoPause) -> $0 charge
# ------------------------------------------------------------------------------
resource "azurerm_mssql_server" "sql_server" {
  name                         = local.sql_server_name
  resource_group_name          = azurerm_resource_group.rg.name
  location                     = var.sql_location != "" ? var.sql_location : azurerm_resource_group.rg.location
  version                      = "12.0"
  administrator_login          = var.sql_admin_username
  administrator_login_password = var.sql_admin_password
  minimum_tls_version          = "1.2"
  tags                         = var.tags

  azuread_administrator {
    login_username = "hellonirupamab1991@outlook.com"
    object_id      = data.azurerm_client_config.current.object_id
    tenant_id      = data.azurerm_client_config.current.tenant_id
  }
}

# Firewall rule: Allow Azure internal services (ADF, Databricks, Logic Apps)
resource "azurerm_mssql_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_mssql_server.sql_server.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Database provisioned with Azure SQL Lifetime Free Monthly Offer
resource "azapi_resource" "sql_db" {
  type      = "Microsoft.Sql/servers/databases@2025-02-01-preview"
  name      = local.sql_database_name
  parent_id = azurerm_mssql_server.sql_server.id
  location  = azurerm_mssql_server.sql_server.location
  tags      = var.tags

  body = {
    sku = {
      name     = "GP_S_Gen5_2"
      tier     = "GeneralPurpose"
      family   = "Gen5"
      capacity = 2
    }
    properties = {
      collation                   = "SQL_Latin1_General_CP1_CI_AS"
      maxSizeBytes                = 34359738368 # 32 GB
      minCapacity                 = 0.5
      autoPauseDelay              = 60
      useFreeLimit                = true
      freeLimitExhaustionBehavior = "AutoPause"
    }
  }
}

# ------------------------------------------------------------------------------
# 6. Azure Databricks Workspace
# ------------------------------------------------------------------------------
resource "azurerm_databricks_workspace" "databricks" {
  name                = local.databricks_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = var.databricks_sku
  tags                = var.tags
}

# ------------------------------------------------------------------------------
# 7. Azure Logic Apps (Consumption Plan)
# ------------------------------------------------------------------------------
resource "azurerm_logic_app_workflow" "logic_app" {
  name                = local.logic_app_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  tags                = var.tags
}


# ==============================================================================
# Role Assignments & Access Permissions
# ==============================================================================

# 1. ADF -> ADLS Gen2 (Full read, write, execute on data lake containers)
resource "azurerm_role_assignment" "adf_to_adls" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

# 2. ADF -> Blob Storage (Full read, write on blob landing containers)
resource "azurerm_role_assignment" "adf_to_blob" {
  scope                = azurerm_storage_account.blob.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

# 3. ADF -> Azure Key Vault (Access policy to read secrets, connection strings & tokens)
resource "azurerm_key_vault_access_policy" "adf_to_kv" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_data_factory.adf.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]
}

# 4. ADF -> Azure Databricks (Contributor role to manage clusters and trigger notebook runs)
resource "azurerm_role_assignment" "adf_to_databricks" {
  scope                = azurerm_databricks_workspace.databricks.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

# 5. ADF -> Azure SQL Server (Contributor role on SQL Server)
resource "azurerm_role_assignment" "adf_to_sql" {
  scope                = azurerm_mssql_server.sql_server.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_factory.adf.identity[0].principal_id
}

# 6. Developer User -> Storage Accounts (Allows you to browse & upload files in Azure Portal)
resource "azurerm_role_assignment" "user_to_adls" {
  scope                = azurerm_storage_account.adls.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "user_to_blob" {
  scope                = azurerm_storage_account.blob.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}
