resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "plan-calicot-dev-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "App"
  reserved            = false

  sku {
    tier = "Standard"
    size = "S1"
  }

  tags = {
    environment = var.environment
  }
}

resource "azurerm_app_service" "app_service" {
  name                = "app-calicot-dev-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  app_service_plan_id = azurerm_app_service_plan.app_service_plan.id

  site_config {
    always_on                 = true
    http2_enabled             = true
    min_tls_version           = "1.2"
    scm_type                  = "LocalGit"
    use_32_bit_worker_process = false

    cors {
      allowed_origins = ["*"]
    }
  }

  app_settings = {
    "ImageUrl" = "https://stcalicotprod000.blob.core.windows.net/images/"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    environment = var.environment
  }
}

resource "azurerm_monitor_autoscale_setting" "autoscale" {
  name                = "autoscale-calicot-dev-${var.id_code}"
  location            = var.location
  resource_group_name = var.resource_group_name
  target_resource_id  = azurerm_app_service.app_service.id

  profile {
    name = "defaultProfile"
    capacity {
      default = 1
      minimum = 1
      maximum = 2
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_app_service.app_service.id
        operator           = "GreaterThan"
        statistic          = "Average"
        threshold          = 70
        time_aggregation   = "Average"
        time_grain         = "PT1M"
        time_window        = "PT5M"
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT1M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_app_service.app_service.id
        operator           = "LessThan"
        statistic          = "Average"
        threshold          = 30
        time_aggregation   = "Average"
        time_grain         = "PT1M"
        time_window        = "PT5M"
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = 1
        cooldown  = "PT1M"
      }
    }
  }

  notification {
    email {
      send_to_subscription_administrator = true
      send_to_subscription_co_administrator = true
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