# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The one state bucket every root keeps its state in, this one included once
# migrated: versioned, encrypted, with all public access blocked and ACLs
# disabled, TLS required, and noncurrent versions expired after 90 days.
# Locking is the S3 backend's lock object (use_lockfile), so there
# is no DynamoDB table.
# https://opentofu.org/docs/language/settings/backends/s3/
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html

resource "random_id" "suffix" {
  byte_length = 3
}

resource "aws_s3_bucket" "state" {
  bucket = "${var.bucket_prefix}-${random_id.suffix.hex}"

  # Every environment's state lives here. Removing this line is a deliberate
  # step of the teardown, never a side effect of a destroy.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Refuse every request that does not arrive over TLS: state holds resource
# ids and the flows' content, and the backend always uses HTTPS anyway.
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html
data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json

  # S3 evaluates a new policy against Block Public Access; set that first.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# Versioning keeps every earlier state file. Ninety days of them is enough
# to recover from a bad apply; older noncurrent versions expire. The current
# version of each state file never does.
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-configuration-examples.html
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # A lifecycle rule on noncurrent versions needs versioning in place.
  depends_on = [aws_s3_bucket_versioning.state]
}
