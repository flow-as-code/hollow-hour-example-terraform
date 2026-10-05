# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# What the repository never contains, read from the files: no ARN in the
# module (references are resource attributes and flow tokens), no account
# id, the Apache-2.0 header on every source file, and no em-dash in the
# prose. The run plans this directory's empty root, so it needs no provider.

variables {
  repo = ".."

  # Directories that are not this repository's source: provider caches,
  # dependencies, local scratch, and the snapshot vendored byte for byte
  # from the TypeScript-first repository.
  skip = ["^\\.git/", "^\\.tofu-cache/", "^\\.tmp/", "(^|/)\\.build/", "(^|/)\\.terraform/", "(^|/)node_modules/", "^tools/equivalence/snapshot/"]
}

run "hygiene" {
  command = plan

  assert {
    condition = [
      for f in fileset(var.repo, "modules/**/{*.tf,*.mjs,*.md,*.json,*.hcl}") : f
      if alltrue([for p in var.skip : !can(regex(p, f))]) && strcontains(file("${var.repo}/${f}"), "arn:aws")
    ] == []
    error_message = "A file under modules/ holds a literal arn:aws. Bind references through refs to resource attributes, never ARNs."
  }

  # The recording bucket relies on SSE-S3 and the service-linked role's
  # amazon-connect-* grant alone (tier decision 5; recordings.tf).
  assert {
    condition = [
      for f in fileset(var.repo, "modules/**/*.tf") : f
      if alltrue([for p in var.skip : !can(regex(p, f))]) && can(regex("aws_kms_key|aws_s3_bucket_policy", file("${var.repo}/${f}")))
    ] == []
    error_message = "The module creates a KMS key or a bucket policy. The recording bucket takes SSE-S3 and no customer key, and the service-linked role's own grant covers amazon-connect-* buckets."
  }

  assert {
    condition = [
      for f in fileset(var.repo, "**/{*.tf,*.tfvars,*.tftest.hcl,*.example,*.mjs}") : f
      if alltrue([for p in var.skip : !can(regex(p, f))]) &&
      !strcontains(substr(file("${var.repo}/${f}"), 0, 300), "SPDX-License-Identifier: Apache-2.0")
    ] == []
    error_message = "A source file lacks the Apache-2.0 header (Copyright 2026 The flow-as-code Authors, SPDX-License-Identifier: Apache-2.0)."
  }

  assert {
    condition = [
      for f in fileset(var.repo, "**/{*.md,*.tf,*.tfvars,*.hcl,*.yml,*.mjs,*.example}") : f
      if alltrue([for p in var.skip : !can(regex(p, f))]) && strcontains(file("${var.repo}/${f}"), "\u2014")
    ] == []
    error_message = "A file holds an em-dash. Use a colon, a comma or two sentences."
  }

  assert {
    condition = [
      for f in fileset(var.repo, "**/{*.md,*.tf,*.tfvars,*.tftest.hcl,*.yml,*.example}") : f
      if alltrue([for p in var.skip : !can(regex(p, f))]) &&
      length([for m in regexall("(?:^|[^0-9A-Za-z])([0-9]{12})(?:[^0-9A-Za-z]|$)", file("${var.repo}/${f}")) : m if m[0] != "000000000000"]) > 0
    ] == []
    error_message = "A file holds a twelve-digit number that could be an AWS account id. Never commit one; 000000000000 is the only placeholder."
  }

  assert {
    condition = [
      for f in fileset(var.repo, "**/*.{tf,tfvars,example,md}") : f
      if alltrue([for p in var.skip : !can(regex(p, f))]) &&
      can(regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", replace(file("${var.repo}/${f}"), "00000000-0000-0000-0000-000000000000", "")))
    ] == []
    error_message = "A file holds a UUID, which could be a Connect instance id. Never commit one."
  }

  # Every action a workflow uses that leaves this repository is pinned to a
  # full commit SHA, with its version in a trailing comment.
  assert {
    condition = [
      for line in flatten([
        for f in fileset("${var.repo}/.github/workflows", "*.yml") :
        split("\n", file("${var.repo}/.github/workflows/${f}"))
      ]) : trimspace(line)
      if can(regex("^\\s*-?\\s*uses:", line)) && !can(regex("uses: [^@\\s]+@[0-9a-f]{40} # v[0-9]", line)) && !can(regex("uses: \\./", line))
    ] == []
    error_message = "A workflow uses an action that is not pinned to a full commit SHA with a # vX.Y.Z comment."
  }

  assert {
    condition     = length(fileset("${var.repo}/.github/workflows", "*.yml")) >= 2
    error_message = "The workflow pin check found no workflows to read."
  }
}
