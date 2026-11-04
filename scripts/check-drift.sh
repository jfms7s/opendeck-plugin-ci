#!/usr/bin/env bash
# Checks the opendeck-* plugin repos against this repo's canonical files.
#
#   scripts/check-drift.sh [--root <dir>] [--ref <git-ref>] [--canonical-ref <git-ref>]
#                          [--no-fetch] [<repo-dir-name>...]
#
#   --root           the directory holding the opendeck-* checkouts (default: the
#                    parent of this repo's checkout)
#   --ref            what to read in each plugin repo (default: origin/master, so a
#                    stale or dirty working tree can't hide drift)
#   --canonical-ref  what to read in this repo for build.mjs and pi.css (default:
#                    origin/master; use HEAD to check a change before it is merged)
#   --no-fetch       skip the `git fetch` of this repo and of every plugin repo
#                    that is done first (a failed fetch is an error, since the
#                    comparison would be against a stale ref)
#   names            the plugin repos to check (default: every opendeck-* next to
#                    this one except opendeck-plugin-ci)
#
# For every plugin repo it prints the first 12 hex digits of the sha256 of its
# build.mjs and pi.css next to the canonical ones, and which reusable
# workflows it calls and at which commit. Both sides are read from git refs,
# never from a working tree. It exits 1 when anything differs from the
# canonical copy (a deleted or renamed build.mjs or pi.css included, except
# for the repos in NO_PI), when a fetch fails, or when the callers pin more
# than one plugin-ci commit.
set -euo pipefail

# Plugin repos that legitimately have no property inspector, hence no pi.css.
# Every other repo must carry the canonical copy.
NO_PI=(opendeck-power-profile)

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
root=""
ref=origin/master
canonical_ref=origin/master
fetch=1
repos=()
while [ $# -gt 0 ]; do
	case $1 in
	--root) root=$2; shift ;;
	--ref) ref=$2; shift ;;
	--canonical-ref) canonical_ref=$2; shift ;;
	--no-fetch) fetch=0 ;;
	-h | --help) sed -n '2,/^set -/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
	-*) echo "unknown option $1" >&2; exit 2 ;;
	*) repos+=("$1") ;;
	esac
	shift
done
if [ -z "$root" ]; then
	# Inside .worktrees/<branch> the checkouts are three levels up.
	root=$(cd "$here/.." && pwd -P)
	case $here in */.worktrees/*) root=$(cd "$here/../../.." && pwd -P) ;; esac
fi
if [ ${#repos[@]} -eq 0 ]; then
	for dir in "$root"/opendeck-*/; do
		name=$(basename "$dir")
		[ "$name" = opendeck-plugin-ci ] || repos+=("$name")
	done
fi

digest() { sha256sum | cut -c1-12; }
no_pi() {
	local name
	for name in "${NO_PI[@]}"; do [ "$name" = "$1" ] && return 0; done
	return 1
}
# The sha256 prefix of <path> at <ref> in <repo>, or "missing" when the ref has no such file.
digest_at() {
	local repo=$1 at=$2 path=$3
	if git -C "$repo" cat-file -e "$at:$path" 2>/dev/null; then
		git -C "$repo" show "$at:$path" | digest
	else
		echo missing
	fi
}

status=0
if [ "$fetch" = 1 ]; then
	fetch_dirs=("$here")
	for name in "${repos[@]}"; do fetch_dirs+=("$root/$name"); done
	for dir in "${fetch_dirs[@]}"; do
		if ! git -C "$dir" fetch --quiet origin 2>/dev/null; then
			echo "git fetch failed in $dir: comparing against a stale ref (use --no-fetch to accept that)" >&2
			status=1
		fi
	done
fi

if ! git -C "$here" rev-parse --verify -q "$canonical_ref^{commit}" >/dev/null; then
	echo "no $canonical_ref in $here" >&2
	exit 2
fi
canonical_build=$(digest_at "$here" "$canonical_ref" build.mjs)
canonical_pi=$(digest_at "$here" "$canonical_ref" pi.css)
if [ "$canonical_build" = missing ] || [ "$canonical_pi" = missing ]; then
	echo "$canonical_ref has no build.mjs or pi.css in $here" >&2
	exit 2
fi
printf 'canonical  build.mjs %s  pi.css %s  (%s)\n' "$canonical_build" "$canonical_pi" "$canonical_ref"

pins=()
for name in "${repos[@]}"; do
	repo="$root/$name"
	if ! git -C "$repo" rev-parse --verify -q "$ref^{commit}" >/dev/null; then
		printf '%-24s no %s\n' "$name" "$ref"
		status=1
		continue
	fi
	build=$(digest_at "$repo" "$ref" build.mjs)
	pi=$(digest_at "$repo" "$ref" assets/propertyInspector/pi.css)
	mark=ok
	[ "$build" = "$canonical_build" ] || mark=DRIFT
	if [ "$pi" = missing ] && no_pi "$name"; then
		pi=none
	elif [ "$pi" != "$canonical_pi" ]; then
		mark=DRIFT
	fi
	# Which reusable workflows the repo's workflows call (a SHA, a tag, or none).
	calls=$(git -C "$repo" grep -h -o -E 'jfms7s/opendeck-plugin-ci/\.github/workflows/[a-z-]+\.yml@[^[:space:]]+' "$ref" -- .github/workflows 2>/dev/null | sed 's|jfms7s/opendeck-plugin-ci/.github/workflows/||' | sort -u | paste -sd, - || true)
	if [ -n "$calls" ]; then
		while IFS= read -r pin; do pins+=("${pin#*@}"); done < <(tr ',' '\n' <<<"$calls")
	else
		calls="no reusable workflow"
	fi
	printf '%-24s build.mjs %-12s pi.css %-12s %s  [%s]\n' "$name" "$build" "$pi" "$calls" "$mark"
	[ "$mark" = ok ] || status=1
done

if [ ${#pins[@]} -gt 0 ] && [ "$(printf '%s\n' "${pins[@]}" | sort -u | wc -l)" -gt 1 ]; then
	echo "the callers pin more than one plugin-ci commit: $(printf '%s\n' "${pins[@]}" | sort -u | paste -sd' ' -)"
	status=1
fi
exit $status
