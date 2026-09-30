# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Partial configuration, as in every environment root: the bucket, key and
# Region are given at init, so no bucket name is committed.
#
# The very first apply has no bucket to keep its state in. It runs with a
# gitignored local_override.tf that switches this root to the local
# backend; once the bucket exists, deleting that file and running
# `tofu init -migrate-state` moves the state into the bucket it created
# (README.md, "1. The state bucket").

terraform {
  backend "s3" {}
}
