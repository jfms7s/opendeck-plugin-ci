# opendeck-plugin-ci

Shared scaffolding for the `opendeck-*` plugin repos (`-claude-usage`, `-focus-launcher`, `-power-profile`, `-synology`, `-utilities`, `-weather`): one canonical `build.mjs`, reusable `workflow_call` CI and release workflows, and `pi.css`. Each plugin keeps its own repo and its own releases (the Ansible role installs the latest published release of each); only the scaffolding is shared. Callers pin this repo by commit SHA.

| File | What it is |
| --- | --- |
| `build.mjs` | The packaging script. Byte-identical in every plugin repo, at the repo root. |
| `pi.css` | The property inspector stylesheet. Byte-identical at `assets/propertyInspector/pi.css` in every plugin that has a property inspector (power-profile has none). |
| `.github/workflows/ci.yml` | Reusable CI (`workflow_call`). |
| `.github/workflows/release.yml` | Reusable release: draft GitHub release with the bundle, `SHA256SUMS` and a build-provenance attestation. |
| `examples/<repo>/{ci,release}.yml` | The caller workflows for each plugin repo, ready to copy (replace `REPLACE_WITH_PLUGIN_CI_SHA`). |
| `examples/dependabot.yml` | The `dependabot.yml` for a plugin repo (cargo and github-actions, monthly, grouped). |
| `.github/workflows/check.yml` | This repo's own checks on push and PR: `scripts/lint.sh` (actionlint, shellcheck) and the `build.mjs` self test. |
| `scripts/check-drift.sh` | Compares every plugin repo with the canonical files. |
| `scripts/lint.sh` | actionlint (workflows and the example callers) and shellcheck, with the tools on `PATH`. |
| `tests/build.test.mjs` | Self test of `build.mjs`'s consistency checks against fixture plugin repos (`node --test tests/*.test.mjs`). |

## Adopting it in a plugin repo

