## What changes

## How it was shown to fail

Every guarantee lands with a test that was seen to fail: name what you broke,
the test that went red, and that it passed again once restored.

- [ ] `tofu fmt -check -recursive` passes
- [ ] `init -backend=false` and `validate` pass in every root (CONTRIBUTING.md, "Running the checks")
- [ ] `tofu -chdir=tests test -test-directory=.` passes
- [ ] `node tools/equivalence/check.mjs` passes (when `modules/`, `environments/` or the snapshot changed)
- [ ] Lock files rewritten for all four platforms (when a provider constraint changed)
- [ ] VERIFY.md updated for any behavior newly relied on, with its AWS doc URL
- [ ] No account id, ARN, instance id, bucket name or phone number in the tree
