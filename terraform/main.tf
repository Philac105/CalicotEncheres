resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.environment}-calicot-cc-${var.id_code}"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = var.vnet_address_space

  tags = {
    environment = var.environment
  }
}

resource "azurerm_subnet" "web_subnet" {
  name                 = "snet-${var.environment}-web-cc-${var.id_code}"
  resource_group_name  = azurerm_resource_group.rg.name
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
  resource_group_name  = azurerm_resource_group.rg.name
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
  resource_group_name = azurerm_resource_group.rg.name

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
  resource_group_name = azurerm_resource_group.rg.name

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