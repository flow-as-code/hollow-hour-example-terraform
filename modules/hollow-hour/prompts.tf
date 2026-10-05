# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The recorded hold prompt (Tier 2, the A/B split in hh-queue-experience.tf):
# a private bucket for the audio, the committed prompts/salt-line-tips.wav as
# its one object, and the Connect prompt made from it through awscc, bound by
# every queue flow as prompt:salt-line-tips. hashicorp/aws has no prompt
# resource, so this is the module's one Cloud Control resource. The audio is
# the TypeScript-first repository's, byte for byte: synthesized once with
# Amazon Polly from prompts/salt-line-tips.txt (its tasks/README.md, tier
# decision 4; the command is in its envs/README.md, "The recorded prompt"),
# as 8 kHz 16-bit mono wav, the shape Connect recommends. Which principal
# reads the object at CreatePrompt (the resource type's handlers say the
# caller), what bucket policy that needs, and which audio format the service
# accepts are settled by the first dev apply (VERIFY.md, row P1); until then
# the bucket carries no policy, as tests/hygiene.tftest.hcl holds for every
# bucket here.
#
# The object's key carries the file's MD5, so a regenerated wav changes the
# key and with it the prompt's s3_uri: the same apply replaces the object
# (the resource address is unchanged, so the old object is deleted) and
# awscc updates the prompt in place (S3Uri is not a create-only property of
# AWS::Connect::Prompt), keeping prompt_arn and every flow binding. A fixed
# key would re-put the object and leave the prompt playing the old audio.
#
# awscc has no default_tags, so the prompt carries the two tags the aws
# provider puts on everything else (the roots' default_tags, local.flow_tags
# here) itself, as a set of {key, value} objects rather than a map;
# tests/flows.tftest.hcl holds them equal to the flows' tags.
# https://docs.aws.amazon.com/connect/latest/APIReference/API_CreatePrompt.html
# https://docs.aws.amazon.com/connect/latest/adminguide/prompts.html
# https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/connect_prompt

# Bucket names are global across AWS, so the instance alias's random suffix
# keeps hh-tf-<environment>-prompts unique, as it does the recording bucket.
resource "aws_s3_bucket" "prompts" {
  bucket = "${local.name_prefix}-prompts-${random_id.alias_suffix.hex}"

  # An environment is torn down with one plan -destroy (README.md,
  # "Teardown"); the one object here is the committed audio.
  force_destroy = true

  tags = local.tags
}

resource "aws_s3_bucket_public_access_block" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "prompts" {
  bucket = aws_s3_bucket.prompts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "salt_line_tips" {
  bucket       = aws_s3_bucket.prompts.id
  key          = "salt-line-tips-${filemd5("${path.module}/prompts/salt-line-tips.wav")}.wav"
  source       = "${path.module}/prompts/salt-line-tips.wav"
  source_hash  = filemd5("${path.module}/prompts/salt-line-tips.wav")
  content_type = "audio/wav"

  tags = local.tags

  depends_on = [
    aws_s3_bucket_public_access_block.prompts,
    aws_s3_bucket_ownership_controls.prompts,
    aws_s3_bucket_server_side_encryption_configuration.prompts,
  ]
}

resource "awscc_connect_prompt" "salt_line_tips" {
  instance_arn = aws_connect_instance.this.arn
  name         = "${local.name_prefix}-salt-line-tips"
  description  = "The recorded variant of the hold tips, for the A/B split in the queue flows."
  s3_uri       = "s3://${aws_s3_object.salt_line_tips.bucket}/${aws_s3_object.salt_line_tips.key}"
  tags         = [for key, value in local.flow_tags : { key = key, value = value }]
}
