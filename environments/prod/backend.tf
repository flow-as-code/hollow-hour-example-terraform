# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Partial configuration: the bucket, key and Region are given at init, from
# a gitignored backend.hcl (copy backend.hcl.example) or -backend-config
# flags, so no bucket name is committed. `tofu init -backend=false` is
# enough to validate.

terraform {
  backend "s3" {}
}
