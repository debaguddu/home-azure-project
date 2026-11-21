variable "location" {
  type        = string
  description = "Target Azure region for all resources"
  default     = "northeurope"
}

variable "sql_location" {
  type        = string
  description = "Region for Azure SQL Server & DB (defaults to centralus)"
  default     = "centralus"
}

variable "project_identifier" {
  type        = string
  description = "Project identifier name"
  default     = "azureproject"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,16}$", var.project_identifier))
    error_message = "Project identifier must be 3-16 lowercase alphanumeric characters or hyphens."
  }
}

variable "environment" {
  type        = string
  description = "Environment identifier (e.g. dev, test, prod)"
  default     = "dev"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.environment))
    error_message = "Environment must be 2-8 lowercase alphanumeric characters."
  }
}

variable "instance" {
  type        = string
  description = "Instance / version index for account switching (e.g. '01', '02', 'v01')"
  default     = "01"

  validation {
    condition     = can(regex("^[a-z0-9]{2,6}$", var.instance))
    error_message = "Instance must be 2-6 lowercase alphanumeric characters."
  }
}

# ------------------------------------------------------------------------------
# Optional Resource Name Overrides (leave empty to use standard pattern)
# ------------------------------------------------------------------------------
variable "resource_group_name_override" {
  type        = string
  description = "Optional override for Resource Group name"
  default     = ""
}

variable "adls_name_override" {
  type        = string
  description = "Optional override for ADLS Gen2 Storage Account name (must be 3-24 lowercase alphanumeric)"
  default     = ""
}

variable "blob_name_override" {
  type        = string
  description = "Optional override for Blob Storage Account name (must be 3-24 lowercase alphanumeric)"
  default     = ""
}

variable "adf_name_override" {
  type        = string
  description = "Optional override for Azure Data Factory name"
  default     = ""
}

variable "key_vault_name_override" {
  type        = string
  description = "Optional override for Key Vault name (must be 3-24 characters)"
  default     = ""
}

variable "sql_server_name_override" {
  type        = string
  description = "Optional override for SQL Server name"
  default     = ""
}

variable "sql_database_name_override" {
  type        = string
  description = "Optional override for SQL Database name"
  default     = ""
}

variable "databricks_name_override" {
  type        = string
  description = "Optional override for Databricks Workspace name"
  default     = ""
}

variable "logic_app_name_override" {
  type        = string
  description = "Optional override for Logic App name"
  default     = ""
}

# ------------------------------------------------------------------------------
# Resource Configurations
# ------------------------------------------------------------------------------
variable "adls_containers" {
  type        = list(string)
  description = "List of containers / filesystems to create in ADLS Gen2"
  default     = ["raw", "bronze", "silver", "gold"]
}

variable "blob_containers" {
  type        = list(string)
  description = "List of containers to create in Blob Storage"
  default     = ["landing"]
}

# ------------------------------------------------------------------------------
# Secrets & Credentials
# ------------------------------------------------------------------------------
variable "sql_admin_username" {
  type        = string
  description = "Admin username for the Azure SQL Server"
  default     = "admin001"
}

variable "sql_admin_password" {
  type        = string
  description = "Admin password for Azure SQL Server"
  sensitive   = true
  default     = "pass@2026"
}

variable "asql_password" {
  type        = string
  description = "Secret value for asql-pass in Key Vault"
  sensitive   = true
  default     = "pass@2026"
}

variable "aws_sql_password" {
  type        = string
  description = "Secret value for aws-sql-pass in Key Vault"
  sensitive   = true
  default     = "Qwerty@9"
}

variable "databricks_sku" {
  type        = string
  description = "SKU for Databricks workspace. 'premium' is required as Azure deprecated Standard. Workspace has $0 base hourly cost."
  default     = "premium"
}

variable "tags" {
  type        = map(string)
  description = "Common tags applied to all resources"
  default = {
    Project     = "azureproject"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
