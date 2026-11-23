resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  sa_name     = substr(replace("${var.project_name}${var.environment}${random_string.suffix.result}", "/[^a-z0-9]/", ""), 0, 24)
  acr_name    = substr(replace("${var.project_name}${var.environment}acr${random_string.suffix.result}", "/[^a-z0-9]/", ""), 0, 50)

  common_tags = {
    project     = var.project_name
    environment = var.environment
    managed_by  = "terraform"
    workload    = "postgresql-16-patroni-ha"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}-${random_string.suffix.result}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_virtual_network" "aks" {
  name                = "vnet-${local.name_prefix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "snet-aks-nodes"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.aks.name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_container_registry" "main" {
  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.acr_sku
  admin_enabled       = false
  tags                = local.common_tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${local.name_prefix}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name_prefix}-${random_string.suffix.result}"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name                        = "systempool"
    node_count                  = var.system_node_count
    vm_size                     = var.system_node_vm_size
    vnet_subnet_id              = azurerm_subnet.aks_nodes.id
    temporary_name_for_rotation = "sysrot"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    service_cidr      = var.aks_service_cidr
    dns_service_ip    = var.aks_dns_service_ip
    load_balancer_sku = "standard"
  }

  tags = local.common_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "pg_ha" {
  name                  = "pgha"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.pg_node_vm_size
  node_count            = var.pg_node_count
  vnet_subnet_id        = azurerm_subnet.aks_nodes.id
  mode                  = "User"

  node_labels = {
    workload = "postgres-ha"
  }

  tags = local.common_tags
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

resource "azurerm_storage_account" "backups" {
  name                     = local.sa_name
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled = true
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "pgbackrest" {
  name                  = var.backup_container_name
  storage_account_id    = azurerm_storage_account.backups.id
  container_access_type = "private"
}