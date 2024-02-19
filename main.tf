# variables

variable "app_name" {
  type        = string
  description = "Name of the application to create"
}

variable "contact_link" {
  type        = string
  description = "URL of the contact form"
}

variable "contact_to" {
  type        = string
  description = "JSON-encoded email address to which contact form submissions will go"
}

variable "email_domain_id" {
  type        = string
  sensitive   = true
  description = "ID of Azure Email Communication Services Domain"
}

variable "region" {
  type        = string
  sensitive   = false
  description = "Azure region for resources"
}

variable "subscription_id" {
  type        = string
  sensitive   = true
  description = "Azure subscription ID"
}

variable "tenant_id" {
  type        = string
  sensitive   = true
  description = "Azure tenant ID"
}

# terraform

terraform {
  backend "azurerm" {
    use_oidc = true
  }

  required_providers {
    azapi = {
      source  = "azure/azapi"
      version = "~> 1.12.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.91.0"
    }
  }

  required_version = ">= 1.7.0"
}

provider "azapi" {
  use_oidc = true
}

provider "azurerm" {
  features {}
  use_oidc = true
}

# resource group

resource "azurerm_resource_group" "resource_group" {
  name     = var.app_name
  location = var.region
}

resource "random_string" "resource_group" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length  = 8
  lower   = true
  numeric = false
  special = false
  upper   = false
}

# virtual network

