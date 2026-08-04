# Terraform Module for VM Provisioning
## Prereq.
1. Before running terraform, your iac-controller VM should be talking to KVM host via qemu+ssh.
2. Configure ~/.ssh/config similar to below
```
Host libvirt-dev-host # this hostname should be in terraform connection string
    HostName 192.168.122.1
    User <username>
    Port <state if changed>
    IdentityFile <identity file to connect to KVM host>
    IdentitiesOnly yes
```
3. `ssh-add <identity_file>`

## How to run
1. terraform init -reconfigure -backend-config=env/dev.backend.hcl 
2. terraform plan -var-file=env/dev.tfvars
3. terraform apply -var-file=env/dev.tfvars

## Destroy
1. terraform destroy -var-file=env/dev.tfvars