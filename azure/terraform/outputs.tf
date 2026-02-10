output "resource_group_name" {
  value = azurerm_resouce_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "deployment_id" {
  value = random_id.deployment.hex
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}
