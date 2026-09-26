#!/usr/bin/env bash
# Symlink farm over many C/C++ repos, so clangd works without a usable build
# system. `link-farm.sh -h` for usage; README.md next to this script for why.
#
# Layout of FARM:
#   include/                    one symlink per header      (foo.h -> /repo/x/inc/foo.h)
#   src/                        one symlink per source file (foo.c -> /repo/x/src/foo.c)
#   index/compile_commands.json every source file with -I FARM/include and the
#                               -f flags (-std=c++.. / gnu++.. only for C++,
#                               -std=c.. / gnu.. only for C); clangd derives
#                               header flags from nearby sources; its background
#                               index cache index/.cache is kept
#   farm.conf                   roots / skipped folders / flags, so `update`
#                               needs no arguments

set -euo pipefail

HEADERS="h hh hpp hxx inl ipp tpp"
SOURCES="c cc cpp cxx"

me=$(basename "$0")

usage() {
	cat <<EOF
$me -- symlink farm of all C/C++ headers and sources below some folders, so
one clangd serves every repo (see README.md next to this script).

Usage:
  $me build  [-o FARM] [-x DIR]... [-f FLAG]... ROOT...
  $me add    [-o FARM] [-x DIR]... [-f FLAG]... ROOT...
  $me update [-o FARM] [-q] [PATH...]
  $me status [-o FARM]
  $me check  [-o FARM] [-v]
  $me -h

Commands:
  build    Create the farm from scratch for the given ROOTs. Prints every
           duplicate file name (the first one found wins).
  add      Add more ROOTs (and -x / -f) to an existing farm, links their files.
  update   Cheap incremental refresh: drops links whose file is gone and links
           new files. Existing links are not touched, compile_commands.json is
           only rewritten when sources were added or removed.
           Without PATH every root is scanned; with PATH only those folders
           (they must lie inside a root) -- the fast choice for git hooks.
           Duplicates of already linked names are skipped silently.
  status   Show roots, skipped folders, flags and link counts.
  check    Health report, changes nothing: missing roots, clangd, dead links,
           files not linked yet, shadowed duplicate names, stale generated
           files, #include "dir/x.h" that clangd can not resolve. Every
           problem names the fix. Exit status 1 on errors. Scans all roots
           and greps every file, so it is slower than update.

Options:
  -o FARM  farm directory (default: ~/.cache/c-farm)
  -x DIR   folder name to skip everywhere, repeatable (.git and build always)
  -f FLAG  compiler flag for every file, repeatable (-DFOO, -I/x); a -std=
           goes only to its language, so C and C++ can both have one:
           -f -std=gnu11 -f -std=c++20
  -q       quiet: no summary line (update)
  -v       list every finding, not the first 5 (check)
  -h       this help

Examples:
  # one farm over libs and projects
  $me build ~/workspace/software/libs ~/workspace/software/projects

  # with defines, a standard per language, and without test / vendored code
  $me build -f -DTARGET_LINUX -f -std=gnu11 -f -std=c++20 -x test -x third_party \\
      ~/workspace/software/libs

  # later: one more folder, same farm
  $me add ~/workspace/software/tools

  # after a pull / branch switch / new file: refresh everything ...
  $me update
  # ... or only one repo (fast), e.g. from .git/hooks/post-checkout
  $me update -q "\$(git rev-parse --show-toplevel)"

  # nightly from cron
  0 6 * * * \$HOME/.config/nvim/tools/c-link-farm/$me update -q

  # something odd in nvim? see what is wrong with the farm
  $me check

  # a second farm somewhere else
  $me build -o ~/.cache/c-farm-fw ~/firmware
EOF
}

die() { echo "$me: $*" >&2; exit 1; }
log() { [ -n "$quiet" ] || echo "$@"; }

# --- arguments --------------------------------------------------------------

[ $# -gt 0 ] || { usage >&2; exit 1; }
cmd=$1
shift
case $cmd in
	-h | --help | help) usage; exit 0 ;;
	build | add | update | status | check) ;;
	*) die "unknown command '$cmd' (-h for help)" ;;
