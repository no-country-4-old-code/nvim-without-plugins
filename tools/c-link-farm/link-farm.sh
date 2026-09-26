#!/usr/bin/env bash
# Build a symlink farm over many C/C++ repos so clangd works without a usable
# build system. See README.md next to this script.
#
#   link-farm.sh [-o FARM] [-x DIRNAME]... [-f FLAG]... ROOT...
#
#   -o FARM     farm directory (default: ~/.cache/c-farm)
#   -x DIRNAME  folder name to skip, repeatable (.git build is always skipped)
#   -f FLAG     extra compiler flag for every file, repeatable (-DFOO, -std=c11)
#   ROOT        folders to scan (e.g. the parent folder of all repos)
#
# Result:
#   FARM/include/      one symlink per header      (foo.h   -> /repo/x/inc/foo.h)
#   FARM/src/          one symlink per source file (foo.cpp -> /repo/x/src/foo.cpp)
#   FARM/compile_flags.txt           same flags for every file, -I FARM/include
#   FARM/index/compile_commands.json every source file with those flags, so
#                                    clangd can index the whole code base
#
# Re-run it whenever files are added, removed or renamed. The clangd index
# cache (FARM/index/.cache) survives re-runs.

set -euo pipefail

farm="$HOME/.cache/c-farm"
skip=(.git build)
flags=()
while getopts "o:x:f:h" opt; do
	case $opt in
		o) farm=$OPTARG ;;
		x) skip+=("$OPTARG") ;;
		f) flags+=("$OPTARG") ;;
		*) sed -n '5,11p' "$0"; exit 1 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || { sed -n '5,11p' "$0"; exit 1; }

roots=()
for r in "$@"; do roots+=("$(realpath "$r")"); done
farm=$(realpath -m "$farm")

# find expression that prunes the skipped folder names and the farm itself
prune=(-path "$farm" -prune)
for d in "${skip[@]}"; do prune+=(-o -name "$d" -prune); done

# find_files EXT... -> absolute paths of all files with one of these extensions
find_files() {
	local names=(-false)
	for e in "$@"; do names+=(-o -name "*.$e"); done
	find "${roots[@]}" \( "${prune[@]}" \) -o -type f \( "${names[@]}" \) -print
}

# link_all DIR < paths -- symlink every path into DIR under its basename.
# Names must be unique: the first one wins, the others are reported.
link_all() {
	local dir=$1
	rm -rf "$dir"
	mkdir -p "$dir"
	awk -F/ -v dir="$dir" '
		{ name = $NF }
		name in seen { printf "duplicate %s: %s (kept %s)\n", name, $0, seen[name] > "/dev/stderr"; next }
		{ seen[name] = $0; print }
	' | xargs -r -d '\n' ln -s -t "$dir" --
	echo "$(find "$dir" -type l | wc -l) links in $dir"
}

find_files h hh hpp hxx inl ipp tpp | sort | link_all "$farm/include"
find_files c cc cpp cxx | sort | link_all "$farm/src"

# one flag per line, as clangd expects
printf '%s\n' "-I$farm/include" "${flags[@]}" > "$farm/compile_flags.txt"

# compile_commands.json: one entry per real source file (not the symlink),
# so the entry matches the path nvim opens.
mkdir -p "$farm/index"
find "$farm/src" -type l -print0 | xargs -r0 realpath | awk '
	function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
	BEGIN { while ((getline f < ARGV[1]) > 0) flags = flags ", " q(f); ARGV[1] = ""; print "[" }
	{
		dir = $0; sub(/\/[^\/]*$/, "", dir)
		cc = ($0 ~ /\.c$/) ? "cc" : "c++"
		printf "%s{\"directory\": %s, \"file\": %s, \"arguments\": [%s%s, \"-c\", %s]}\n",
			(NR > 1 ? "," : ""), q(dir), q($0), q(cc), flags, q($0)
	}
	END { print "]" }
' "$farm/compile_flags.txt" > "$farm/index/compile_commands.json"
echo "farm ready: $farm"
