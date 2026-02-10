terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "random_id" "deployment" {
  byte_length = 4
}

resource "azurerm_resouce_group" "main" {
  name     = "rg-devopslab-${random_id.deployment.hex}"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-devopslab-${random_id.deployment.hex}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resouce_group.main.location
  resource_group_name = azurerm_resouce_group.main.name
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resouce_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_container_registry" "main" {
  name                = "acrdevopslab${random_id.deployment.hex}"
  resource_group_name = azurerm_resouce_group.main.name
  location            = azurerm_resouce_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-devopslab-${random_id.deployment.hex}"
  location            = azurerm_resouce_group.main.location
  resource_group_name = azurerm_resouce_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-devopslab-${random_id.deployment.hex}"
  location            = azurerm_resouce_group.main.location
  resource_group_name = azurerm_resouce_group.main.name
  dns_prefix          = "devopslab${random_id.deployment.hex}"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_B4ms"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.0.0/16"
    dns_service_ip = "10.0.0.10"
  }
}

resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "ACRPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
