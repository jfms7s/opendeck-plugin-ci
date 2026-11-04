#!/usr/bin/env bash
# Checks the opendeck-* plugin repos against this repo's canonical files.
#
#   scripts/check-drift.sh [--root <dir>] [--ref <git-ref>] [<repo-dir-name>...]
#
#   --root  the directory holding the opendeck-* checkouts (default: the parent
#           of this repo's checkout)
#   --ref   what to read in each plugin repo (default: origin/master, so a
#           stale or dirty working tree can't hide drift; `git fetch` first)
#   names   the plugin repos to check (default: every opendeck-* next to this
#           one except opendeck-plugin-ci)
#
# For every plugin repo it prints the first 12 hex digits of the sha256 of its
# build.mjs and pi.css next to the canonical ones, and which reusable
# workflows it calls and at which commit. It exits 1 when anything differs from
# the canonical copy, or when the callers pin more than one plugin-ci commit.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
root=""
ref=origin/master
repos=()
while [ $# -gt 0 ]; do
	case $1 in
	--root) root=$2; shift ;;
	--ref) ref=$2; shift ;;
	-h | --help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

hash() { sha256sum | cut -c1-12; }
canonical_build=$(hash <"$here/build.mjs")
canonical_pi=$(hash <"$here/pi.css")
printf 'canonical  build.mjs %s  pi.css %s\n' "$canonical_build" "$canonical_pi"

status=0
pins=()
for name in "${repos[@]}"; do
	repo="$root/$name"
	if ! git -C "$repo" rev-parse --verify -q "$ref^{commit}" >/dev/null; then
		printf '%-24s no %s\n' "$name" "$ref"
		status=1
		continue
	fi
	build=$(git -C "$repo" show "$ref:build.mjs" 2>/dev/null | hash || true)
	[ -n "$build" ] || build=missing
	# power-profile has no property inspector, so no pi.css: that is not drift.
	if git -C "$repo" cat-file -e "$ref:assets/propertyInspector/pi.css" 2>/dev/null; then
		pi=$(git -C "$repo" show "$ref:assets/propertyInspector/pi.css" | hash)
	else
		pi=none
	fi
	mark=ok
	[ "$build" = "$canonical_build" ] || mark=DRIFT
	{ [ "$pi" = "$canonical_pi" ] || [ "$pi" = none ]; } || mark=DRIFT
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
