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
| `scripts/check-drift.sh` | Compares every plugin repo with the canonical files. |

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

Scheduled runs (a caller `schedule:` trigger) run only `audit`. The release workflow reports `release / verify`, `release / build-linux`, `release / build-macos`, `release / package` and `release / publish`.

The caller job must grant `contents: read` and `packages: read` (the quality job reads a package), and the release caller job `contents: write`, `id-token: write`, `attestations: write`; the called jobs each request only what they need, and only `publish` writes. Everything is SHA-pinned.

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
| `macos-test-args`, `macos-extra`, `macos-check` | empty | extra `cargo test` arguments; extra bash; command (template `{bin}`) for the signature and start-up check |
| `audit`, `cargo-audit-version`, `deny-checks` | empty, `0.22.2`, `advisories` | advisory scan: `cargo-audit` or `cargo-deny` |
| `quality` | `true` | the report-only job |

## `release.yml` inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `rust-toolchain`, `node-version`, `node-version-file` | as in CI | keep equal to the caller's CI |
| `apt-packages`, `pi-tests` | empty | apt packages and PI tests for `verify` |
| `audit`, `cargo-audit-version`, `deny-checks` | empty, `0.22.2`, `advisories` | advisory scan in `verify` (a tag can point at a commit that never ran CI) |
| `macos`, `macos-runner`, `macos-test` | `true`, `macos-15`, `false` | build the macOS binary natively; run its tests there |
| `check-macos` | empty | command (template `{bin}`) run on the native binary; `package` also checks it is an arm64 Mach-O |
| `aarch64-linux` | `false` | cross-build the aarch64 Linux binary |
| `check-x86_64`, `check-aarch64` | empty | commands (template `{bin}`) run on the Linux binaries (the aarch64 one under qemu) |
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

The consistency checks: Cargo and manifest versions agree (and match the tag), every action UUID is `<plugin uuid>.<action>`, every literal `const UUID` in `src/` that is under the plugin's namespace is a manifest action, `CodePaths` file names are `<bin>-<triple>`, and `CodePathLin`/`CodePathMac`/`CodePathWin` point into `CodePaths`.

## Keeping the copies identical

```
scripts/check-drift.sh            # reads origin/master of each opendeck-* checkout next to this repo
scripts/check-drift.sh --ref HEAD # or any ref; --root <dir> if the checkouts are elsewhere
```

It prints the sha256 prefix of every plugin's `build.mjs` and `pi.css` beside the canonical ones, which reusable workflows each repo calls and at which SHA, and exits 1 on any difference or if the callers pin more than one plugin-ci commit. To change a shared file: change it here, then copy it to the six repos in one PR each.
