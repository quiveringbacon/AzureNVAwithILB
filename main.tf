provider "azurerm" {
features {}
subscription_id = var.F-SubscriptionID
}


#variables
variable "A-location" {
    description = "Location of the resources"
    #default     = "eastus"
}

variable "B-resource_group_name" {
    description = "Name of the resource group to create"
}

variable "C-home_public_ip" {
    description = "Your home public ip address"
}

variable "D-username" {
    description = "Username for Virtual Machines"
    #default     = "azureuser"
}

variable "E-password" {
    description = "Password for Virtual Machines"
    sensitive = true
}

variable "F-SubscriptionID" {
  description = "Subscription ID to use"  
}

resource "azurerm_resource_group" "RG" {
  location = var.A-location
  name     = var.B-resource_group_name
  provisioner "local-exec" {
    command = "az vm image terms accept --urn cisco:cisco-asav:asav-azure-byol:latest"
  }
}

#logic app to self destruct resourcegroup after 24hrs
data "azurerm_subscription" "sub" {
}

resource "azurerm_logic_app_workflow" "workflow1" {
  location = azurerm_resource_group.RG.location
  name     = "labdelete"
  resource_group_name = azurerm_resource_group.RG.name
  identity {
    type = "SystemAssigned"
  }
  depends_on = [
    azurerm_resource_group.RG,
  ]
}
resource "azurerm_role_assignment" "contrib1" {
  scope = azurerm_resource_group.RG.id
  role_definition_name = "Contributor"
  principal_id  = azurerm_logic_app_workflow.workflow1.identity[0].principal_id
  depends_on = [azurerm_logic_app_workflow.workflow1]
}


