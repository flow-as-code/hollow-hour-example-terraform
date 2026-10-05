# Copyright 2026 The flow-as-code Authors
# SPDX-License-Identifier: Apache-2.0

# The environments differ in terraform.tfvars values and nothing else, and
# the season switch moves one binding.
#
# "files" reads the roots as files. "content" plans tests/fixtures/profiles,
# which calls the module once per profile with the values from that root's
# terraform.tfvars, with the real flowascode provider (plan only, no AWS
# call), and compares every FlowDoc across profiles. "bindings" shows what a
# profile can change besides content: the refs keys are the same in every
# profile, and the only refs value that reads the season is the hotline's
# module:greeting@live, the only one that reads the hours is each district's
# hours:<slug>. That last part is read from the module's source, because a
# mocked provider returns one value for every instance of a resource type,
# so a plan cannot tell one queue's ARN from another's.

# aws is mocked: nothing is created. The defaults are shapes the provider
# validates (a policy that parses, ARNs that parse); 000000000000 and the
# zero UUID are placeholders.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_connect_instance" {
    defaults = { arn = "arn:aws:connect:us-east-1:000000000000:instance/00000000-0000-0000-0000-000000000000" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::000000000000:role/mock" }
  }
  mock_resource "aws_lambda_function" {
    defaults = { arn = "arn:aws:lambda:us-east-1:000000000000:function:mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:us-east-1:000000000000:log-group:mock" }
  }
}

provider "flowascode" {
  region                      = "us-east-1"
  access_key                  = "offline"
  secret_key                  = "offline"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

# The module and the roots, relative to tests/, where tofu test runs.
variables {
  module = "../modules/hollow-hour"
  roots = {
    dev  = "../environments/dev"
    qa   = "../environments/qa"
    prod = "../environments/prod"
  }
}

run "files" {
  command = plan

  module {
    source = "./fixtures/profiles"
  }

  # Every .tf in the three roots is the same file.
  assert {
    condition = alltrue([
      for f in fileset(var.roots.dev, "*.tf") :
      file("${var.roots.dev}/${f}") == file("${var.roots.qa}/${f}") &&
      file("${var.roots.dev}/${f}") == file("${var.roots.prod}/${f}")
    ])
    error_message = "A .tf file differs between environments/dev, qa and prod. Only terraform.tfvars may differ."
  }

  assert {
    condition = (
      fileset(var.roots.dev, "{*.tf,*.tfvars,*.example,.terraform.lock.hcl}") == fileset(var.roots.qa, "{*.tf,*.tfvars,*.example,.terraform.lock.hcl}") &&
      fileset(var.roots.dev, "{*.tf,*.tfvars,*.example,.terraform.lock.hcl}") == fileset(var.roots.prod, "{*.tf,*.tfvars,*.example,.terraform.lock.hcl}")
    )
    error_message = "The environment roots hold different sets of files."
  }

  # Each tfvars sets exactly environment, aws_region, hours and season, once.
  assert {
    condition = alltrue([
      for env, root in var.roots :
      [
        for line in split("\n", file("${root}/terraform.tfvars")) :
        regex("^([a-z_]+)\\s*=", line)[0] if !startswith(line, "#") && trimspace(line) != ""
      ] == ["environment", "aws_region", "hours", "season"]
    ])
    error_message = "A terraform.tfvars sets something other than environment, aws_region, hours and season, in that order, once each."
  }

  assert {
    condition     = alltrue([for env, root in var.roots : output.tfvars[env].environment == env])
    error_message = "Each root's environment is its directory's name."
  }

  assert {
    condition = output.tfvars == {
      dev  = { environment = "dev", aws_region = "us-west-2", hours = "always_open", season = "standard" }
      qa   = { environment = "qa", aws_region = "us-west-2", hours = "night_shift", season = "standard" }
      prod = { environment = "prod", aws_region = "us-west-2", hours = "night_shift", season = "standard" }
    }
    error_message = "The committed profiles are all in us-west-2 (the TypeScript-first repository keeps us-east-1): dev around the clock, qa and prod on the night shift, all with the standard greeting."
  }

  assert {
    condition = alltrue([
      for env, root in var.roots :
      strcontains(file("${root}/backend.hcl.example"), "key          = \"hollow-hour-example-terraform/${env}/terraform.tfstate\"")
    ])
    error_message = "Each root's backend.hcl.example keys its state by its own environment."
  }
}

# Every profile deploys the same flow content: tfvars move bindings, never
# actions.
run "content" {
  command = plan

  module {
    source = "./fixtures/profiles"
  }

  assert {
    condition = alltrue([
      for name, docs in output.flowdocs : docs == output.flowdocs["prod"]
    ])
    error_message = "A profile's FlowDocs differ from prod's. Environment, hours and season must change bindings only."
  }

  assert {
    condition     = length(output.flowdocs["prod"]) == 18
    error_message = "Each profile deploys eighteen flows and modules."
  }
}

run "bindings" {
  command = plan

  module {
    source = "./fixtures/profiles"
  }

  # dev, qa, prod and both October variants bind the same reference keys:
  # each creates its own resources in its own instance.
  assert {
    condition = alltrue([
      for profile, flows in output.flow_refs : alltrue([
        for flow, refs in flows : keys(refs) == keys(output.flow_refs["prod"][flow])
      ])
    ])
    error_message = "A profile binds different reference keys from prod's."
  }

  # The season reaches exactly one binding: the hotline's greeting, through
  # the live alias of the chosen season.
  assert {
    condition = flatten([
      for f in sort(fileset(var.module, "*.tf")) : [
        for line in split("\n", file("${var.module}/${f}")) :
        "${f}: ${replace(trimspace(line), "/\\s+/", " ")}"
        if strcontains(line, "var.season") && !startswith(trimspace(line), "#") && f != "variables.tf"
      ]
      ]) == [
      "hh-hotline-main.flow.tf: \"module:greeting@live\" = flowascode_contact_flow_module_alias.hh_greeting_live[var.season].arn",
      "outputs.tf: value = var.season",
    ]
    error_message = "var.season is read somewhere other than the hotline's module:greeting@live binding (and the season output). The season switch must move that one binding."
  }

  # The hours reach each district's hours:<slug> binding and nothing else.
  assert {
    condition = flatten([
      for f in sort(fileset(var.module, "*.tf")) : [
        for line in split("\n", file("${var.module}/${f}")) :
        "${f}: ${replace(trimspace(line), "/\\s+/", " ")}"
        if(strcontains(line, "var.hours") || strcontains(line, "local.district_hours")) && !startswith(trimspace(line), "#") && f != "variables.tf"
      ]
      ]) == [
      "hh-district.tf: \"hours:$${each.key}\" = aws_connect_hours_of_operation.profile[local.district_hours[each.key]].arn",
      "locals.tf: district_hours = { for d in var.districts : d.slug => coalesce(d.hours, var.hours) }",
      "outputs.tf: value = local.district_hours",
    ]
    error_message = "The hours profile is read somewhere other than each district's hours:<slug> binding (and the district_hours output)."
  }

  # October is the season plus the hours: every crew moves to always_open.
  assert {
    condition = (
      output.district_hours["prod-october"] == { for slug, h in output.district_hours["prod"] : slug => "always_open" } &&
      alltrue([for slug, h in output.district_hours["prod"] : h == "night_shift"]) &&
      output.season["prod-october"] == "halloween" && output.season["prod"] == "standard"
    )
    error_message = "prod-october moves every district crew from night_shift to always_open and the greeting to halloween."
  }
}
