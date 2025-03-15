data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "kv" {
  name                        = "kv-calicot-${var.environment}-${var.id_code}"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  
  network_acls {
    default_action = "Allow"
    bypass         = "AzureServices"
  }

  tags = {
    environment = var.environment
  }
}

resource "azurerm_key_vault_access_policy" "web_app" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_web_app.app_service.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List"
  ]
}

resource "azurerm_mssql_server" "sql_server" {
  name                         = "sqlsrv-calicot-${var.environment}-${var.id_code}"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  version                      = "12.0"
  administrator_login          = var.db_name
  administrator_login_password = var.db_password
  
  public_network_access_enabled    = false
  minimum_tls_version             = "1.2"
  
  tags = {
    environment = var.environment
  }
}

resource "azurerm_private_endpoint" "sql_endpoint" {
  name                = "pe-sql-${var.environment}-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = azurerm_subnet.db_subnet.id

  private_service_connection {
    name                           = "psc-sql-${var.environment}-${var.id_code}"
    private_connection_resource_id = azurerm_mssql_server.sql_server.id
    is_manual_connection           = false
    subresource_names              = ["sqlServer"]
  }

  tags = {
    environment = var.environment
  }
}

resource "azurerm_mssql_database" "sql_db" {
  name                = "sqldb-calicot-${var.environment}-${var.id_code}"
  server_id           = azurerm_mssql_server.sql_server.id
  collation           = "SQL_Latin1_General_CP1_CI_AS"
  sku_name            = "Basic"
  max_size_gb         = 2
  
  tags = {
    environment = var.environment
  }
}

resource "azurerm_service_plan" "app_service_plan" {
  name                = "plan-calicot-1-${var.environment}-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Windows"
  sku_name            = "S1"

  tags = {
    environment = var.environment
  }
}

resource "azurerm_windows_web_app" "app_service" {
  name                = "app-calicot-${var.environment}-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  service_plan_id     = azurerm_service_plan.app_service_plan.id

  site_config {
    always_on        = true
    ftps_state       = "Disabled"
    
    application_stack {
      current_stack  = "dotnet"
      dotnet_version = "v8.0"
    }
  }
  
  https_only = true
  
  app_settings = {
    "ImageUrl" = "https://stcalicotprod000.blob.core.windows.net/images/"
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  virtual_network_subnet_id = azurerm_subnet.web_subnet.id

  tags = {
    environment = var.environment
  }

  connection_string {
    name  = "ConnectionStrings"
    type  = "SQLAzure"
    value = "@Microsoft.KeyVault(SecretUri=https://${azurerm_key_vault.kv.name}.vault.azure.net/secrets/ConnectionStrings/)"
  }
}

resource "azurerm_monitor_autoscale_setting" "app_autoscale" {
  name                = "autoscale-${var.environment}-${var.id_code}"
  resource_group_name = var.resource_group_name
  location            = var.location
  target_resource_id  = azurerm_service_plan.app_service_plan.id

  profile {
    name = "CPU Based Autoscale"

    capacity {
      default = 1
      minimum = 1
      maximum = 2
    }

    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.app_service_plan.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
    
    rule {
      metric_trigger {
        metric_name        = "CpuPercentage"
        metric_resource_id = azurerm_service_plan.app_service_plan.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

 notification {
    email {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      custom_emails                         = []
    }
  }

  tags = {
    environment = var.environment
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.environment}-calicot-cc-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space

  tags = {
    environment = var.environment
  }
}

resource "azurerm_subnet" "web_subnet" {
  name                 = "snet-${var.environment}-web-cc-${var.id_code}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.web_subnet_address_prefix]
  service_endpoints    = ["Microsoft.Web"]

  delegation {
    name = "webapp-delegation"
    
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "db_subnet" {
  name                 = "snet-${var.environment}-db-cc-${var.id_code}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [var.db_subnet_address_prefix]
  service_endpoints    = ["Microsoft.Sql"]

  # Configure network security rules for DB subnet
  # Database subnet will be kept secure by not allowing direct internet access
}

# Network Security Group for web subnet to allow HTTP and HTTPS
resource "azurerm_network_security_group" "web_nsg" {
  name                = "nsg-${var.environment}-web-cc-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = var.environment
  }
}

# Network Security Group for DB subnet to restrict access
resource "azurerm_network_security_group" "db_nsg" {
  name                = "nsg-${var.environment}-db-cc-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name

  # Only allow traffic from web subnet to database
  security_rule {
    name                       = "AllowWebSubnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433" # SQL Server port
    source_address_prefix      = var.web_subnet_address_prefix
    destination_address_prefix = "*"
  }

  # Block all other inbound traffic
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = {
    environment = var.environment
  }
}

# Associate NSG with web subnet
resource "azurerm_subnet_network_security_group_association" "web_nsg_association" {
  subnet_id                 = azurerm_subnet.web_subnet.id
  network_security_group_id = azurerm_network_security_group.web_nsg.id
}

# Associate NSG with DB subnet
resource "azurerm_subnet_network_security_group_association" "db_nsg_association" {
  subnet_id                 = azurerm_subnet.db_subnet.id
  network_security_group_id = azurerm_network_security_group.db_nsg.id
}