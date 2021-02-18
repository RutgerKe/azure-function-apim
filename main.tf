provider "azurerm" {
    // Credentials should be set, az login is the easiest
    // other options are described here: https://www.terraform.io/docs/providers/azurerm/index.html
    version = "=2.47.0"
    features {}
}

# We use variables for repeat settings
variable "location" { default = "West Europe" }
# A name to make sure resources don't clash, we use them in naming  our
# components, as some things (like functions) need a globally unique name
variable "collectionname" { default = "someone-testing-apim" }
variable "adminemail" { default = "admin@example.com" }
variable "clientemail" { default = "client@example.com" }

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.collectionname}"
  location = var.location
}

resource "azurerm_api_management" "example" {
  name                = "apim-${var.collectionname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  publisher_name      = "PublisherName"
  publisher_email     = var.adminemail

  sku_name = "Consumption_0"
}

# Our general API definition, here we could include a nice swagger file or something
resource "azurerm_api_management_api" "example" {
  name                = "example-api"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.example.name
  revision            = "2"
  display_name        = "Example API"
  path                = "example"
  protocols           = ["https"]

  import {
    content_format = "openapi"
    content_value  = file("api-spec.yml")
  }
}

# A seperate backend definition, we need this to set our authorisation code for our azure function
resource "azurerm_api_management_backend" "example" {
  name                = "example-backend"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.example.name
  protocol            = "http"
  url                 = "https://${azurerm_function_app.func.default_hostname}/api/"

  # This depends on the existence of the named value, however terraform doesn't know this
  # so we have to define it explicitly
  depends_on          = [azurerm_api_management_named_value.example]

  credentials {
      header = {
          x-functions-key = "{{func-functionkey}}"
      }
  }
}

# To store our function code securely (so it isn't easily visible everywhere)
# we store the value as a secret 'named value'
resource "azurerm_api_management_named_value" "example" {
  name                = "func-functionkey"
  resource_group_name = azurerm_resource_group.main.name
  api_management_name = azurerm_api_management.example.name
  display_name        = "func-functionkey"
  value               = data.azurerm_function_app_host_keys.app_function_key.master_key
  secret              = true
}

# We use a policy on our API to set the backend, which has the configuration for the authentication code
resource "azurerm_api_management_api_policy" "example" {
  api_name            = azurerm_api_management_api.example.name
  api_management_name = azurerm_api_management_api.example.api_management_name
  resource_group_name = azurerm_resource_group.main.name

  # Put any policy block here, has to beh XML :(
  # More options: https://docs.microsoft.com/en-us/azure/api-management/api-management-policies
  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <set-backend-service backend-id="${azurerm_api_management_backend.example.name}" />
        </inbound>
    </policies>
  XML
}

# Below just a generic app service plan and python function setup
resource "azurerm_app_service_plan" "main" {
  name                = "asp-${var.collectionname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "functionapp"
  reserved            = true

  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_application_insights" "main" {
  name                = "aai-${var.collectionname}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  application_type    = "web"
}

resource "azurerm_storage_account" "main" {
  # we use replace to strip out the dashes, as it is not allowed in a storage account name
  name                     = "st${replace(var.collectionname, "-", "")}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_function_app" "func" {
  name                       = "fa-${var.collectionname}-func"
  resource_group_name        = azurerm_resource_group.main.name
  location                   = azurerm_resource_group.main.location
  app_service_plan_id        = azurerm_app_service_plan.main.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  os_type = "linux"
  version = "~3"
  app_settings = {
    FUNCTIONS_WORKER_RUNTIME         = "python"
    APPINSIGHTS_INSTRUMENTATIONKEY   = azurerm_application_insights.main.instrumentation_key
  }

  site_config {
    linux_fx_version = "PYTHON|3.7"
  }
}

# We use the host key in the APIM to authenticate requests
data "azurerm_function_app_host_keys" "app_function_key" {
  name                = azurerm_function_app.func.name
  resource_group_name = azurerm_resource_group.main.name
}