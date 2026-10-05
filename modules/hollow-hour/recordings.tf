# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# Call recording storage: one bucket and one CALL_RECORDINGS storage config
# per instance, so the recording blocks the flows set (hh-hotline-main's
# start-recording, hh-dead-line's record-agent-only) store something. The
# TypeScript-first repository read its three instances on 2026-10-05 and
# found no storage config on any (its VERIFY.md, RS1), so T1's recording
# block had stored nothing; this is tier decision 5 (its tasks/README.md):
# SSE-S3 on the bucket and no customer managed KMS key (the storage config's
# encryption block is optional, and a customer key is a monthly charge),
# public access blocked, ACLs disabled, and a lifecycle rule that expires
# recordings after 30 days.
#
# The bucket name starts with amazon-connect-: that prefix is the only S3
# grant the instance's service-linked role carries
# (AmazonConnectServiceLinkedRolePolicy, read 2026-10-05 as v56: object
# actions under amazon-connect-*/* and GetBucketLocation and GetBucketAcl on
# amazon-connect-*), the service-linked role guide lists no inline policy for
# a recording bucket, and the module adds no bucket policy, so any other name
# would rely on undocumented behavior. The longest name this can take is 62
# characters (name_prefix is at most 16, the environment at most 12), under
# the 63 S3 allows. Whether a recording lands with this configuration is
# settled live by this tier's Close apply (VERIFY.md).
# https://docs.aws.amazon.com/connect/latest/adminguide/security_iam_awsmanpol.html#amazonconnectservicelinkedrolepolicy
# https://docs.aws.amazon.com/connect/latest/adminguide/connect-slr.html
# https://docs.aws.amazon.com/connect/latest/APIReference/API_AssociateInstanceStorageConfig.html
# https://docs.aws.amazon.com/connect/latest/adminguide/update-instance-settings.html
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/connect_instance_storage_config

resource "aws_s3_bucket" "recordings" {
  bucket = "amazon-connect-${local.name_prefix}-recordings-${random_id.alias_suffix.hex}"

  # An environment is torn down with one plan -destroy (README.md,
  # "Teardown"), and recordings expire after 30 days anyway, so the bucket
  # may go with whatever is still in it.
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    id     = "expire-recordings"
    status = "Enabled"

    filter {}

    expiration {
      days = 30
    }
  }
}

resource "aws_connect_instance_storage_config" "call_recordings" {
  instance_id   = aws_connect_instance.this.id
  resource_type = "CALL_RECORDINGS"

  storage_config {
    storage_type = "S3"

    s3_config {
      bucket_name   = aws_s3_bucket.recordings.id
      bucket_prefix = "connect/${local.instance_alias}/CallRecordings"
    }
  }

  depends_on = [aws_s3_bucket_public_access_block.recordings]
}
