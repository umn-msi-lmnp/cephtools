# Refactor Plan

## #1 bucketpolicy reliability (IN PROGRESS)

Scope: fail on unresolved principals, fail on failed policy application,
accurate result summaries in terminal and readme, normalize LIST input,
tighten CLI help.

- [x] Add `_resolve_policy_users` helper (s3info resolution, fail-fast)
- [x] Wire helper into GROUP and LIST branches
- [x] Track `_policy_result` through setpolicy/delpolicy/do_not_setpolicy
- [x] Pass result into readme and terminal summary
- [x] Return 1 on policy application failure
- [x] Normalize LIST input: tr comma, trim whitespace, deduplicate
- [x] Tighten CLI help text (GROUP_READ_WRITE / LIST_READ_WRITE = "full bucket permissions")
- [x] Integration tests: generated-only, apply failure, unresolved user, list normalization
- [x] All tests pass
- [ ] Update changelog + bump version
- [ ] Commit

## #2 doc/vignette_bucketpolicy.md corrections (PENDING)

- Align vignette with actual CLI flags and behavior
- Remove stale examples, add `--do_not_setpolicy` example
- Keep lean; no verbose rewrites

## #3 README.md typo + minor doc fixes (PENDING)

- Fix known typo in readme.md
- Any small inconsistencies found during audit

## #4 panfs2ceph doc/code alignment (PENDING)

- Correct package docs to match actual behavior
- Lean corrections only

## #5 dd2ceph doc/code alignment (PENDING)

- Correct package docs to match actual behavior
- Lean corrections only

## #6 Final packaging / install.md review (PENDING)

- Ensure install.md and build docs are consistent
- No verbose additions
