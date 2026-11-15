output "resource_group_name" {
  description = "Resource Group Name"
  value       = azurerm_resource_group.rg.name
}

output "adls_storage_account_name" {
  description = "ADLS Gen2 Storage Account Name (Hierarchical Namespace)"
  value       = azurerm_storage_account.adls.name
}

output "adls_containers" {
  description = "Created ADLS Gen2 Hierarchical Containers"
  value       = [for c in azurerm_storage_data_lake_gen2_filesystem.adls_containers : c.name]
}

output "blob_storage_account_name" {
  description = "Standard Blob Storage Account Name (Non-Hierarchical)"
  value       = azurerm_storage_account.blob.name
}

output "blob_containers" {
  description = "Created Blob Containers"
  value       = [for c in azurerm_storage_container.blob_containers : c.name]
}

output "data_factory_name" {
  description = "Azure Data Factory Name"
  value       = azurerm_data_factory.adf.name
}

output "key_vault_name" {
  description = "Azure Key Vault Name"
  value       = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  description = "Azure Key Vault URI"
  value       = azurerm_key_vault.kv.vault_uri
}

output "sql_server_fqdn" {
  description = "Azure SQL Server Fully Qualified Domain Name"
  value       = azurerm_mssql_server.sql_server.fully_qualified_domain_name
}

output "sql_database_name" {
  description = "Azure SQL Database Name (Lifetime Free Offer)"
  value       = azapi_resource.sql_db.name
}

output "databricks_workspace_url" {
  description = "Azure Databricks Workspace URL"
  value       = azurerm_databricks_workspace.databricks.workspace_url
}

output "logic_app_name" {
  description = "Azure Logic App Name"
  value       = azurerm_logic_app_workflow.logic_app.name
}
