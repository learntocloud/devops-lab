variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "East US 2"
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}
