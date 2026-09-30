# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The six deterministic stub Lambdas, each zipped at plan time straight from
# lambdas/<name>/ (one dependency-free index.mjs, copied from the
# TypeScript-first repository). No build step and no Node: archive_file does
# the packaging.
#
# The flows bind lambda:<name> to the instance association's function_arn
# rather than the function's arn. The value is the same ARN, but the
# reference makes every flow that invokes a function wait for its
# association: Connect runs only functions associated with the instance.
# https://docs.aws.amazon.com/connect/latest/adminguide/connect-lambda-functions.html

locals {
  # district-for-address, plane-check and prank-score are for Tier 2: no
  # Tier 1 flow invokes them yet. They are deployed and associated now, as in
  # the TypeScript-first repository, so the functions and names are settled
  # before a flow binds them.
  lambdas = toset([
    "caller-lookup",
    "classify-apparition",
    "crew-eta",
    "district-for-address",
    "plane-check",
    "prank-score",
  ])

  # What district-for-address and crew-eta read as HH_DISTRICTS.
  districts_env = jsonencode([for d in var.districts : { slug = d.slug, name = d.name }])

  # The instance's account, for the invoke permission's source_account,
  # read from its ARN (arn:<partition>:connect:<region>:<account>:instance/<id>)
  # so a plan makes no STS call.
  account_id = split(":", aws_connect_instance.this.arn)[4]
}

data "archive_file" "lambda" {
  for_each = local.lambdas

  type        = "zip"
  source_dir  = "${path.module}/lambdas/${each.key}"
  output_path = "${path.root}/.build/${local.name_prefix}-${each.key}.zip"
  # Fixed file mode, so the zip and its hash are the same whatever the umask.
  output_file_mode = "0644"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# IAM names are global to the account, so the environment is in each name.
resource "aws_iam_role" "lambda" {
  for_each = local.lambdas

  name               = "${local.name_prefix}-${each.key}"
  description        = "Hollow Hour ${var.environment} stub Lambda ${each.key}."
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json

  tags = local.tags
}

# Created here rather than by the first invocation, so retention is set and
# a destroy removes it.
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = local.lambdas

  name              = "/aws/lambda/${local.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days

  tags = local.tags
}

# Writing to its own log group is the only permission a stub needs.
data "aws_iam_policy_document" "lambda_logs" {
  for_each = local.lambdas

  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda[each.key].arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  for_each = local.lambdas

  name   = "logs"
  role   = aws_iam_role.lambda[each.key].id
  policy = data.aws_iam_policy_document.lambda_logs[each.key].json
}

# nodejs22.x is supported until its deprecation on Apr 30, 2027.
# https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html
resource "aws_lambda_function" "stub" {
  for_each = local.lambdas

  function_name    = "${local.name_prefix}-${each.key}"
  description      = "Hollow Hour deterministic stub: ${each.key}."
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 3
  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256

  environment {
    variables = {
      HH_ENVIRONMENT = var.environment
      HH_DISTRICTS   = local.districts_env
    }
  }

  tags = local.tags

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda_logs]
}

# Connect may invoke the function from this instance only. A live apply
# showed AssociateLambdaFunction adds an equivalent statement of its own; this
# one is stated anyway, so the module does not rely on that side effect (the
# TypeScript-first repository's VERIFY.md, row L2).
resource "aws_lambda_permission" "connect" {
  for_each = local.lambdas

  statement_id   = "hollow-hour-connect"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.stub[each.key].function_name
  principal      = "connect.amazonaws.com"
  source_account = local.account_id
  source_arn     = aws_connect_instance.this.arn
}

resource "aws_connect_lambda_function_association" "stub" {
  for_each = local.lambdas

  instance_id  = aws_connect_instance.this.id
  function_arn = aws_lambda_function.stub[each.key].arn

  depends_on = [aws_lambda_permission.connect]
}
