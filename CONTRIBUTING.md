# Contributing

## Ground rules

- The repository root is Terraform, and deploying needs nothing else:
  OpenTofu 1.10 or later, the AWS CLI and AWS credentials. OpenTofu is
  what CI tests; Terraform 1.11 or later should work but is untested.
  Node appears only in `tools/equivalence/`, a CI check.
- Flows are HCL in `modules/hollow-hour/`. A flow that is one resource is a
  `hh-<name>.flow.tf` that flow-cli can read; a flow per district is one
  resource over `var.districts`. Action ids, text and branching match the
  TypeScript-first repository's; change one side and the equivalence check
  fails until the snapshot is moved to a commit that has the same change.
- References are resource attributes bound through `refs`, and actions name
  reference keys (`queue:old-town-crew`). Never a literal ARN;
  `tests/hygiene.tftest.hcl` fails on `arn:aws` under `modules/`.
- The environment roots are identical but for `terraform.tfvars`, and a
  tfvars sets `environment`, `aws_region`, `hours` and `season` and nothing
  else. A new setting is a module variable with a default.
- Every guarantee lands with a test that has been shown to fail: break what
  it guards, watch it go red, restore it, and say so in the pull request.
- A Connect behavior newly relied on gets a row in `VERIFY.md` (or a pointer
  to the TypeScript-first repository's row), with its AWS documentation, and
  stays "needs sandbox" until a live apply records the service's answer.
- No account ids, ARNs, instance ids, bucket names or credentials anywhere
  in the tree. `terraform.tfvars` holds choices, never ids.
- Every source file starts with the Apache-2.0 header naming "The
  flow-as-code Authors"; never a legal entity's name.
- Every third-party action in `.github/workflows/` is pinned to a full
  commit SHA with its version in a trailing comment.
- Prose uses no em-dashes.
- Conventional commits, small and self-contained, docs in the same commit.

## Running the checks

```sh
tofu fmt -check -recursive
for root in bootstrap environments/dev environments/qa environments/prod tools/equivalence/harness; do
  tofu -chdir="$root" init -backend=false -lockfile=readonly && tofu -chdir="$root" validate
done
tofu -chdir=tests init -lockfile=readonly -test-directory=.
tofu -chdir=tests test -test-directory=.
npm --prefix tools/equivalence ci && node tools/equivalence/check.mjs
```

None of them calls AWS. The first init downloads the aws, archive, random
and flowascode providers from the OpenTofu registry.

## Provider locks

Each root commits its `.terraform.lock.hcl` with hashes for Linux and macOS
on amd64 and arm64, so an init installs only reviewed builds. After changing
a provider constraint, rewrite them:

```sh
for root in bootstrap environments/dev environments/qa environments/prod tests tools/equivalence/harness; do
  tofu -chdir="$root" providers lock \
    -platform=darwin_arm64 -platform=darwin_amd64 \
    -platform=linux_amd64 -platform=linux_arm64
done
```

These are OpenTofu registry locks (`registry.opentofu.org`). With Terraform,
run `terraform providers lock` with the same platforms for its own
registry's entries; keep that diff out of a pull request.

Dependabot moves the provider constraints and lock files, but its pull
request may lock fewer platforms than these four. Run the loop above on its
branch before merging, so every platform keeps its hashes.

## Deploying

`.github/workflows/deploy.yml`, dispatched by hand: a plan job with no
gate, then, when asked, an apply job that waits for prod's reviewer and
applies that saved plan (README.md, "Deploying from GitHub"). One deploy
runs at a time across every environment. Never apply two environments in
one Region at once by hand either: the Connect API throttle is shared, and
a second instance create can be refused while the first is pending.
