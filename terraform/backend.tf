terraform {
  # Select env/dev.backend.hcl or env/prod.backend.hcl during `terraform init`
  # so each environment uses a separate local state file.
  backend "local" {}
}
