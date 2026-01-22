#!/bin/sh
#
# C Safety Lint - Enforces naming conventions for zero-cost tracing
#
# Rules:
#   1. _lunet_* functions must only be called from:
#      - include/trace.h (where safe wrappers are defined)
#      - *_impl.c files (rare, for internal implementations)
#
#   2. All other .c files must use the safe public API (lunet_*)
#
# Usage:
#   bin/lint_c_safety.sh [--fix]
#
# Exit codes:
#   0 - All checks passed
#   1 - Violations found

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")

echo "=== C Safety Lint ==="
echo "Checking for unsafe _lunet_* function calls..."
echo ""

violations=0

# Find all .c files except *_impl.c
# Check if they call _lunet_* functions directly
check_file() {
	file="$1"
	base=$(basename "$file")

	# Skip implementation files (allowed to call internal functions)
	case "$base" in
	*_impl.c) return 0 ;;
	trace.c) return 0 ;;
	co.c) return 0 ;;
	esac

	# Look for calls to _lunet_* functions
	# Pattern: _lunet_ followed by word chars, then ( for function call
	# Exclude: declarations, definitions, comments
	matches=$(grep -n '_lunet_[a-zA-Z_]*[[:space:]]*(' "$file" 2>/dev/null |
		grep -E -v '^[0-9]+:[[:space:]]*(//|/\*|\*)' |
		grep -v 'int _lunet_' |
		grep -v 'void _lunet_' || true)

	if [ -n "$matches" ]; then
		printf "%bVIOLATION%b in %s:\n" "$RED" "$NC" "$file"
		printf "%s\n" "$matches" | while IFS= read -r line; do
			printf "  %s\n" "$line"
		done
		printf "\n"
		printf "  Fix: Use the safe wrapper instead:\n"
		printf "    _lunet_ensure_coroutine() -> lunet_ensure_coroutine()\n"
		printf "    Make sure to #include \"trace.h\"\n\n"
		return 1
	fi

	return 0
}

# Check all source files
for file in "$ROOT_DIR"/src/*.c "$ROOT_DIR"/ext/*/*.c; do
	if [ -f "$file" ]; then
		if ! check_file "$file"; then
			violations=$((violations + 1))
		fi
	fi
done

# Also check header files (except trace.h and co.h)
for file in "$ROOT_DIR"/include/*.h "$ROOT_DIR"/ext/*/*.h; do
	if [ -f "$file" ]; then
		hdr_basename=$(basename "$file")
		# Skip files that are allowed to reference internal functions
		if [ "$hdr_basename" != "trace.h" ] && [ "$hdr_basename" != "co.h" ]; then
			if ! check_file "$file"; then
				violations=$((violations + 1))
			fi
		fi
	fi
done

echo "=== Summary ==="
if [ "$violations" -eq 0 ]; then
	printf "%bAll checks passed!%b No unsafe _lunet_* calls found.\n" "$GREEN" "$NC"
	exit 0
else
	printf "%bFound %s file(s) with violations.%b\n\n" "$RED" "$violations" "$NC"
	printf "%s\n" "The _lunet_* functions are internal implementations that bypass"
	printf "%s\n\n" "safety checks. Use the safe wrappers from trace.h instead:"
	printf "%s\n" "  | Internal (unsafe)           | Safe wrapper (use this)        |"
	printf "%s\n" "  |-----------------------------|--------------------------------|"
	printf "%s\n\n" "  | _lunet_ensure_coroutine()   | lunet_ensure_coroutine()       |"
	printf "%s\n" "See AGENTS.md for the full C Code Conventions."
	exit 1
fi