resource "azurerm_virtual_network" "virtual_network" {
  name                = "vnet"
  resource_group_name = azurerm_resource_group.resource_group.name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.resource_group.location
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "servers" {
  name                 = "servers"
  resource_group_name  = azurerm_resource_group.resource_group.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = ["10.0.1.0/24"]
  delegation {
    name = "delegation"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# database

resource "random_password" "database_login" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length  = 8
  lower   = true
  numeric = false
  special = false
  upper   = false
}

resource "random_password" "database_password" {
  keepers = {
    database_login = random_password.database_login.result
  }
  length = 16
}

resource "azapi_resource" "mysql_server" {
  name      = "mysql-${random_string.resource_group.result}"
  parent_id = azurerm_resource_group.resource_group.id
  type      = "Microsoft.DBforMySQL/flexibleServers@2023-10-01-preview"
  location  = azurerm_resource_group.resource_group.location
  body = jsonencode({
    properties = {
      administratorLogin         = random_password.database_login.result
      administratorLoginPassword = random_password.database_password.result
      storage = {
        autoGrow      = "Enabled"
        autoIoScaling = "Enabled"
        storageSizeGB = 20
      }
      version = "8.0.21"
    }
    sku = {
      name = "Standard_B1ms"
      tier = "Burstable"
    }
  })
  response_export_values = ["*"]
}

locals {
  mysql_host = jsondecode(azapi_resource.mysql_server.output).properties.fullyQualifiedDomainName
}

resource "time_sleep" "delay_after_db_server" {
  depends_on      = [azapi_resource.mysql_server]
  create_duration = "30s"
}

resource "azapi_resource" "mysql_database" {
  name      = "strapi"
  parent_id = azapi_resource.mysql_server.id
  type      = "Microsoft.DBforMySQL/flexibleServers/databases@2023-06-30"
  body = jsonencode({
    properties = {
      charset   = "utf8mb3"
      collation = "utf8mb3_unicode_ci"
    }
  })
  depends_on = [time_sleep.delay_after_db_server]
}

resource "azurerm_private_dns_zone" "mysql_database_private_dns_zone" {
  name                = "privatelink.mysql.database.azure.com"
  resource_group_name = azurerm_resource_group.resource_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql_zone_virtual_network_link" {
  name                  = "mysql-link"
  resource_group_name   = azurerm_resource_group.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql_database_private_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.virtual_network.id
}

resource "azurerm_private_endpoint" "mysql_database_private_endpoint" {
  name                          = "${azapi_resource.mysql_server.name}-private-endpoint"
  resource_group_name           = azurerm_resource_group.resource_group.name
  location                      = azurerm_resource_group.resource_group.location
  subnet_id                     = azurerm_subnet.private_endpoints.id
  custom_network_interface_name = "${azapi_resource.mysql_server.name}-nic"
  private_service_connection {
    name                           = "${azapi_resource.mysql_server.name}-private-service-connection"
    is_manual_connection           = false
    private_connection_resource_id = azapi_resource.mysql_server.id
    subresource_names              = ["mysqlServer"]
  }
  private_dns_zone_group {
    name                 = azurerm_private_dns_zone.mysql_database_private_dns_zone.name
    private_dns_zone_ids = [azurerm_private_dns_zone.mysql_database_private_dns_zone.id]
  }
}

# storage

resource "azurerm_storage_account" "storage_account" {
  name                          = "storage${random_string.resource_group.result}"
  resource_group_name           = azurerm_resource_group.resource_group.name
  location                      = azurerm_resource_group.resource_group.location
  account_tier                  = "Standard"
  account_replication_type      = "RAGRS"
  public_network_access_enabled = false
}

resource "azurerm_private_dns_zone" "storage_account_private_dns_zone" {
  name                = "privatelink.file.core.windows.net"
  resource_group_name = azurerm_resource_group.resource_group.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_account_zone_virtual_network_link" {
  name                  = "storage-link"
  resource_group_name   = azurerm_resource_group.resource_group.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_account_private_dns_zone.name
  virtual_network_id    = azurerm_virtual_network.virtual_network.id
}

resource "azurerm_private_endpoint" "storage_account_private_endpoint" {
  name                          = "${azurerm_storage_account.storage_account.name}-private-endpoint"
  resource_group_name           = azurerm_resource_group.resource_group.name
  location                      = azurerm_resource_group.resource_group.location
  subnet_id                     = azurerm_subnet.private_endpoints.id
  custom_network_interface_name = "${azurerm_storage_account.storage_account.name}-nic"
  private_service_connection {
    name                           = "${azurerm_storage_account.storage_account.name}-private-service-connection"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_storage_account.storage_account.id
    subresource_names              = ["file"]
  }
  private_dns_zone_group {
    name                 = azurerm_private_dns_zone.storage_account_private_dns_zone.name
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_account_private_dns_zone.id]
  }
}

resource "azurerm_storage_account_network_rules" "storage_account_network_rules" {
  storage_account_id = azurerm_storage_account.storage_account.id
  default_action     = "Deny"
}

data "azapi_resource" "storage_account_file_services" {
  name      = "default"
  parent_id = azurerm_storage_account.storage_account.id
  type      = "Microsoft.Storage/storageAccounts/fileServices@2023-01-01"
}

resource "azapi_resource" "uploads_share" {
  name      = "uploads"
  parent_id = data.azapi_resource.storage_account_file_services.id
  type      = "Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01"
  body = jsonencode({
    properties = {
      accessTier       = "Hot"
      enabledProtocols = "SMB"
      shareQuota       = 5120
    }
  })
}

# email

data "azapi_resource_list" "email_usernames" {
  type                   = "Microsoft.Communication/emailServices/domains/senderUsernames@2023-06-01-preview"
  parent_id              = var.email_domain_id
  response_export_values = ["value"]
}

data "azapi_resource" "email_domain" {
  type                   = "Microsoft.Communication/emailServices/domains@2023-06-01-preview"
  resource_id            = var.email_domain_id
  response_export_values = ["properties"]
}

locals {
  email_from_user   = sensitive(jsondecode(data.azapi_resource_list.email_usernames.output).value[0].properties.username)
  email_from_domain = sensitive(jsondecode(data.azapi_resource.email_domain.output).properties.fromSenderDomain)
}

locals {
  email_from_address = sensitive("${local.email_from_user}@${local.email_from_domain}")
}

resource "azapi_resource" "communication_service" {
  name      = "communication-${random_string.resource_group.result}"
  parent_id = azurerm_resource_group.resource_group.id
  location  = "global"
  type      = "Microsoft.Communication/communicationServices@2023-06-01-preview"
  body = jsonencode({
    properties = {
      dataLocation  = "United States"
      linkedDomains = [var.email_domain_id]
    }
  })
}

resource "azapi_resource_action" "communication_service_keys" {
  type                   = "Microsoft.Communication/communicationServices@2023-06-01-preview"
  resource_id            = azapi_resource.communication_service.id
  action                 = "listKeys"
  response_export_values = ["*"]
}

locals {
  communication_service_connection_string = sensitive(jsondecode(azapi_resource_action.communication_service_keys.output).primaryConnectionString)
}

# web app

resource "azurerm_service_plan" "service_plan" {
  name                = "${azurerm_resource_group.resource_group.name}-service-plan"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  os_type             = "Linux"
  sku_name            = "B1"
  worker_count        = 1
}

resource "random_bytes" "admin_jwt_secret" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length = 8
}

