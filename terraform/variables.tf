variable "project_name" {
  description = "Short prefix for naming Azure resources"
  type        = string
  default     = "pgha"
}

variable "environment" {
  description = "Environment identifier"
  type        = string
  default     = "prod"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralindia"
}

variable "availability_zones" {
  description = "Support zones"
  type        = list(string)
  default     = ["1", "3"]
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.40.0.0/16"]
}

variable "aks_subnet_cidr" {
  type    = string
  default = "10.40.1.0/24"
}

variable "aks_service_cidr" {
  type    = string
  default = "172.16.0.0/16"
}

variable "aks_dns_service_ip" {
  type    = string
  default = "172.16.0.10"
}

variable "kubernetes_version" {
  type    = string
  default = null
}

variable "system_node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "system_node_count" {
  type    = number
  default = 2
}

variable "pg_node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

variable "pg_node_count" {
  type    = number
  default = 3
}

variable "acr_sku" {
  type    = string
  default = "Standard"
}

variable "storage_account_tier" {
  type    = string
  default = "Standard"
}

variable "storage_replication_type" {
  type    = string
  default = "GRS"
}

variable "backup_container_name" {
  type    = string
  default = "pgbackrest-repo"
}
