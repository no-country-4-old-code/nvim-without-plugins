#!/usr/bin/env bash
# cdeps.sh — render a C/C++ file/folder dependency graph as SVG (via graphviz)
#
# Usage: cdeps.sh [--files|--folders] [TARGET_DIR]
#   --files    one node per file, edges follow #include "..."
#   --folders  (default) collapse to directories, show folder→folder deps
#   TARGET_DIR  root of the project to scan (default: git root or CWD)
#
# Requirements: graphviz (dot), optionally wslu (wslview) for auto-open on WSL
# Output:  /tmp/cdeps.dot  and  /tmp/cdeps.svg  (paths printed to stdout)

set -euo pipefail

# ── argument parsing ────────────────────────────────────────────────────────
MODE="--folders"
TARGET=""

for arg in "$@"; do
    case "$arg" in
        --files|--folders) MODE="$arg" ;;
        -*) echo "Unknown option: $arg" >&2; exit 1 ;;
        *)  TARGET="$arg" ;;
    esac
done

if [[ -z "$TARGET" ]]; then
    # default: git root of current directory, fall back to CWD
    TARGET="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
fi

TARGET="$(realpath "$TARGET")"

# ── verify graphviz is available ─────────────────────────────────────────────
if ! command -v dot &>/dev/null; then
    echo "ERROR: 'dot' (graphviz) not found. Install it with: sudo apt install graphviz" >&2
    exit 1
fi

# ── collect C/C++ source files ───────────────────────────────────────────────
mapfile -t SOURCES < <(
    find "$TARGET" \
        -type d \( -name ".git" -o -name "build" -o -name "Build" -o -name "CMakeFiles" -o -name "node_modules" \) -prune \
        -o -type f \( \
            -name "*.c"   -o -name "*.cc"  -o -name "*.cpp" -o -name "*.cxx" \
            -o -name "*.h" -o -name "*.hpp" -o -name "*.hh" \
        \) -print
)

if [[ ${#SOURCES[@]} -eq 0 ]]; then
    echo "No C/C++ source files found in: $TARGET" >&2
    exit 1
fi

# ── build the edge list ──────────────────────────────────────────────────────
# For each source file, find #include "path" (local includes only, not <...>).
# Resolution order: file's own dir → project root (with path) → basename scan.
declare -A EDGES  # key="from -> to" to deduplicate
EDGE_COUNT=0

# Build a basename→fullpath map from all scanned headers so that includes
# like #include "utils.h" resolve even when the header lives in include/.
declare -A HEADER_MAP
for f in "${SOURCES[@]}"; do
    case "$f" in *.h|*.hpp|*.hh) HEADER_MAP["$(basename "$f")"]="$f" ;; esac
done

for src in "${SOURCES[@]}"; do
    src_dir="$(dirname "$src")"
    while IFS= read -r inc_rel; do
        resolved=""
        inc_base="$(basename "$inc_rel")"
        for candidate in \
            "${src_dir}/${inc_rel}" \
            "${TARGET}/${inc_rel}" \
            "${HEADER_MAP[$inc_base]:-}"; do
            if [[ -n "$candidate" && -f "$candidate" ]]; then
                resolved="$(realpath "$candidate")"
                break
            fi
        done
        # Only emit an edge if the included file is inside the project
        if [[ -n "$resolved" && "$resolved" == "$TARGET"* ]]; then
            from_rel="${src#$TARGET/}"
            to_rel="${resolved#$TARGET/}"
            if [[ "$MODE" == "--folders" ]]; then
                from_node="$(dirname "$from_rel")"
                to_node="$(dirname "$to_rel")"
                # Drop self-loops (same folder)
                [[ "$from_node" == "$to_node" ]] && continue
                # Normalise "." to the project basename
                root_name="$(basename "$TARGET")"
                [[ "$from_node" == "." ]] && from_node="$root_name"
                [[ "$to_node"   == "." ]] && to_node="$root_name"
            else
                from_node="$from_rel"
                to_node="$to_rel"
            fi
            EDGES["${from_node} -> ${to_node}"]=1
            EDGE_COUNT=$(( EDGE_COUNT + 1 ))
        fi
    done < <(grep -oP '(?<=#include ")([^"]+)' "$src" 2>/dev/null || true)
done


# ── emit graphviz dot ────────────────────────────────────────────────────────
DOT_FILE="/tmp/cdeps.dot"
SVG_FILE="/tmp/cdeps.svg"

{
    echo "digraph cdeps {"
    echo "  rankdir=LR;"
    echo "  node [shape=box fontname=\"monospace\" fontsize=10];"
    echo "  edge [color=\"#555555\"];"
    if [[ $EDGE_COUNT -eq 0 ]]; then
        echo "  \"no_local_includes\" [label=\"No local #include \\\"...\\\" found\"];"
    else
        for edge in "${!EDGES[@]}"; do
            from="${edge% -> *}"
            to="${edge#* -> }"
            echo "  \"$from\" -> \"$to\";"
        done
    fi
    echo "}"
} > "$DOT_FILE"

dot -Tsvg -o "$SVG_FILE" "$DOT_FILE"

echo "dot:  $DOT_FILE"
echo "svg:  $SVG_FILE"

# ── open in browser (WSL-aware) ───────────────────────────────────────────────
if command -v wslview &>/dev/null; then
    wslview "$SVG_FILE" &
elif command -v explorer.exe &>/dev/null; then
    explorer.exe "$(wslpath -w "$SVG_FILE")" &
elif command -v xdg-open &>/dev/null; then
    xdg-open "$SVG_FILE" &
fi
