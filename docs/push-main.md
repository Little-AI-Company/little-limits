---
title: "Push to main"
summary: "How a change lands: scripts/push_main.sh checks one commit, records the result in Tested: trailers, and fast-forwards main. GitHub Actions builds it afterwards."
read_when:
  - "A change is done and you land it on main."
  - "You revert a commit on main."
  - "main is red after a push."
---

# Push to main

Every change lands as one commit on `main`, pushed by `scripts/push_main.sh`. There are no branches, pull requests, or required statuses ([AGENTS.md: Shipping on main](../AGENTS.md#shipping-on-main)). This is the small-repo version of little-worker's route (little-worker `docs/push-main.md`); it has no commit status, proof loop, or feature flags.

## Land a commit

```sh
git fetch origin main
git switch --detach origin/main
# edit, then:
git commit            # one purpose; Customer-note: trailer on feat, fix, perf
git show HEAD         # read every line
scripts/push_main.sh  # --package for UI, lifecycle, resource, or packaging changes
```

The script:

1. Refuses a dirty tree, no commit ahead of `origin/main`, or several commits (`--squash "<subject>"` folds them into one).
2. Rebases the commit onto `origin/main`.
3. Refuses a `feat`, `fix`, or `perf` commit without a `Customer-note:` trailer. The scopes `release`, `website`, `ci`, `test`, and `repo` need none. The trailer must be in the last paragraph, beside `Co-Authored-By:`.
4. Runs `git diff --check`. When the commit touches `Sources/`, `Tests/`, `Resources/`, `scripts/`, or the package files, it also runs the full `swift test`, plus `scripts/package_app.sh` and `codesign --verify` with `--package`:
   - here, on a Mac with Swift;
   - otherwise on the M4 over `ssh m4`. It sends the commit as a git bundle on standard input, so nothing reaches GitHub before the check passes, and checks it in `~/Developer/little-limits-push`, one run at a time. A cold build there takes about 7 minutes; later runs reuse `.build`. From a cloud session, run little-worker's `bash scripts/m4-ssh-setup.sh` once;
   - otherwise with a Linux Swift, which builds only `UsageHistory`;
   - otherwise it stops. `--no-swift "<why>"` pushes anyway and records `Tested: swift test not-run (<why>)`.
5. Writes one `Tested:` trailer per check, naming the tree it passed on:

   ```text
   Tested: git diff --check pass tree 3f2a9c1d7e0b
   Tested: swift test pass (m4, macOS 26.7.2, Xcode 27.1, 41s) tree 3f2a9c1d7e0b
   ```

6. Pushes `git push origin <sha>:refs/heads/main`. If `main` moved, it fetches, rebases, checks again, and retries, 3 times.

`--verify` runs the checks on HEAD and pushes nothing.

The last line on standard output is `PUSH: <state> <sha>`. Exit codes: `0` pushed or verified, `1` usage or git error, `2` a check failed and `main` is unchanged, `3` rebase conflict (aborted), `4` `main` kept moving, `5` not pushable (dirty, nothing to push, several commits, no Customer-note, no Swift).

## After the push

`.github/workflows/ci.yml` packages, verifies the signature, and runs the full tests on GitHub's `xcode-27` macOS image, and runs the `UsageHistory` tests on Linux. Nobody waits for it. The M4 runs macOS 26 with Xcode 27.1; this run is the check on a clean machine and the macOS 27 runtime.

If it turns red, whoever pushed the commit fixes it forward or reverts it within the hour.

## Revert

```sh
scripts/push_main.sh --revert <sha> --reason "<what broke>"
```

It reverts the commit on top of `origin/main`, adds `Customer-note: none (reverts <sha12>: <reason>)`, checks the result, and pushes it. Reland the change as a new commit.

## Never

- Push `main` any other way, force-push, or amend a pushed commit.
- Write a `Tested:` trailer by hand.
- Skip or weaken a test to get the check green.
