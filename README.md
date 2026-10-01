# Hollow Hour Example: Terraform-first

Hollow Hour Removal Co. runs a dispatch line for haunted households, built on
Amazon Connect with [flow-as-code](https://flow-as-code.dev/). The business is
invented; the engineering is not.

This repository is the **Terraform-first** approach: the entire environment,
the Connect instance included, is one Terraform module, and every flow is a
`flowascode_contact_flow` resource written as HCL. Nothing needs Node to
deploy: `tofu init`, `tofu plan`, `tofu apply`, and the AWS CLI for a few
one-off reads. For the TypeScript-first
approach, where FlowDocs and `.flow.ts` builders are the source and
`flow-cli` emits the HCL, see
[flow-as-code/hollow-hour-example-typescript](https://github.com/flow-as-code/hollow-hour-example-typescript).
The two deploy the same hotline, and CI proves it action by action
([Equivalence](#equivalence-with-the-typescript-first-repository)).

Each repository deploys greenfield on its own: its own state bucket, its own
Connect instances, nothing shared.

> Status: **live in dev, qa and prod, all in us-west-2** (2026-09-30). Each
> environment was applied greenfield from this repository, following the
> quickstart below: 63 resources per environment, the instance included, in
> one plan and one apply. qa and prod were first applied in us-east-1 and
> moved to us-west-2 the same day, by destroy and re-apply ("Picking other
> Regions or another account"). A fresh plan of each shows no changes.
> The TypeScript-first repository's keypad scenario (S2) passed against all
> three, in us-west-2, and the instance's flow logs landed in the log group
> this module creates. It is
> also checked offline on every change (fmt, validate of every root,
> `tofu test`, equivalence of content and bindings in every profile). See
> [VERIFY.md](VERIFY.md).

## The hotline

A caller hears a recording notice and the season's greeting, is asked
"Is anyone hurt?" before anything else (a yes gets the emergency-number
advice and never a ghost queue), answers a six-question keypad interview,
and is graded Faint, Restless, Manifest, Hostile or Chorus. Hostile and
Chorus go to the Lantern Crew; every other grade picks a district from the
menu (Old Town, Harborside, Graveyard Hill), whose crew answers inside its
hours, and a full crew queue overflows to the sibling district named in
`overflow_to`. The story, the rubric and the safety rules are the
TypeScript-first repository's README; the flows here are the same flows.

This is a fictional service and must never be mistaken for a real emergency
line. There is no public phone number: the environments claim none.

## Layout

```
bootstrap/               the state bucket, and nothing else
environments/
  dev/ qa/ prod/         thin roots: identical .tf files, one terraform.tfvars each
modules/hollow-hour/     the entire environment
  instance.tf            the Connect instance and its flow log group
  hours.tf queues.tf     both hours profiles; a crew queue per district, three shared
  lambdas.tf lambdas/    six stub Lambdas, zipped at plan time, associated with the instance
  hh-greeting.tf         the two greeting modules, their versions and live aliases
  hh-hotline-main.flow.tf
  hh-agent-whisper.flow.tf
  hh-customer-whisper.flow.tf
  hh-district-menu.tf    one keypad key per district
  hh-district.tf         one flow per district (for_each)
  hh-queue-experience.tf one queue flow per district (for_each)
tests/                   tofu test: flows, environments, hygiene (no AWS call)
tools/equivalence/       CI check only (Node): the flows and their bindings equal the TypeScript-first ones
.github/workflows/       ci.yml (pushes to main, pull requests), deploy.yml (dispatch: plan, then apply)
```

## How a flow reads here

Every flow is a `flowascode_contact_flow`. Its actions are HCL blocks, and
its references are plain Terraform references supplied through `refs`: an
action names a reference key (`queue:old-town-crew`), and `refs` binds that
key to the resource. There are no address maps, no refs files and no emit
step. The three district flows are one resource over `var.districts`:

```hcl
resource "flowascode_contact_flow" "hh_district" {
  for_each = local.district_flows

  instance_id = aws_connect_instance.this.id
  name        = "hh-district-${each.key}"
  type        = "CONTACT_FLOW"

  refs = {
    "hours:${each.key}"                     = aws_connect_hours_of_operation.profile[local.district_hours[each.key]].arn
    "queue:${each.key}-crew"                = aws_connect_queue.crew[each.key].arn
    "queue:${each.value.sibling.slug}-crew" = aws_connect_queue.crew[each.value.sibling.slug].arn
    # ...
  }

  action {
    id   = "set-crew-queue"
    next = "set-customer-whisper"
    update_contact_target_queue {
      queue_id = "queue:${each.key}-crew"
    }
    error {
      type = "NoMatchingError"
      next = "hand-to-dispatch"
    }
  }
  # ...
}
```

The district menu builds its prompt, its keypad conditions and its
per-district actions with `dynamic` blocks, so adding a district is one
entry in `var.districts` and the module grows a queue, two flows and a menu
key. The action ids, text and branching are the TypeScript-first
repository's, unchanged; they were written from its FlowDocs with the
pinned `flow-cli` (`codegen --to tf`) and then given real references.

Every Compare carries `next`: Amazon Connect refuses a Compare without
`Transitions.NextAction` ([VERIFY.md](VERIFY.md)), and `tests/flows.tftest.hcl`
fails on one.

## Three environments

| Environment | Region    | Crew hours                           | Greeting |
| ----------- | --------- | ------------------------------------ | -------- |
| `dev`       | us-west-2 | `always_open`, around the clock      | standard |
| `qa`        | us-west-2 | `night_shift`, 4 pm to 6 am          | standard |
| `prod`      | us-west-2 | `night_shift`, 4 pm to 6 am          | standard |

Each root under `environments/` is the same six `.tf` files and a
`terraform.tfvars` of four values. `tests/environments.tftest.hcl` holds
that: the `.tf` files are byte-identical, each tfvars sets exactly
`environment`, `aws_region`, `hours` and `season`, and every profile deploys
the same FlowDocs.

```hcl
# environments/prod/terraform.tfvars
environment = "prod"
aws_region  = "us-west-2"
hours       = "night_shift"
season      = "standard"
```

Queues hold two contacts outside prod and 25 in prod, so an operator can
fill a dev or qa queue with two test calls and hear the overflow path
(`queue_max_contacts` in the module).

### The season

October is prod with two lines changed in `environments/prod/terraform.tfvars`:

```diff
-hours       = "night_shift"
-season      = "standard"
+hours       = "always_open"
+season      = "halloween"
```

Both greetings are always deployed, each behind its own `live` alias.
`season` chooses which alias the hotline's `module:greeting@live` binds, and
`hours` which profile each crew's `hours:<slug>` binds. No flow's actions
change: the plan updates, in place, the `refs` of the hotline and of the
three district flows and the content derived from them (each flow's
resolved `content` and its hash), and nothing else. Rolling back is
reverting the commit. `tests/environments.tftest.hcl` holds that the season reaches exactly
one binding and the hours exactly one per district.

## Quickstart, from zero

You need:

- OpenTofu 1.10 or later. CI tests 1.10 and the latest release. Terraform
  1.11 or later (the first release where the S3 backend's lock file is out
  of experiment) should work with the same commands, but is untested here.
  The committed lock files hold `registry.opentofu.org` entries only, so
  with Terraform run `terraform providers lock` for your platforms first
  (CONTRIBUTING.md, "Provider locks").
- The AWS CLI (v2), for the quota reads below and a few one-off steps.
- AWS credentials for the account you deploy to.

Node is not needed. Every command below runs from the repository root.

Check the Connect instance quota first. The default is two instances per
account and Region (`L-AA17A6B9`), and each environment creates one, all
three in us-west-2, so this repository alone needs a quota of at least 3
there, plus any instances the account already has in that Region. The
TypeScript-first repository keeps its three in us-east-1, so the two never
share a Region and can share an account without counting against each
other. The maintainers' account read 5 in both Regions on 2026-09-30, after
an increase approved that day ([VERIFY.md](VERIFY.md), T6). Read the quota
and the instances already there, and if the quota is short, ask for more;
a larger increase "can take up to 3 weeks":

```sh
aws service-quotas get-service-quota --service-code connect \
  --quota-code L-AA17A6B9 --region us-west-2
aws connect list-instances --region us-west-2 --query 'length(InstanceSummaryList)'
aws service-quotas request-service-quota-increase --service-code connect \
  --quota-code L-AA17A6B9 --desired-value <existing + 3> --region us-west-2
```

### 1. The state bucket

`bootstrap/` creates one S3 bucket for every root's state: versioned,
encrypted, public access blocked, `prevent_destroy`, locked by the S3
backend's lock object (`use_lockfile`, no DynamoDB table). Its first apply
has no bucket to keep state in, so it runs on local state and then moves
that state into the bucket it created.

The bucket's Region is `state_region` (default `us-east-1`). To use
another, write it to `bootstrap/terraform.tfvars` before the first plan.
That file is gitignored (`.gitignore` commits only
`environments/*/terraform.tfvars`), and every later plan of `bootstrap/`
reads it, so the Region cannot be forgotten on one run; a plan with a
different Region would look for the bucket there and plan a new one.

```sh
printf 'state_region = "us-east-1"\n' > bootstrap/terraform.tfvars      # optional
printf 'terraform {\n  backend "local" {}\n}\n' > bootstrap/local_override.tf
tofu -chdir=bootstrap init
tofu -chdir=bootstrap plan -out=bootstrap.tfplan
tofu -chdir=bootstrap apply bootstrap.tfplan

cp bootstrap/backend.hcl.example bootstrap/backend.hcl
# set bucket to: tofu -chdir=bootstrap output -raw state_bucket
# set region to the bucket's Region
rm bootstrap/local_override.tf
tofu -chdir=bootstrap init -migrate-state -force-copy -backend-config=backend.hcl
tofu -chdir=bootstrap state list        # now read from the bucket
rm -f bootstrap/terraform.tfstate bootstrap/terraform.tfstate.backup
```

With `-chdir`, `-backend-config=backend.hcl` and `-out=` are relative to
that directory. `local_override.tf`, `backend.hcl`, `terraform.tfvars`
there and the state files are gitignored. Keep the bucket name somewhere
other than this state (a GitHub secret, a password manager): a fresh clone
cannot read it back from `tofu output`.

### 2. Each environment

The same four commands per environment. The first apply creates the
instance (a few minutes; the provider waits until it is ACTIVE) and then
its 62 other resources.

```sh
cp environments/dev/backend.hcl.example environments/dev/backend.hcl
# set bucket, and region if the bucket is not in us-east-1
tofu -chdir=environments/dev init -backend-config=backend.hcl
tofu -chdir=environments/dev plan -out=dev.tfplan
tofu -chdir=environments/dev apply dev.tfplan
```

Then `environments/qa`, then `environments/prod`, one at a time: the
Connect API throttle is shared by everything in an account and Region, and
creating two instances at once in one Region can be refused while the
first is pending (below). Always apply the saved plan you read, never
`apply -auto-approve`.

After the first apply, check the new instance's concurrent-calls quota
(below). Nothing here claims a phone number, so exercise the flows from
the Connect admin website: sign in at `https://<alias>.my.connect.aws/`
(`tofu -chdir=environments/dev output -raw instance_alias`), find the
`hh-*` flows under Routing, Flows, and run them with the website's test
cases and simulation
([Amazon Connect guide](https://docs.aws.amazon.com/connect/latest/adminguide/testing-simulation-execute-test-cases.html)).
`flow-cli simulate`, which the TypeScript-first repository uses, can run
the same kind of test from a terminal. It is optional: it needs Node, and a
resource map from each reference key to its ARN, which this repository does
not produce (that repository builds its own from state).

### Picking other Regions or another account

- The Region is `aws_region` in each environment's `terraform.tfvars`.
  Everything the environment creates lives there. Amazon Connect is not in
  every Region; see the
  [Regions list](https://docs.aws.amazon.com/connect/latest/adminguide/regions.html).
- The state bucket's Region is `state_region`, set in the gitignored
  `bootstrap/terraform.tfvars` (above), and then `region` in every
  `backend.hcl`, the bootstrap root's included. It need not match any
  environment's.
- The account is whichever your credentials reach. Another account needs
  its own bootstrap (its own bucket) and its own `backend.hcl` files. No
  account id, instance id or bucket name is written in a tracked file; the
  instance alias and the bucket name carry random suffixes, so two copies
  never collide.
- Resource names start `hh-tf-<environment>-` (`name_prefix` in the
  module), so this repository and the TypeScript-first one (`hh-<environment>-`)
  can share an account: IAM role names are global to it.
- Changing `aws_region` on a deployed environment does not move it: the
  providers look for its resources in the new Region, find none, and plan
  new ones, while the old ones stay behind, unmanaged. Move it by destroy
  and re-apply, in this order, with the tfvars still naming the old Region
  for the first two steps:

  ```sh
  tofu -chdir=environments/qa plan -destroy -out=destroy.tfplan
  tofu -chdir=environments/qa apply destroy.tfplan
  # now set aws_region in environments/qa/terraform.tfvars
  tofu -chdir=environments/qa plan -out=qa.tfplan
  tofu -chdir=environments/qa apply qa.tfplan
  ```

  The state stays in the same bucket and key; only the resources move.
  The new instance gets a new alias suffix, a new ARN and new flow ids, so
  read its concurrent-calls quota again (below), and rebuild anything
  keyed on the old ARNs, such as a simulate resource map. Observed on
  2026-09-30, moving qa and prod from us-east-1 to us-west-2: each destroy
  removed 63 resources, each apply added 63, a fresh plan of dev, qa and
  prod then reported no changes, and scenario S2 passed on both
  ([VERIFY.md](VERIFY.md), T8). Check the new Region's instance quota
  first.
- Never let a plan replace the instance. The greeting module versions are
  `create_before_destroy` (a new version must exist before the old one
  goes), and Terraform and OpenTofu extend that to everything a version
  depends on, the instance included. A change that replaces the instance
  would create the new one first, under the same alias, which Connect
  refuses because an alias is unique. Destroy first instead.

## Known service behaviors

Checked live by the TypeScript-first repository; its
[VERIFY.md](https://github.com/flow-as-code/hollow-hour-example-typescript/blob/main/VERIFY.md)
has the evidence, dates and AWS documentation for each. Summarized:

- **A Compare needs `next`** (row C1). Connect refuses a Compare without
  `Transitions.NextAction`: "Action is missing required property. Path:
  Actions[0].Transitions.NextAction". Every Compare here sets `next` to its
  NoMatchingCondition target.
- **Hours cannot wrap midnight** (rows H1, H2). 0:00 to 0:00 is accepted as
  around the clock; a 16:00 to 6:00 range is refused ("Start time: 16:0
  cannot be greater than end time: 6:0"), so `night_shift` is two ranges a
  day, 0:00 to 6:00 and 16:00 to 0:00.
- **Instance count per Region** (row H3). The default quota is 2 per account
  and Region (`L-AA17A6B9`), adjustable; a larger increase "can take up to 3
  weeks". This repository keeps all three environments in us-west-2 and
  needs at least 3 there; the Quickstart has the reads and the request.
- **A pending create can be refused.** Creating an instance while another is
  still being created in the same Region was refused once with
  `ServiceQuotaExceededException: Currently pending instance creation
  requests, if successfully executed, will reach instance count quota`,
  although the Region was under quota. Wait until the other is ACTIVE, plan
  again and apply again; nothing else in the apply is affected.
- **A new instance may allow 0 concurrent calls** (row S2). "Concurrent
  active calls per instance" (`L-12AB7C57`) is an instance-level quota whose
  documented default is 10, but one of the TypeScript-first repository's
  new instances read 0, and test runs on it failed to start with "limit
  reached". That the 0 caused the refusal is inferred, not confirmed: the
  two instances that read 10 ran the same test, and no run has followed an
  increase yet. Read it for each new instance, by its ARN (never
  committed), and if it is 0, ask for the default and follow the request:

  ```sh
  arn="$(tofu -chdir=environments/qa output -raw instance_arn)"
  aws service-quotas get-service-quota --service-code connect \
    --quota-code L-12AB7C57 --context-id "$arn" --region <region>
  aws service-quotas request-service-quota-increase --service-code connect \
    --quota-code L-12AB7C57 --context-id "$arn" --desired-value 10 --region <region>
  aws service-quotas list-requested-service-quota-change-history-by-quota \
    --service-code connect --quota-code L-12AB7C57 \
    --quota-requested-at-level RESOURCE --region <region>
  ```

  The request may become a support case rather than apply at once. An
  instance-level request is recorded at the resource level: without
  `--quota-requested-at-level RESOURCE` the history reads empty.
- **The API throttle is shared** (row H3): 2 requests per second, burst 5,
  across every instance in the account and Region. Deploy one environment
  at a time.
- **Associating a Lambda grants Connect invoke permission** (row L2); the
  module states its own `aws_lambda_permission` anyway, so it does not rely
  on that.
- **Flow logs go to `/aws/connect/<alias>`**, which Connect creates and
  which keeps logs forever by default (row H4). Here the module creates that
  group before the instance, with a 14-day retention, so a destroy removes
  it after the instance ([VERIFY.md](VERIFY.md), T1: whether Connect
  reuses a group that exists is still to be seen live; the fallback is
  below).

### If Connect refuses the log group

If the first apply shows Connect refusing, or not using, a log group that
already exists (VERIFY.md, T1), set `manage_flow_log_group = false` in the
module block of every root's `main.tf` (the roots stay identical). The
module then creates no flow log group: Connect creates its own, and you set
its retention once, with the AWS CLI, after the first apply:

```sh
alias="$(tofu -chdir=environments/dev output -raw instance_alias)"
aws logs put-retention-policy --region us-west-2 \
  --log-group-name "/aws/connect/$alias" --retention-in-days 14
```

If the group is not there yet, Connect has not written a flow log; run the
command again after the first test call. A destroy then leaves the group
behind: delete it with `aws logs delete-log-group` after the environment's
teardown.


## Deploying from GitHub

`.github/workflows/deploy.yml`, dispatched by hand for one environment, runs
two jobs. `plan` initializes the backend, runs `plan -out`, and writes the
plan to the run's summary; it has no approval gate, so the plan is there
before anyone approves anything. `apply` runs only when the dispatch checks
`apply`: it waits for the environment's required reviewer (prod), downloads
the exact plan the `plan` job saved, and applies it. One deploy runs at a
time across all three environments (one concurrency group, never
cancelled): dev, qa and prod share us-west-2's Connect API throttle, and a
second instance create while one is pending can be refused.

### Setting it up

1. **Environments.** In the repository's settings, create six GitHub
   environments: `dev`, `qa` and `prod` for the apply job, and
   `dev-plan`, `qa-plan` and `prod-plan` for the plan job. On every one,
   limit deployment branches to `main`. On `prod`, add a required reviewer
   (and "Prevent self-review" when more than one person can approve). The
   `-plan` environments get no reviewer; they exist so the plan job can
   read its own secrets, which GitHub scopes to an environment.
2. **Roles.** Create IAM roles that trust GitHub's OIDC provider
   ([GitHub's guide](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services)),
   each for the subjects of its environments,
   `repo:<owner>/<repository>:environment:<name>`:
   - a **plan role** for `dev-plan`, `qa-plan` and `prod-plan`, read-only:
     reading what the module manages (the AWS managed policy
     `ReadOnlyAccess` covers it), reading the state objects under
     `hollow-hour-example-terraform/` in the bucket, and writing and
     deleting their `.tflock` lock objects, which a plan takes;
   - a **deploy role** for `dev`, `qa` and `prod` (or one per
     environment), with the permissions below.
3. **Secrets and variables.**

   | Where                          | Kind     | Name                  | Value                                                                                   |
   | ------------------------------ | -------- | --------------------- | --------------------------------------------------------------------------------------- |
   | repository                     | secret   | `PLAN_ARTIFACT_KEY`   | a random passphrase (`openssl rand -base64 32`); encrypts the saved plan between jobs   |
   | `dev-plan`, `qa-plan`, `prod-plan` | secret | `AWS_PLAN_ROLE_ARN` | the plan role's ARN                                                                     |
   | `dev`, `qa`, `prod`            | secret   | `AWS_DEPLOY_ROLE_ARN` | the deploy role's ARN                                                                   |
   | all six environments           | secret   | `TF_STATE_BUCKET`     | the bucket `bootstrap/` created                                                         |
   | all six environments           | variable | `TF_STATE_REGION`     | that bucket's Region                                                                    |

   The role ARNs and the bucket are secrets, not variables, because GitHub
   prints each step's `with:` and `env:` values in the log before any
   `add-mask` can run, and masks only secrets there. The Region is not
   sensitive.

The saved plan holds state values (ids, ARNs, the account id), and anyone
can download a public repository's artifacts, so it travels between the
jobs encrypted with `PLAN_ARTIFACT_KEY` and is kept for one day. The logs
and the summary mask the account id, redact every UUID, and mask the
instance alias once state holds it; the apply log stops before the outputs.

The deploy role needs what the TypeScript-first repository's deploy role
needs (its `envs/README.md`, "The deploy role": state, queues and hours,
flows and modules, Lambda association, Lambdas, their roles and log
groups), scoped to `hh-tf-<environment>-*` names, plus what this module
adds: creating, describing, updating and deleting the Connect instance
(the directory and service-linked role Connect creates with it included)
and the `/aws/connect/<alias>` log group. [VERIFY.md](VERIFY.md), T4,
records that the exact instance actions are still to be confirmed by a
live apply.

## Opening the flows in flow-cli and the studio (optional)

Not needed to deploy. This needs Node 22.12 or later.

The three flows that are one resource each, `hh-hotline-main.flow.tf`,
`hh-agent-whisper.flow.tf` and `hh-customer-whisper.flow.tf`, are in the
shape flow-cli reads: `flow-cli synth` turns each into a FlowDoc, and
`flow-cli studio` opens it.

The flows that iterate (`hh-district.tf`, `hh-queue-experience.tf`,
`hh-district-menu.tf` and the greetings) use `for_each` or `dynamic`, which
flow-cli's reader refuses by design, because it reads a file without
evaluating it. Their documents come from the provider instead: every
`flowascode_contact_flow` computes its `flowdoc` at plan time. The
equivalence check can write prod's out for the CLI or the studio, from the
repository root:

```sh
npm --prefix tools/equivalence ci
node tools/equivalence/check.mjs --write .tmp/flowdocs
npx @flow-as-code/cli@0.2.1 lint .tmp/flowdocs
npx @flow-as-code/cli@0.2.1 studio .tmp/flowdocs
```

That view is for reading. An edit in the studio does not flow back into
the module; make it in the HCL.

## Checks

| Command                                                      | What it holds                                                                                                                                                                                                          |
| ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tofu fmt -check -recursive`                                 | formatting                                                                                                                                                                                                             |
| `tofu -chdir=<root> init -backend=false && tofu -chdir=<root> validate` | every root: `bootstrap`, the three environments, `tools/equivalence/harness`                                                                                                                                |
| `tofu -chdir=tests init -test-directory=.` then `tofu -chdir=tests test -test-directory=.` | `flows`: every Compare has `next`, every reference is bound and every binding used, no ARN in a flow, a queue and two flows and a menu key per district, the variable validations. `environments`: the roots differ only in tfvars values, every profile deploys the same FlowDocs, the season moves one binding. `hygiene`: no `arn:aws` in `modules/`, no account or instance id, license headers, no em-dash, pinned actions |
| `npm --prefix tools/equivalence ci && node tools/equivalence/check.mjs` | in dev, qa, prod and prod-october: the flows equal the TypeScript-first repository's, action by action, and each reference is bound to the resource that repository binds it to                                  |

No check makes an AWS call. The tests mock `aws`, and the flowascode
provider only plans, which computes the FlowDoc without calling Connect.
`ci.yml` runs on pushes to `main` and on pull requests: fmt and validate
with OpenTofu 1.10 and with the latest release, and `tofu test` and the
equivalence check with 1.10.

### Equivalence with the TypeScript-first repository

`tools/equivalence/` is a CI check, not a deploy step, and the one place
Node is used. For each deploy profile (dev, qa, prod and prod-october) it
plans the module offline and checks two things against files vendored
from the TypeScript-first repository (`tools/equivalence/snapshot/`, source
commit in `SOURCE.md`):

- **Content.** Each flow's FlowDoc, read from the plan, equals the FlowDoc
  of the same name there: the same twelve names, and per document the
  same type, start action, reference tokens and every action's id, type,
  parameters and transitions, in order.
- **Bindings.** Each reference is bound to the resource that repository
  binds it to in the same profile (its `refs/<profile>.tfmap.json`), read
  by name: a flow bound to the wrong queue, Lambda or greeting fails,
  although its tokens match.

The three `.flow.tf` files are also read by `@flow-as-code/hcl`, the reader
flow-cli uses, and must give the same documents. On 2026-09-30: 12 flows
and modules, 195 actions and 44 bindings per profile, identical.

Equivalence covers flow content and bindings, not descriptions. The
deployed descriptions differ from the TypeScript-first repository's on
purpose: some of theirs (the generated district and queue flows) name the
generator that wrote them.

## Cost

Amazon Connect charges for usage (per-minute voice and similar), not for
an idle instance, at the time of writing; claiming a phone number adds a
daily charge, and nothing here claims one. An idle environment costs little
beyond CloudWatch Logs storage and the state bucket, and the Lambdas cost
nothing until called. Check
[Amazon Connect pricing](https://aws.amazon.com/connect/pricing/) for your
Region before you rely on that.

## Teardown

In this order, from the repository root; each step needs the one before it
to have finished.

1. Each environment, with the same `backend.hcl` as its apply:

   ```sh
   tofu -chdir=environments/prod init -backend-config=backend.hcl
   tofu -chdir=environments/prod plan -destroy -out=destroy.tfplan
   tofu -chdir=environments/prod apply destroy.tfplan
   ```

   This removes the flows and modules, the Lambdas and their roles and log
   groups, the queues and hours, the instance, and then its flow log group
   (with `manage_flow_log_group = false`, delete that group yourself; see
   "If Connect refuses the log group"). Repeat for qa and dev.

2. The state bucket. `prevent_destroy` refuses any plan that deletes it,
   and it is versioned, so move the bootstrap state out of it first:

   ```sh
   tofu -chdir=bootstrap init -backend-config=backend.hcl   # a fresh clone: attach the bucket first
   bucket="$(tofu -chdir=bootstrap output -raw state_bucket)"
   printf 'terraform {\n  backend "local" {}\n}\n' > bootstrap/local_override.tf
   tofu -chdir=bootstrap init -migrate-state -force-copy
   ```

   Empty the bucket of every object version and delete marker (the
   console's "Empty" action does both), and check that nothing is left:

   ```sh
   aws s3api list-object-versions --bucket "$bucket" --region <state region> \
     --query '[length(Versions || `[]`), length(DeleteMarkers || `[]`)]'
   # [0, 0]
   ```

   Then remove the `lifecycle { prevent_destroy = true }` block from
   `bootstrap/state.tf` as a local edit you do not commit, and destroy
   with a saved plan, as everywhere else:

   ```sh
   tofu -chdir=bootstrap plan -destroy -out=destroy.tfplan
   tofu -chdir=bootstrap apply destroy.tfplan
   ```

   Afterwards delete `bootstrap/local_override.tf` and the local state,
   and `git checkout bootstrap/state.tf` so the guard is back.

## Adopting an existing instance

The module creates its instance. To bring one that already exists under it
instead, pass its alias to the module as `instance_alias` (in the root's
`main.tf`, a local change: the roots stay identical in this repository),
and import the instance and its flow log group in the environment root
before the first plan:

```hcl
import {
  to = module.hollow_hour.aws_connect_instance.this
  id = "<instance id>"
}

import {
  to = module.hollow_hour.aws_cloudwatch_log_group.connect_flow_logs[0]
  id = "/aws/connect/<alias>"
}
```

Keep that file out of the repository: it names the instance. Read the plan
before applying it: if it replaces the instance (an attribute that forces
replacement differs, such as `identity_management_type`), stop. As under
"Picking other Regions or another account", the replacement would create a
second instance under the same alias first, which Connect refuses; make the
module match the instance instead.

## License

Apache-2.0. Copyright The flow-as-code Authors.