esac

farm="$HOME/.cache/c-farm"
new_skip=()
new_flags=()
quiet=
verbose=
while getopts "o:x:f:qvh" opt; do
	case $opt in
		o) farm=$OPTARG ;;
		x) new_skip+=("$OPTARG") ;;
		f)
			# `-f std=c++20` would reach clang as a second input file
			[ "${OPTARG#-}" != "$OPTARG" ] || die "-f $OPTARG: a flag starts with '-' (-f -$OPTARG?)"
			new_flags+=("$OPTARG")
			;;
		q) quiet=1 ;;
		v) verbose=1 ;;
		h) usage; exit 0 ;;
		*) die "-h for help" ;;
	esac
done
shift $((OPTIND - 1))
farm=$(realpath -m "$farm")

case $cmd in
	build | add) [ $# -gt 0 ] || die "$cmd needs at least one ROOT" ;;
	update | status | check)
		[ ${#new_skip[@]} -eq 0 ] && [ ${#new_flags[@]} -eq 0 ] ||
			die "-x / -f only work with build or add"
		;;
esac
case $cmd in status | check) [ $# -eq 0 ] || die "$cmd takes no arguments" ;; esac

# absolute, resolved folders; a missing one is an error, not an empty scan
paths=()
for p in "$@"; do
	[ -d "$p" ] || die "not a folder: $p"
	paths+=("$(realpath "$p")")
done

# --- farm.conf ----------------------------------------------------------------

roots=()
skip=(.git build)
flags=()

load_conf() {
	[ -f "$farm/farm.conf" ] || die "no farm at $farm -- run '$me build ROOT...' first"
	# shellcheck source=/dev/null
	source "$farm/farm.conf"
	[ ${#roots[@]} -gt 0 ] || die "$farm/farm.conf lists no roots -- run '$me build ROOT...'"
}

# plain assignments, not `declare -p`: that would turn into locals when
# load_conf sources the file inside a function
save_conf() {
	local name
	for name in roots skip flags; do
		local -n arr=$name
		printf '%s=(' "$name"
		[ ${#arr[@]} -eq 0 ] || printf ' %q' "${arr[@]}"
		printf ' )\n'
	done > "$farm/farm.conf"
}

# append $2... to the array named $1, skipping entries already in it
add_unique() {
	local -n arr=$1
	shift
	local v e
	for v in "$@"; do
		for e in "${arr[@]}"; do [ "$e" = "$v" ] && continue 2; done
		arr+=("$v")
	done
}

# is $1 one of the roots or inside one?
in_roots() {
	local r
	for r in "${roots[@]}"; do
		[ "$1" = "$r" ] || [ "${1#"$r"/}" != "$1" ] && return 0
	done
	return 1
}

# --- farm work ------------------------------------------------------------------

# find_files "EXT..." DIR... -> absolute paths below DIR with one of the
# extensions, skipped folders and the farm itself pruned, sorted (so the
# "first one wins" rule for duplicates is stable)
find_files() {
	local names=(-false) prune=(-path "$farm" -prune) e d
	for e in $1; do names+=(-o -name "*.$e"); done
	for d in "${skip[@]}"; do prune+=(-o -name "$d" -prune); done
	shift
	find "$@" \( "${prune[@]}" \) -o -type f \( "${names[@]}" \) -print | sort
}

# link_new DIR REPORT < paths -- symlink every path whose basename is not yet
# linked in DIR; with REPORT=1 print the duplicates. Echoes the number linked.
link_new() {
	local dir=$1 report=$2 new
	new=$(awk -F/ -v report="$report" '
		BEGIN {
			# existing links: "name<TAB>target"
			while ((getline l < ARGV[1]) > 0) {
				i = index(l, "\t")
				have[substr(l, 1, i - 1)] = substr(l, i + 1)
			}
			ARGV[1] = ""
		}
		{ name = $NF }
		name in have {
			if (report && have[name] != $0)
				printf "duplicate %s: %s (kept %s)\n", name, $0, have[name] > "/dev/stderr"
			next
		}
		{ have[name] = $0; print }
	' <(find "$dir" -maxdepth 1 -type l -printf '%f\t%l\n') -)
	[ -z "$new" ] && { echo 0; return; }
	printf '%s\n' "$new" | xargs -d '\n' ln -s -t "$dir" --
	printf '%s\n' "$new" | wc -l
}

# delete links in DIR whose file is gone; echoes how many
drop_dead() {
	find "$1" -maxdepth 1 -xtype l -print -delete | wc -l
}

# compile_commands.json: one entry per real source file (the link target, not
# the link), so the entry matches the path nvim opens. A -std= flag only goes
# to its own language (clang rejects -std=gnu11 for C++ and vice versa).
# Written to a temp file and moved, so clangd never reads half a file.
write_commands() {
	local out="$farm/index/compile_commands.json"
	find "$farm/src" -maxdepth 1 -type l -printf '%l\n' | sort | awk '
		function q(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return "\"" s "\"" }
		BEGIN {
			while ((getline f < ARGV[1]) > 0) {
				if (f ~ /^-std=(c|gnu)\+\+/) cxx = cxx ", " q(f)
				else if (f ~ /^-std=/) c = c ", " q(f)
				else { c = c ", " q(f); cxx = cxx ", " q(f) }
			}
			ARGV[1] = ""
			print "["
		}
		{
			dir = $0; sub(/\/[^\/]*$/, "", dir)
			isc = $0 ~ /\.c$/
			printf "%s{\"directory\": %s, \"file\": %s, \"arguments\": [%s%s, \"-c\", %s]}\n",
				(NR > 1 ? "," : ""), q(dir), q($0), q(isc ? "cc" : "c++"), (isc ? c : cxx), q($0)
		}
		END { print "]" }
	' <(printf '%s\n' "-I$farm/include" "${flags[@]}") - > "$out.tmp"
	mv "$out.tmp" "$out"
}

count() { find "$farm/$1" -maxdepth 1 -type l 2> /dev/null | wc -l; }

# sync REPORT DIR... -- bring the farm in line with the files below DIR
sync() {
	local report=$1 gone_h gone_s new_h new_s
	shift
	mkdir -p "$farm/include" "$farm/src" "$farm/index"
	gone_h=$(drop_dead "$farm/include")
	gone_s=$(drop_dead "$farm/src")
	new_h=$(find_files "$HEADERS" "$@" | link_new "$farm/include" "$report")
	new_s=$(find_files "$SOURCES" "$@" | link_new "$farm/src" "$report")
	if [ "$gone_s" -gt 0 ] || [ "$new_s" -gt 0 ] || [ "$cmd" != update ] ||
		[ ! -f "$farm/index/compile_commands.json" ]; then
		write_commands
	fi
	log "+$((new_h + new_s)) -$((gone_h + gone_s)) links;" \
		"$(count include) headers, $(count src) sources in $farm"
}

# --- commands -------------------------------------------------------------------

if [ "$cmd" = status ]; then
	load_conf
	echo "farm:    $farm"
	printf 'root:    %s\n' "${roots[@]}"
	echo "skip:    ${skip[*]}"
	echo "flags:   ${flags[*]:-(none)}"
	echo "links:   $(count include) headers, $(count src) sources"
	echo "updated: $(date -r "$farm/index/compile_commands.json" '+%F %T')"
	exit 0
fi

# --- check: read-only health report -------------------------------------------

errors=0
warnings=0
ok() { echo "ok     $*"; }
warn() { echo "warn   $*"; warnings=$((warnings + 1)); }
error() { echo "ERROR  $*"; errors=$((errors + 1)); }
lines() { awk 'END { print NR }'; } # wc -l, but "0" for an empty string too
# stdin indented below the last message; first 5 lines unless -v
examples() {
	awk -v all="$verbose" '
		all || NR <= 5 { print "         " $0 }
		END { if (!all && NR > 5) print "         ... " NR - 5 " more (-v lists all)" }
	'
}

if [ "$cmd" = check ]; then
	# a report, not a job: a probe that fails (grep without match, a missing
	# folder) must not end the report half-way
	set +e +o pipefail
	load_conf
	echo "farm $farm"
	for d in include src index; do
		[ -d "$farm/$d" ] || error "$farm/$d is missing -- run 'build'"
	done

	# roots: gone, nested (scanned twice), or without any C/C++ file
	live=()
	for r in "${roots[@]}"; do
		if [ ! -d "$r" ]; then
			error "root is gone: $r -- 'build' without it (update fails until then)"
			continue
		fi
		live+=("$r")
		for o in "${roots[@]}"; do
			[ "${r#"$o"/}" != "$r" ] && warn "root $r lies inside root $o -- drop it with 'build'"
		done
	done
	[ ${#live[@]} -eq ${#roots[@]} ] && ok "${#roots[@]} root(s) exist"

	if command -v clangd > /dev/null; then
		ok "$(clangd --version | head -n 1)"
	else
		error "clangd not on \$PATH"
	fi

	# links: file deleted, or pointing outside the roots (a root was dropped)
	dead=$(find "$farm/include" "$farm/src" -maxdepth 1 -xtype l -printf '%l\n' 2> /dev/null)
	n=$(printf '%s' "$dead" | lines)
	if [ "$n" -gt 0 ]; then
		warn "$n link(s) to deleted files -- run 'update'"
		printf '%s\n' "$dead" | examples
	else
		ok "no links to deleted files"
	fi
	outside=$(find "$farm/include" "$farm/src" -maxdepth 1 -type l -printf '%l\n' 2> /dev/null |
		awk 'BEGIN { for (i = 1; i < ARGC; i++) root[i] = ARGV[i] "/"; n = ARGC; ARGC = 1 }
			{ for (i = 1; i < n; i++) if (index($0, root[i]) == 1) next; print }' "${roots[@]}")
	n=$(printf '%s' "$outside" | lines)
	if [ "$n" -gt 0 ]; then
		warn "$n link(s) outside every root -- run 'build'"
		printf '%s\n' "$outside" | examples
	fi

	# scan the roots and compare with the links:
	#   new  -- not linked yet (update missing)
	#   dup  -- same name as a linked file, so never linked: a shadowed header may
	#           be the wrong one for an #include, a shadowed source is not indexed
	scan() { # scan "EXT..." DIR -> "new<TAB>path" / "dup<TAB>path<TAB>kept"
		find_files "$1" "${live[@]}" | awk -F/ '
			BEGIN {
				while ((getline l < ARGV[1]) > 0) {
					i = index(l, "\t"); name[substr(l, 1, i - 1)] = substr(l, i + 1); linked[substr(l, i + 1)] = 1
				}
				ARGV[1] = ""
			}
			$0 in linked { next }
			$NF in name { print "dup\t" $0 "\t" name[$NF]; next }
			{ print "new\t" $0 }
		' <(find "$farm/$2" -maxdepth 1 -type l -printf '%f\t%l\n' 2> /dev/null) -
	}
	[ ${#live[@]} -gt 0 ] || { echo "no root to scan"; exit 1; }
	headers=$(scan "$HEADERS" include)
	sources=$(scan "$SOURCES" src)
	new=$(printf '%s\n' "$headers" "$sources" | awk -F'\t' '$1 == "new" { print $2 }')
	n=$(printf '%s' "$new" | lines)
	if [ "$n" -gt 0 ]; then
		warn "$n file(s) not linked yet -- run 'update'"
		printf '%s\n' "$new" | examples
	else
		ok "every file in the roots is linked"
	fi
	dup=$(printf '%s\n' "$headers" | awk -F'\t' '$1 == "dup" { print $2 "  (kept " $3 ")" }')
	n=$(printf '%s' "$dup" | lines)
	if [ "$n" -gt 0 ]; then
		warn "$n header(s) shadowed by one with the same name -- #include may get the wrong one"
		printf '%s\n' "$dup" | examples
	else
		ok "header names are unique"
	fi
	dup=$(printf '%s\n' "$sources" | awk -F'\t' '$1 == "dup" { print $2 "  (kept " $3 ")" }')
	n=$(printf '%s' "$dup" | lines)
	if [ "$n" -gt 0 ]; then
		warn "$n source(s) not indexed: same name as a linked source"
		printf '%s\n' "$dup" | examples
	fi

	# generated files match farm.conf and the links
	if [ "$farm/farm.conf" -nt "$farm/index/compile_commands.json" ]; then
		warn "compile_commands.json is older than farm.conf -- run 'build'"
	fi
	[ -f "$farm/compile_flags.txt" ] &&
		warn "$farm/compile_flags.txt is no longer used (it forces C on every .h) -- delete it"
	entries=$(awk '/"file":/ { n++ } END { print n + 0 }' "$farm/index/compile_commands.json" 2> /dev/null || echo 0)
	if [ "$entries" -eq "$(count src)" ]; then
		ok "compile_commands.json has all $entries sources"
	else
		warn "compile_commands.json has $entries of $(count src) sources -- run 'update'"
	fi
	[ -d "$farm/index/.cache/clangd/index" ] &&
		ok "clangd index cache: $(find "$farm/index/.cache/clangd/index" -type f | lines) files (sources + headers)"

	# #include "sub/foo.h": the flat farm can not resolve a path; fine when it
	# exists next to the including file or below one of the -I flags
	incdirs=()
	for f in "${flags[@]}"; do [ "${f#-I}" != "$f" ] && incdirs+=("${f#-I}"); done
	unresolved=$(
		find "$farm/include" "$farm/src" -maxdepth 1 -type l -printf '%l\0' 2> /dev/null |
			xargs -0 -r grep -HoE '^[[:space:]]*#[[:space:]]*include[[:space:]]*"[^"]*/[^"]*"' 2> /dev/null |
			while IFS= read -r m; do
				file=${m%%:*}
				inc=${m#*\"}
				inc=${inc%\"}
				[ -e "${file%/*}/$inc" ] && continue
				for d in "${incdirs[@]}"; do [ -e "$d/$inc" ] && continue 2; done
				printf '%s  (in %s)\n' "$inc" "$file"
			done | sort -u -t ' ' -k 1,1
	)
	n=$(printf '%s' "$unresolved" | lines)
	if [ "$n" -gt 0 ]; then
		warn "$n #include path(s) with a folder clangd can not find -- add the base folder with -f -I<dir>"
		printf '%s\n' "$unresolved" | examples
	else
		ok "every #include \"dir/file.h\" resolves"
	fi

	echo "$errors error(s), $warnings warning(s)"
	[ "$errors" -eq 0 ]
	exit
fi

mkdir -p "$farm"
# a cron run and a git hook at the same time would race on the links
exec 9> "$farm/.lock"
flock 9

case $cmd in
	build)
		# only ever wipe something that looks like a farm
		if [ -n "$(ls -A "$farm" | grep -vx -e .lock -e index)" ] && [ ! -d "$farm/include" ]; then
			die "$farm is not empty and not a farm -- refusing to overwrite it"
		fi
		rm -rf "$farm/include" "$farm/src" "$farm/compile_flags.txt" # index/.cache (clangd) survives
		roots=("${paths[@]}")
		add_unique skip "${new_skip[@]}"
		flags=("${new_flags[@]}")
		save_conf
		sync 1 "${roots[@]}"
		;;
	add)
		load_conf
		add_unique roots "${paths[@]}"
		add_unique skip "${new_skip[@]}"
		add_unique flags "${new_flags[@]}"
		save_conf
		sync 1 "${paths[@]}"
		;;
	update)
		load_conf
		for p in "${paths[@]}"; do
			in_roots "$p" || die "$p is not inside a farm root -- use '$me add $p'"
		done
		[ ${#paths[@]} -gt 0 ] || paths=("${roots[@]}")
		sync "" "${paths[@]}"
		;;
esac
