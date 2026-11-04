#!/usr/bin/env bash
# Lints this repo: shellcheck on every script, actionlint on the reusable
# workflows, this repo's own workflows and the example callers.
#
#   scripts/lint.sh        needs actionlint and shellcheck on PATH
#
# The example callers pin the reusable workflows by a placeholder SHA, so they
# are linted against the local copies (which also checks every input name and
# type they pass).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$here"

for tool in actionlint shellcheck; do
	command -v "$tool" >/dev/null || { echo "lint.sh: $tool is not on PATH" >&2; exit 2; }
done

echo "shellcheck"
shellcheck scripts/*.sh

echo "actionlint (workflows)"
actionlint -color=false

echo "actionlint (examples against the local reusable workflows)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.github/workflows"
git init -q "$tmp" # actionlint finds the project root by its .git
cp .github/workflows/ci.yml .github/workflows/release.yml "$tmp/.github/workflows/"
for example in examples/*/*.yml; do
	repo=$(basename "$(dirname "$example")")
	sed -E 's|jfms7s/opendeck-plugin-ci/(\.github/workflows/[a-z-]+\.yml)@[^[:space:]]+|./\1|' "$example" >"$tmp/.github/workflows/$repo-$(basename "$example")"
done
(cd "$tmp" && actionlint -color=false)
echo "lint.sh: clean"
