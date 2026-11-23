output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "storage_account_name" {
  value = azurerm_storage_account.backups.name
}

output "storage_account_primary_key" {
  value     = azurerm_storage_account.backups.primary_access_key
  sensitive = true
}

output "backup_container_name" {
  value = azurerm_storage_container.pgbackrest.name
}