resource "azurerm_resource_group_template_deployment" "apiconnections" {
  name                = "group-deploy"
  resource_group_name = azurerm_resource_group.RG.name
  deployment_mode     = "Incremental"
  template_content = <<TEMPLATE
{
    "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {},
    "variables": {},
    "resources": [
        {
            "type": "Microsoft.Web/connections",
            "apiVersion": "2016-06-01",
            "name": "arm-1",
            "location": "${azurerm_resource_group.RG.location}",
            "kind": "V1",
            "properties": {
                "displayName": "labdeleteconn1",
                "authenticatedUser": {},
                "statuses": [
                    {
                        "status": "Ready"
                    }
                ],
                "connectionState": "Enabled",
                "customParameterValues": {},
                "alternativeParameterValues": {},
                "parameterValueType": "Alternative",
                "createdTime": "2023-05-21T23:07:20.1346918Z",
                "changedTime": "2023-05-21T23:07:20.1346918Z",
                "api": {
                    "name": "arm",
                    "displayName": "Azure Resource Manager",
                    "description": "Azure Resource Manager exposes the APIs to manage all of your Azure resources.",
                    "iconUri": "https://connectoricons-prod.azureedge.net/laborbol/fixes/path-traversal/1.0.1552.2695/arm/icon.png",
                    "brandColor": "#003056",
                    "id": "/subscriptions/${data.azurerm_subscription.sub.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.RG.location}/managedApis/arm",
                    "type": "Microsoft.Web/locations/managedApis"
                },
                "testLinks": []
            }
        },
        {
            "type": "Microsoft.Logic/workflows",
            "apiVersion": "2017-07-01",
            "name": "labdelete",
            "location": "${azurerm_resource_group.RG.location}",
            "dependsOn": [
                "[resourceId('Microsoft.Web/connections', 'arm-1')]"
            ],
            "identity": {
                "type": "SystemAssigned"
            },
            "properties": {
                "state": "Enabled",
                "definition": {
                    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
                    "contentVersion": "1.0.0.0",
                    "parameters": {
                        "$connections": {
                            "defaultValue": {},
                            "type": "Object"
                        }
                    },
                    "triggers": {
                        "Recurrence": {
                            "recurrence": {
                                "frequency": "Minute",
                                "interval": 3,
                                "startTime": "${timeadd(timestamp(),"24h")}"
                            },
                            "evaluatedRecurrence": {
                                "frequency": "Minute",
                                "interval": 3,
                                "startTime": "${timeadd(timestamp(),"24h")}"
                            },
                            "type": "Recurrence"
                        }
                    },
                    "actions": {
                        "Delete_a_resource_group": {
                            "runAfter": {},
                            "type": "ApiConnection",
                            "inputs": {
                                "host": {
                                    "connection": {
                                        "name": "@parameters('$connections')['arm']['connectionId']"
                                    }
                                },
                                "method": "delete",
                                "path": "/subscriptions/@{encodeURIComponent('${data.azurerm_subscription.sub.subscription_id}')}/resourcegroups/@{encodeURIComponent('${azurerm_resource_group.RG.name}')}",
                                "queries": {
                                    "x-ms-api-version": "2016-06-01"
                                }
                            }
                        }
                    },
                    "outputs": {}
                },
                "parameters": {
                    "$connections": {
                        "value": {
                            "arm": {
                                "connectionId": "[resourceId('Microsoft.Web/connections', 'arm-1')]",
                                "connectionName": "arm-1",
                                "connectionProperties": {
                                    "authentication": {
                                        "type": "ManagedServiceIdentity"
                                    }
                                },
                                "id": "/subscriptions/${data.azurerm_subscription.sub.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.RG.location}/managedApis/arm"
                            }
                        }
                    }
                }
            }
        }
    ]
}
TEMPLATE
}
/*
resource "random_pet" "name" {
  length = 1
}
*/
#vnets and subnets
resource "azurerm_virtual_network" "vnetA" {
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "vnetA"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.0.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.hubvnetNSG.id
  }
  subnet {
    address_prefixes     = ["10.0.1.0/24"]
    name                 = "GatewaySubnet" 
  }
  subnet {
    address_prefixes     = ["10.0.2.0/24"]
    name                 = "outside"
    security_group =  azurerm_network_security_group.asasshnsg.id
  }
  subnet {
    address_prefixes     = ["10.0.3.0/24"]
    name                 = "inside" 
    #security_group = azurerm_network_security_group.asansg.id
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_virtual_network" "vnetB" {
  address_space       = ["10.250.0.0/16"]
  location            = azurerm_resource_group.RG.location
  name                = "vnetB"
  resource_group_name = azurerm_resource_group.RG.name
  subnet {
    address_prefixes     = ["10.250.0.0/24"]
    name                 = "default"
    security_group = azurerm_network_security_group.hubvnetNSG.id
  }
  subnet {
    address_prefixes     = ["10.250.1.0/24"]
    name                 = "GatewaySubnet" 
  }
  subnet {
    address_prefixes     = ["10.250.2.0/24"]
    name                 = "outside"
    security_group =  azurerm_network_security_group.asasshnsg.id
  }
  subnet {
    address_prefixes     = ["10.250.3.0/24"]
    name                 = "inside" 
    #security_group = azurerm_network_security_group.asansg.id
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_virtual_network_peering" "AtoBpeering" {
  name                      = "AtoB-peering"
  remote_virtual_network_id = azurerm_virtual_network.vnetB.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "vnetA"
  allow_forwarded_traffic = true
  allow_gateway_transit = true
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.vnetA,
    azurerm_virtual_network.vnetB
  ]
}
resource "azurerm_virtual_network_peering" "BtoApeering" {
  name                      = "BtoA-peering"
  remote_virtual_network_id = azurerm_virtual_network.vnetA.id
  resource_group_name       = azurerm_resource_group.RG.name
  virtual_network_name      = "vnetB"
  allow_forwarded_traffic = true
  allow_gateway_transit = true
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  depends_on = [
    azurerm_virtual_network.vnetA,
    azurerm_virtual_network.vnetB
  ]
}

