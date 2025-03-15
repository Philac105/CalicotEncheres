output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.rg.name
}

output "vnet_id" {
  description = "ID of the created virtual network"
  value       = azurerm_virtual_network.vnet.id
}

output "vnet_name" {
  description = "Name of the created virtual network"
  value       = azurerm_virtual_network.vnet.name
}

output "web_subnet_id" {
  description = "ID of the web subnet"
  value       = azurerm_subnet.web_subnet.id
}

output "web_subnet_name" {
  description = "Name of the web subnet"
  value       = azurerm_subnet.web_subnet.name
}

output "db_subnet_id" {
  description = "ID of the database subnet"
  value       = azurerm_subnet.db_subnet.id
}

output "db_subnet_name" {
  description = "Name of the database subnet"
  value       = azurerm_subnet.db_subnet.name
}

output "web_nsg_id" {
  description = "ID of the web subnet network security group"
  value       = azurerm_network_security_group.web_nsg.id
}

output "db_nsg_id" {
  description = "ID of the database subnet network security group"
  value       = azurerm_network_security_group.db_nsg.id
}