1. Copy `build.mjs` to the repo root and `pi.css` to `assets/propertyInspector/pi.css` (a plain copy; `scripts/check-drift.sh` is what keeps them honest).
2. Copy `examples/<repo>/ci.yml` and `release.yml` over `.github/workflows/`, and set the `@` to the plugin-ci commit you want (keep the `# vX.Y.Z` comment when it is a tagged release, so Dependabot can bump it).
3. In the same window, edit the repo's "Protect master" ruleset so the required checks are the new names (see below). Until the ruleset is edited every PR, Dependabot's included, waits for checks that no longer exist.
4. Delete workflows the shared ones replace (power-profile's `advisories.yml`).

A private `opendeck-plugin-ci` can only be called by other repos of the same account if its Actions access allows it (Settings, Actions, General, "Access": "Accessible from repositories owned by the user"); making it public needs no setting. Reusable workflows from a public repo are callable by anyone.

## Job and check names

A job that calls a reusable workflow reports each called job as `<caller job> / <called job>`. The example callers name their job `ci` (CI) and `release` (Release), so the checks are:

| Check | Runs when | What it does |
| --- | --- | --- |
| `ci / test` | PRs, pushes | `cargo fmt --check`, `cargo clippy --all-targets --locked -D warnings`, tests (under `cargo-llvm-cov`), optional `clippy --target aarch64-apple-darwin`, property inspector tests, `test-extra` |
| `ci / bundle` | PRs, pushes | release build (thin LTO by default) of `bundle-target`, `node build.mjs --check-only`, `node build.mjs --zip <target>`, optional draft-notes check |
| `ci / msrv`, `ci / msrv-macos` | `msrv` set (`msrv-macos` for the second) | `cargo check --all-targets --locked` on the oldest supported Rust, on Ubuntu and macOS. Two jobs, not a matrix, so a matrix does not rename the check |
| `ci / aarch64` | `aarch64: true` | the aarch64 Linux cross build: `cargo check`, or (with `aarch64-check`) a release build started under qemu |
| `ci / macos` | `macos: true` (default) | native Apple Silicon: clippy, tests, PI tests, release build, `macos-check` (signature, arm64, start-up), `node build.mjs aarch64-apple-darwin` |
| `ci / audit` | `audit` set; the only job on a scheduled run | `cargo audit` or `cargo deny check <deny-checks>` |
| `ci / quality` | `quality: true` (default) | report-only eng-metrics-lab |
| `ci / gate` | PRs, pushes (not scheduled runs) | fails when a job listed in `required-jobs` was skipped or did not succeed; see "Skipped is green" |

Scheduled runs (a caller `schedule:` trigger) run only `audit`. The release workflow reports `release / verify`, `release / build-linux`, `release / build-macos`, `release / package` and `release / publish`.

The caller job must grant `contents: read` and `packages: read` (the quality job reads a package), and the release caller job `contents: write`, `id-token: write`, `attestations: write`; the called jobs each request only what they need, and only `publish` writes.

Every action is pinned by commit SHA with a `# vX.Y.Z` comment that Dependabot can bump (`dtolnay/rust-toolchain` has only a moving `v1` tag, so that is the comment), and every job runs on `ubuntu-24.04` or the `macos-runner`. Tools are pinned by version, not by hash: `cargo-audit` and `cargo-llvm-cov` (inputs, installed from crates.io or `taiki-e/install-action`), `cargo-deny` (fixed by the SHA of `cargo-deny-action`, which has no version input), and the Rust toolchain. `check.yml` downloads actionlint and shellcheck at a pinned version and verifies their sha256; bump those by hand.

## Skipped is green

GitHub counts a skipped required check as passing. Every job that an input can switch off (`bundle`, `msrv`, `msrv-macos`, `aarch64`, `macos`, `audit`, `quality`) is skipped when its input is unset, so a caller edit such as `aarch64: false` or a dropped `msrv:` would remove that protection without a red check. Two defences:

- Set `required-jobs` in the caller to the jobs its ruleset requires. `ci / gate` then fails if any of them was skipped or failed (an unknown name fails too). The examples set it. Requiring `ci / gate` in the ruleset as well makes the list itself the single place that has to be edited.
- The inputs that must stay set for each repo's required checks:

| Repo | Required checks | Inputs that must stay set |
| --- | --- | --- |
| claude-usage | `ci / test`, `ci / macos`, `ci / aarch64`, `ci / bundle` | `aarch64: true`, `macos` not `false`, `bundle` not `false` |
| focus-launcher | `ci / test`, `ci / msrv`, `ci / macos`, `ci / msrv-macos`, `ci / bundle` | `msrv` (equal to `rust-version`), `msrv-macos: true`, `macos` and `bundle` not `false` |
| power-profile | `ci / test`, `ci / bundle` | `bundle` not `false` |
| synology | `ci / test`, `ci / msrv`, `ci / aarch64`, `ci / macos`, `ci / msrv-macos`, `ci / bundle` | `msrv`, `msrv-macos: true`, `aarch64: true`, `macos` and `bundle` not `false` |
| utilities | `ci / test`, `ci / bundle`, `ci / macos` | `macos` and `bundle` not `false` |
| weather | `ci / test`, `ci / aarch64`, `ci / macos`, `ci / bundle` | `aarch64: true`, `macos` and `bundle` not `false` |

`ci / bundle` holds the release build, the `build.mjs` checks and the release-notes check that used to live inside `test`, so requiring only `ci / test` no longer protects those. Inside a job, the optional steps are gated the same way and are skipped silently when their input is empty: `macos-check`, `aarch64-check`, `pi-tests`, `release-notes-check`, `test-extra`, `macos-extra`. `audit` and `quality` are not required by any ruleset today.

## `ci.yml` inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `rust-toolchain` | `1.98.1` | toolchain for fmt, clippy, tests and builds |
| `rust-cache` | `true` | `Swatinem/rust-cache` in the CI jobs (never in the release) |
| `node-version`, `node-version-file` | `24`, empty | Node for `build.mjs` and PI tests; the file (e.g. `.nvmrc`) wins when set |
| `apt-packages` | empty | apt packages for the `test` job (`dbus-daemon`) |
| `coverage`, `cargo-llvm-cov-version` | `true`, `0.9.1` | run tests under `cargo-llvm-cov` and upload the lcov fragment |
| `clippy-darwin` | `false` | also clippy `aarch64-apple-darwin` from the Linux job |
| `pi-tests` | empty | glob for `node --test` (`tests/*.test.mjs`, `tests/pi/*.test.mjs`) |
| `test-extra` | empty | bash run in `test` after the tests (repo-specific checks) |
| `bundle`, `bundle-target` | `true`, `x86_64-unknown-linux-gnu` | the bundle job and its target |
| `bundle-lto` | `thin` | `CARGO_PROFILE_RELEASE_LTO` for PR release builds in `bundle` and `macos` (`off`, `thin`, or empty for the Cargo.toml profile) |
| `release-notes-check` | `false` | `node scripts/release-body.mjs > /dev/null` in `bundle` |
| `msrv`, `msrv-macos` | empty, `false` | MSRV toolchain (empty skips the job); also on macOS. Keep it equal to `rust-version` |
| `aarch64`, `aarch64-check` | `false`, empty | the aarch64 job; command (templates `{bin}`, `{triple}`) run on the built binary under qemu |
| `macos`, `macos-runner` | `true`, `macos-15` | the native macOS job |
| `macos-test-args`, `macos-extra`, `macos-check` | empty | extra `cargo test` arguments; extra bash (its step times out after 5 minutes, e.g. a Keychain prompt); command (template `{bin}`) for the signature and start-up check |
| `audit`, `cargo-audit-version`, `deny-checks` | empty, `0.22.2`, `advisories` | advisory scan: `cargo-audit` or `cargo-deny` |
| `quality` | `true` | the report-only job |
| `required-jobs` | empty | jobs `ci / gate` requires to have run and succeeded (see "Skipped is green") |

## `release.yml` inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `rust-toolchain`, `node-version`, `node-version-file` | as in CI | keep equal to the caller's CI |
| `apt-packages`, `pi-tests` | empty | apt packages and PI tests for `verify` |
| `audit`, `cargo-audit-version`, `deny-checks` | empty, `0.22.2`, `advisories` | advisory scan in `verify` (a tag can point at a commit that never ran CI) |
| `macos`, `macos-runner`, `macos-test` | `true`, `macos-15`, `false` | build the macOS binary natively; run its tests there |
| `check-macos` | empty | command (template `{bin}`) run on the native binary; `package` also checks it is an arm64 Mach-O |
| `aarch64-linux` | `false` | cross-build the aarch64 Linux binary |
| `check-x86_64`, `check-aarch64` | empty | commands (template `{bin}`) run on the Linux binaries (the aarch64 one under qemu). A binary whose check is unset is built and architecture-checked but never started: claude-usage sets no `check-x86_64` or `check-aarch64`, so its Linux binaries are not run in the release (its CI `aarch64` job only runs `cargo check`) |
| `release-notes` | `false` | the draft's notes come from `scripts/release-body.mjs` |

The release needs `Cargo.toml` `version` = `assets/manifest.json` `Version` = the tag without its `v`; `build.mjs --release --tag` fails otherwise. Every `CodePaths` target must be built (`macos`/`aarch64-linux` must match the manifest). The assets are `<bin>.streamDeckPlugin` and `SHA256SUMS`, the release is a draft, and nothing here publishes it.

## `build.mjs`

Reads the binary name from `Cargo.toml` and the plugin UUID from `assets/manifest.json`, so it holds no per-plugin constants.

```
node build.mjs                       package every CodePaths target that has been built
node build.mjs --all                 require every CodePaths target
node build.mjs <triple>...           package exactly these targets
node build.mjs --check-only          only the consistency checks
  --zip                              also write ./<bin>.streamDeckPlugin
  --release                          every CodePaths binary must be bundled; write dist/<bin>.streamDeckPlugin and dist/SHA256SUMS
  --expect-version <v|vX.Y.Z>        fail unless Cargo.toml and manifest.json are at this version
  --tag <vX.Y.Z>                     like --expect-version, but the tag must be exactly v<version>
  aliases: --require-all = --all, --check-version = --check-only
```

The consistency checks: Cargo and manifest versions agree (and match the tag), every action UUID is `<plugin uuid>.<action>`, every literal `const UUID` in `src/` that starts with the project family prefix (the first two segments of the plugin UUID, `com.jfms7s.`) is a manifest action, so a typo in the plugin segment is an error while a test double such as `test.echo` is ignored, `CodePaths` file names are `<bin>-<triple>`, and `CodePathLin`/`CodePathMac`/`CodePathWin` point into `CodePaths`.

## Keeping the copies identical

```
scripts/check-drift.sh                      # fetches, then reads origin/master of each opendeck-* checkout next to this repo
scripts/check-drift.sh --ref HEAD           # or any ref of the plugin repos; --root <dir> if the checkouts are elsewhere
scripts/check-drift.sh --canonical-ref HEAD # compare against this checkout's HEAD instead of origin/master (before merging a change)
scripts/check-drift.sh --no-fetch           # skip the fetches
```

It fetches this repo and every plugin repo first (a failed fetch is an error), then prints the sha256 prefix of every plugin's `build.mjs` and `pi.css` beside the canonical ones, both read from git refs rather than working trees, which reusable workflows each repo calls and at which SHA. It exits 1 on any difference, on a deleted or renamed `build.mjs` or `pi.css` (shown as `missing`; only repos in the script's `NO_PI` list, today power-profile, may lack `pi.css`), or if the callers pin more than one plugin-ci commit. To change a shared file: change it here, then copy it to the six repos in one PR each.

`scripts/lint.sh` runs actionlint and shellcheck locally; `node --test tests/*.test.mjs` runs the `build.mjs` self test. `check.yml` runs both on every push and PR.