#NSG's
resource "azurerm_network_security_group" "hubvnetNSG" {
  location            = azurerm_resource_group.RG.location
  name                = "vnet-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_security_rule" "hubvnetnsgrule1" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "3389"
  direction                   = "Inbound"
  name                        = "AllowCidrBlockRDPInbound"
  network_security_group_name = "vnet-default-nsg"
  priority                    = 2711
  protocol                    = "Tcp"
  resource_group_name         = azurerm_network_security_group.hubvnetNSG.resource_group_name
  source_address_prefix       = var.C-home_public_ip
  source_port_range           = "*"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_network_security_group" "asansg" {
  location            = azurerm_resource_group.RG.location
  name                = "onprem-asa-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_security_rule" "asansgrule1" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
  direction                   = "Inbound"
  name                        = "AllowCidrBlockInbound"
  network_security_group_name = "onprem-asa-default-nsg"
  priority                    = 2711
  protocol                    = "*"
  resource_group_name         = azurerm_network_security_group.asansg.resource_group_name
  source_address_prefix       = "192.168.0.0/24"
  source_port_range           = "*"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_security_rule" "asansgrule2" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "*"
  direction                   = "Outbound"
  name                        = "AllowCidrBlockOutbound"
  network_security_group_name = "onprem-asa-default-nsg"
  priority                    = 2712
  protocol                    = "*"
  resource_group_name         = azurerm_network_security_group.asansg.resource_group_name
  source_address_prefix       = "10.0.0.0/8"
  source_port_range           = "*"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_network_security_group" "asasshnsg" {
  location            = azurerm_resource_group.RG.location
  name                = "onprem-ssh-default-nsg"
  resource_group_name = azurerm_resource_group.RG.name
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_security_rule" "asasshnsgrule1" {
  access                      = "Allow"
  destination_address_prefix  = "*"
  destination_port_range      = "22"
  direction                   = "Inbound"
  name                        = "AllowCidrBlockSSHInbound"
  network_security_group_name = "onprem-ssh-default-nsg"
  priority                    = 100
  protocol                    = "Tcp"
  resource_group_name         = azurerm_network_security_group.asasshnsg.resource_group_name
  source_address_prefix       = var.C-home_public_ip
  source_port_range           = "*"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

#route tables
resource "azurerm_route_table" "RT-A" {
  name                          = "RT-A"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "tovnetB"
    address_prefix = "10.250.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.3.10"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "defaultsubnetA" {
  subnet_id      = azurerm_virtual_network.vnetA.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT-A.id
  timeouts {
    create = "2h"
    read = "2h"
    #update = "2h"
    delete = "2h"
  }
}
resource "azurerm_route_table" "RT-B" {
  name                          = "RT-B"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "tovnetA"
    address_prefix = "10.0.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.250.3.10"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "defaultsubnetB" {
  subnet_id      = azurerm_virtual_network.vnetB.subnet.*.id[0]
  route_table_id = azurerm_route_table.RT-B.id
  timeouts {
    create = "2h"
    read = "2h"
    #update = "2h"
    delete = "2h"
  }
}

resource "azurerm_route_table" "RT-asa-A" {
  name                          = "RT-asa-A"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "tovnetB"
    address_prefix = "10.250.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.250.3.10"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "asasubnetA" {
  subnet_id      = azurerm_virtual_network.vnetA.subnet.*.id[3]
  route_table_id = azurerm_route_table.RT-asa-A.id
  timeouts {
    create = "2h"
    read = "2h"
    #update = "2h"
    delete = "2h"
  }
}
resource "azurerm_route_table" "RT-asa-B" {
  name                          = "RT-asa-B"
  location                      = azurerm_resource_group.RG.location
  resource_group_name           = azurerm_resource_group.RG.name
  

  route {
    name           = "tovnetB"
    address_prefix = "10.0.0.0/24"
    next_hop_type  = "VirtualAppliance"
    next_hop_in_ip_address = "10.0.3.10"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
}
resource "azurerm_subnet_route_table_association" "asasubnetB" {
  subnet_id      = azurerm_virtual_network.vnetB.subnet.*.id[3]
  route_table_id = azurerm_route_table.RT-asa-B.id
  timeouts {
    create = "2h"
    read = "2h"
    #update = "2h"
    delete = "2h"
  }
}

#public ip's
resource "azurerm_public_ip" "asava1-pip" {
  name                = "asava1-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "asavb1-pip" {
  name                = "asavb1-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "asava2-pip" {
  name                = "asava2-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "asavb2-pip" {
  name                = "asavb2-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  sku = "Standard"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "vmA-pip" {
  name                = "vmA-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_public_ip" "vmB-pip" {
  name                = "vmB-pip"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  allocation_method = "Static"
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

#ILB
resource "azurerm_lb" "ilb-A" {
  name                = "ILB-A"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "frontend-ip"
    subnet_id                     = azurerm_virtual_network.vnetA.subnet.*.id[3]
    private_ip_address_allocation = "Static"
    private_ip_address = "10.0.3.10"
  }
}

resource "azurerm_lb_backend_address_pool" "ilb_poolA" {
  loadbalancer_id      = azurerm_lb.ilb-A.id
  name                 = "test-pool"  
}

resource "azurerm_lb_probe" "ilb_probeA" {  
  loadbalancer_id     = azurerm_lb.ilb-A.id
  name                = "probe1"
  port                = 443
}

resource "azurerm_lb_rule" "ilb_ruleA" {
  loadbalancer_id                = azurerm_lb.ilb-A.id
  name                           = "test-rule"
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  disable_outbound_snat          = true
  frontend_ip_configuration_name = "frontend-ip"
  probe_id                       = azurerm_lb_probe.ilb_probeA.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ilb_poolA.id]
}

resource "azurerm_lb" "ilb-B" {
  name                = "ILB-B"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                          = "frontend-ip"
    subnet_id                     = azurerm_virtual_network.vnetB.subnet.*.id[3]
    private_ip_address_allocation = "Static"
    private_ip_address = "10.250.3.10"
  }
}

resource "azurerm_lb_backend_address_pool" "ilb_poolB" {
  loadbalancer_id      = azurerm_lb.ilb-B.id
  name                 = "test-pool"  
}

resource "azurerm_lb_probe" "ilb_probeB" {  
  loadbalancer_id     = azurerm_lb.ilb-B.id
  name                = "probe1"
  port                = 443
}

resource "azurerm_lb_rule" "ilb_ruleB" {
  loadbalancer_id                = azurerm_lb.ilb-B.id
  name                           = "test-rule"
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  disable_outbound_snat          = true
  frontend_ip_configuration_name = "frontend-ip"
  probe_id                       = azurerm_lb_probe.ilb_probeB.id
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.ilb_poolB.id]
}

#vnic's
resource "azurerm_network_interface" "asainside-nic-a1" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asainside-nic-a1"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_virtual_network.vnetA.subnet.*.id[3]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "asaoutside-nic-a1" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asaoutside-nic-a1"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.asava1-pip.id
    subnet_id                     = azurerm_virtual_network.vnetA.subnet.*.id[2]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_network_interface" "asainside-nic-a2" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asainside-nic-a2"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_virtual_network.vnetA.subnet.*.id[3]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "asaoutside-nic-a2" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asaoutside-nic-a2"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.asava2-pip.id
    subnet_id                     = azurerm_virtual_network.vnetA.subnet.*.id[2]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "asainside-nic-b1" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asainside-nic-b1"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_virtual_network.vnetB.subnet.*.id[3]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "asaoutside-nic-b1" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asaoutside-nic-b1"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.asavb1-pip.id
    subnet_id                     = azurerm_virtual_network.vnetB.subnet.*.id[2]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "asainside-nic-b2" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asainside-nic-b2"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_virtual_network.vnetB.subnet.*.id[3]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "asaoutside-nic-b2" {
  ip_forwarding_enabled = true
  location            = azurerm_resource_group.RG.location
  name                = "asaoutside-nic-b2"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.asavb2-pip.id
    subnet_id                     = azurerm_virtual_network.vnetB.subnet.*.id[2]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_network_interface" "vmA-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "vmA-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vmA-pip.id
    subnet_id                     = azurerm_virtual_network.vnetA.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_network_interface" "vmB-nic" {
  location            = azurerm_resource_group.RG.location
  name                = "vmB-nic"
  resource_group_name = azurerm_resource_group.RG.name
  ip_configuration {
    name                          = "ipconfig1"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vmB-pip.id
    subnet_id                     = azurerm_virtual_network.vnetB.subnet.*.id[0]
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_network_interface_backend_address_pool_association" "nic_ilb_poolA1" {
  #count                   = 2
  network_interface_id    = azurerm_network_interface.asainside-nic-a1.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ilb_poolA.id
}
resource "azurerm_network_interface_backend_address_pool_association" "nic_ilb_poolA2" {
  #count                   = 2
  network_interface_id    = azurerm_network_interface.asainside-nic-a2.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ilb_poolA.id
}
resource "azurerm_network_interface_backend_address_pool_association" "nic_ilb_poolB1" {
  #count                   = 2
  network_interface_id    = azurerm_network_interface.asainside-nic-b1.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ilb_poolB.id
}
resource "azurerm_network_interface_backend_address_pool_association" "nic_ilb_poolB2" {
  #count                   = 2
  network_interface_id    = azurerm_network_interface.asainside-nic-b2.id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.ilb_poolB.id
}


#VM's
resource "azurerm_windows_virtual_machine" "vmA" {
  admin_password        = var.E-password
  admin_username        = var.D-username
  location              = azurerm_resource_group.RG.location
  name                  = "vmA"
  network_interface_ids = [azurerm_network_interface.vmA-nic.id]
  resource_group_name   = azurerm_resource_group.RG.name
  size                  = "Standard_B2ms"
  identity {
    type = "SystemAssigned"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    offer     = "WindowsServer"
    publisher = "MicrosoftWindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_virtual_machine_extension" "killhubvmfirewallA" {
  auto_upgrade_minor_version = true
  name                       = "killhubvmfirewallA"
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  virtual_machine_id         = azurerm_windows_virtual_machine.vmA.id
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -command \"Set-NetFirewallProfile -Enabled False\""
    }
  SETTINGS
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_windows_virtual_machine" "vmB" {
  admin_password        = var.E-password
  admin_username        = var.D-username
  location              = azurerm_resource_group.RG.location
  name                  = "vmB"
  network_interface_ids = [azurerm_network_interface.vmB-nic.id]
  resource_group_name   = azurerm_resource_group.RG.name
  size                  = "Standard_B2ms"
  identity {
    type = "SystemAssigned"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }
  source_image_reference {
    offer     = "WindowsServer"
    publisher = "MicrosoftWindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}
resource "azurerm_virtual_machine_extension" "killhubvmfirewallB" {
  auto_upgrade_minor_version = true
  name                       = "killhubvmfirewallB"
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  virtual_machine_id         = azurerm_windows_virtual_machine.vmB.id
  settings = <<SETTINGS
    {
      "commandToExecute": "powershell -command \"Set-NetFirewallProfile -Enabled False\""
    }
  SETTINGS
  timeouts {
    create = "2h"
    read = "2h"
    update = "2h"
    delete = "2h"
  }
  
}

resource "azurerm_linux_virtual_machine" "asav-a1" {
  admin_password                  = var.E-password
  admin_username                  = var.D-username
  disable_password_authentication = false
  location                        = azurerm_resource_group.RG.location
  name                            = "asa-a1"
  network_interface_ids           = [azurerm_network_interface.asaoutside-nic-a1.id,azurerm_network_interface.asainside-nic-a1.id]
  resource_group_name             = azurerm_resource_group.RG.name
  size                            = "Standard_D2_v2"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  plan {
    name      = "asav-azure-byol"
    product   = "cisco-asav"
    publisher = "cisco"
  }
  source_image_reference {
    offer     = "cisco-asav"
    publisher = "cisco"
    sku       = "asav-azure-byol"
    version   = "latest"
  }
  custom_data = base64encode(local.asa_custom_dataa1)
}

# Locals Block for custom data
locals {
asa_custom_dataa1 = <<CUSTOM_DATA
int gi0/0
no shut
nameif inside
ip address dhcp

http server enable
http 168.63.129.16 255.255.255.255 inside

route inside 10.0.0.0 255.255.0.0 10.0.3.1
route inside 168.63.129.16 255.255.255.255 10.0.3.1 2
route management 168.63.129.16 255.255.255.255 10.0.2.1 1
access-list inside permit ip any any

object network obj-any
subnet 0.0.0.0 0.0.0.0
nat (inside,management) source dynamic obj-any interface

CUSTOM_DATA  
}
resource "azurerm_linux_virtual_machine" "asav-a2" {
  admin_password                  = var.E-password
  admin_username                  = var.D-username
  disable_password_authentication = false
  location                        = azurerm_resource_group.RG.location
  name                            = "asa-a2"
  network_interface_ids           = [azurerm_network_interface.asaoutside-nic-a2.id,azurerm_network_interface.asainside-nic-a2.id]
  resource_group_name             = azurerm_resource_group.RG.name
  size                            = "Standard_D2_v2"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  plan {
    name      = "asav-azure-byol"
    product   = "cisco-asav"
    publisher = "cisco"
  }
  source_image_reference {
    offer     = "cisco-asav"
    publisher = "cisco"
    sku       = "asav-azure-byol"
    version   = "latest"
  }
  custom_data = base64encode(local.asa_custom_dataa2)
}

# Locals Block for custom data
locals {
asa_custom_dataa2 = <<CUSTOM_DATA
int gi0/0
no shut
nameif inside
ip address dhcp

http server enable
http 168.63.129.16 255.255.255.255 inside

route inside 10.0.0.0 255.255.0.0 10.0.3.1
route inside 168.63.129.16 255.255.255.255 10.0.3.1 2
route management 168.63.129.16 255.255.255.255 10.0.2.1 1
access-list inside permit ip any any

object network obj-any
subnet 0.0.0.0 0.0.0.0
nat (inside,management) source dynamic obj-any interface

CUSTOM_DATA  
}
resource "azurerm_linux_virtual_machine" "asav-b1" {
  admin_password                  = var.E-password
  admin_username                  = var.D-username
  disable_password_authentication = false
  location                        = azurerm_resource_group.RG.location
  name                            = "asa-b1"
  network_interface_ids           = [azurerm_network_interface.asaoutside-nic-b1.id,azurerm_network_interface.asainside-nic-b1.id]
  resource_group_name             = azurerm_resource_group.RG.name
  size                            = "Standard_D2_v2"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  plan {
    name      = "asav-azure-byol"
    product   = "cisco-asav"
    publisher = "cisco"
  }
  source_image_reference {
    offer     = "cisco-asav"
    publisher = "cisco"
    sku       = "asav-azure-byol"
    version   = "latest"
  }
  custom_data = base64encode(local.asa_custom_datab1)
}

# Locals Block for custom data
locals {
asa_custom_datab1 = <<CUSTOM_DATA
int gi0/0
no shut
nameif inside
ip address dhcp

http server enable
http 168.63.129.16 255.255.255.255 inside

route inside 10.250.0.0 255.255.0.0 10.250.3.1
route inside 168.63.129.16 255.255.255.255 10.250.3.1 2
route management 168.63.129.16 255.255.255.255 10.250.2.1 1
access-list inside permit ip any any

object network obj-any
subnet 0.0.0.0 0.0.0.0
nat (inside,management) source dynamic obj-any interface


CUSTOM_DATA  
}
resource "azurerm_linux_virtual_machine" "asav-b2" {
  admin_password                  = var.E-password
  admin_username                  = var.D-username
  disable_password_authentication = false
  location                        = azurerm_resource_group.RG.location
  name                            = "asa-b2"
  network_interface_ids           = [azurerm_network_interface.asaoutside-nic-b2.id,azurerm_network_interface.asainside-nic-b2.id]
  resource_group_name             = azurerm_resource_group.RG.name
  size                            = "Standard_D2_v2"
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  plan {
    name      = "asav-azure-byol"
    product   = "cisco-asav"
    publisher = "cisco"
  }
  source_image_reference {
    offer     = "cisco-asav"
    publisher = "cisco"
    sku       = "asav-azure-byol"
    version   = "latest"
  }
  custom_data = base64encode(local.asa_custom_datab2)
}

# Locals Block for custom data
locals {
asa_custom_datab2 = <<CUSTOM_DATA
int gi0/0
no shut
nameif inside
ip address dhcp

http server enable
http 168.63.129.16 255.255.255.255 inside

route inside 10.250.0.0 255.255.0.0 10.250.3.1
route inside 168.63.129.16 255.255.255.255 10.250.3.1 2
route management 168.63.129.16 255.255.255.255 10.250.2.1 1
access-list inside permit ip any any

object network obj-any
subnet 0.0.0.0 0.0.0.0
nat (inside,management) source dynamic obj-any interface

CUSTOM_DATA  
}