resource "random_bytes" "api_token_salt" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length = 8
}

resource "random_bytes" "app_keys" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length = 8
}

resource "random_bytes" "jwt_secret" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length = 8
}

resource "random_bytes" "transfer_token_salt" {
  keepers = {
    resource_group_name = azurerm_resource_group.resource_group.name
  }
  length = 8
}

resource "azurerm_linux_web_app" "web_app" {
  name                      = var.app_name
  resource_group_name       = azurerm_resource_group.resource_group.name
  location                  = azurerm_resource_group.resource_group.location
  service_plan_id           = azurerm_service_plan.service_plan.id
  https_only                = true
  virtual_network_subnet_id = azurerm_subnet.servers.id
  site_config {
    always_on = true
    application_stack {
      node_version = "20-lts"
    }
    health_check_path                 = "/"
    health_check_eviction_time_in_min = 10
    worker_count                      = 1
    vnet_route_all_enabled            = true
  }
  storage_account {
    access_key   = azurerm_storage_account.storage_account.primary_access_key
    account_name = azurerm_storage_account.storage_account.name
    name         = azapi_resource.uploads_share.name
    share_name   = azapi_resource.uploads_share.name
    type         = "AzureFiles"
    mount_path   = "/home/site/wwwroot/public/uploads"
  }
  app_settings = {
    "ADMIN_JWT_SECRET"                        = random_bytes.admin_jwt_secret.base64
    "API_TOKEN_SALT"                          = random_bytes.api_token_salt.base64
    "APP_KEYS"                                = random_bytes.app_keys.base64
    "COMMUNICATION_SERVICE_CONNECTION_STRING" = local.communication_service_connection_string
    "CONTACT_LINK"                            = var.contact_link
    "DATABASE_CLIENT"                         = "mysql"
    "DATABASE_HOST"                           = local.mysql_host
    "DATABASE_PASSWORD"                       = random_password.database_password.result
    "DATABASE_SSL"                            = "true"
    "DATABASE_USERNAME"                       = random_password.database_login.result
    "FALLBACK_EMAIL"                          = local.email_from_address
    "JWT_SECRET"                              = random_bytes.jwt_secret.base64
    "TRANSFER_TOKEN_SALT"                     = random_bytes.transfer_token_salt.base64
    "WEBSITE_RUN_FROM_PACKAGE"                = "1"
    "CONTACT_TO"                              = var.contact_to
  }
  depends_on = [azapi_resource.mysql_server]
}

# vault / backups

resource "azurerm_recovery_services_vault" "vault" {
  name                = "vault"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  sku                 = "Standard"
}

resource "azurerm_backup_policy_file_share" "policy_file_share" {
  name                = "DailyBackup"
  resource_group_name = azurerm_resource_group.resource_group.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  backup {
    frequency = "Daily"
    time      = "12:00"
  }
  retention_daily {
    count = 30
  }
}

resource "azurerm_backup_container_storage_account" "backup_storage_account" {
  resource_group_name = azurerm_resource_group.resource_group.name
  recovery_vault_name = azurerm_recovery_services_vault.vault.name
  storage_account_id  = azurerm_storage_account.storage_account.id
}

resource "azurerm_backup_protected_file_share" "protected_file_share" {
  resource_group_name       = azurerm_resource_group.resource_group.name
  recovery_vault_name       = azurerm_recovery_services_vault.vault.name
  source_storage_account_id = azurerm_backup_container_storage_account.backup_storage_account.storage_account_id
  source_file_share_name    = azapi_resource.uploads_share.name
  backup_policy_id          = azurerm_backup_policy_file_share.policy_file_share.id
  depends_on                = [azurerm_backup_container_storage_account.backup_storage_account]
}
