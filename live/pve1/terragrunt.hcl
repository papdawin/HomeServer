skip = true

include "root" {
  path = find_in_parent_folders("root.hcl")
}

locals {
  node_config = read_terragrunt_config("${get_terragrunt_dir()}/config/node.hcl")
}

inputs = local.node_config.inputs
