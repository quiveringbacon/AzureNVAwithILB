# Azure NVA with ILB

This lab creates a couple of vnets peered together with an internal load balancer and a pair of Cisco ASAv's in each vnet. UDR's are added to send traffic to the opposite default subnet via the load balancer, a VM is created in each default subnet as well. You'll be prompted for the resource group name, location where you want the resources created, and username and password to use for the VM's and a subscription ID to use. This also creates a logic app that will delete the resource group in 24hrs. The topology will look something like this:

![asavwithILB](https://github.com/user-attachments/assets/b6b0c7ea-96d6-4820-b19e-652723331290)

You can run Terraform right from the Azure cloud shell by cloning this git repository with "git clone https://github.com/quiveringbacon/AzureNVAwithILB.git ./terraform". Then, "cd terraform" then, "terraform init" and finally "terraform apply -auto-approve" to deploy.
