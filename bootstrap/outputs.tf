# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Every environment root's backend bucket and region. Read them with
# `tofu output -raw`; never commit them.

output "state_bucket" {
  description = "The S3 bucket every root keeps its state in."
  value       = aws_s3_bucket.state.bucket
}

output "state_region" {
  description = "The Region of that bucket: every root's backend region."
  value       = aws_s3_bucket.state.region
}
