#!/bin/bash
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
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== C Safety Lint ==="
echo "Checking for unsafe _lunet_* function calls..."
echo ""

violations=0

# Find all .c files except *_impl.c
# Check if they call _lunet_* functions directly
check_file() {
	local file="$1"
	local basename=$(basename "$file")

	# Skip implementation files (allowed to call internal functions)
	if [[ "$basename" == *_impl.c ]]; then
		return 0
	fi

	# Skip trace.c (implements the tracing)
	if [[ "$basename" == "trace.c" ]]; then
		return 0
	fi

	# Skip co.c (defines _lunet_ensure_coroutine)
	if [[ "$basename" == "co.c" ]]; then
		return 0
	fi

	# Look for calls to _lunet_* functions
	# Pattern: _lunet_ followed by word chars, then ( for function call
	# Exclude: declarations, definitions, comments
	local matches=$(grep -n '_lunet_[a-zA-Z_]*\s*(' "$file" 2>/dev/null |
		grep -v '^\s*//' |
		grep -v '^\s*\*' |
		grep -v 'int _lunet_' |
		grep -v 'void _lunet_' || true)

	if [[ -n "$matches" ]]; then
		echo -e "${RED}VIOLATION${NC} in $file:"
		echo "$matches" | while read -r line; do
			echo "  $line"
		done
		echo ""
		echo "  Fix: Use the safe wrapper instead:"
		echo "    _lunet_ensure_coroutine() -> lunet_ensure_coroutine()"
		echo "    Make sure to #include \"trace.h\""
		echo ""
		return 1
	fi

	return 0
}

# Check all source files
for file in "$ROOT_DIR"/src/*.c "$ROOT_DIR"/ext/*/*.c; do
	if [[ -f "$file" ]]; then
		if ! check_file "$file"; then
			((violations++)) || true
		fi
	fi
done

# Also check header files (except trace.h and co.h)
for file in "$ROOT_DIR"/include/*.h "$ROOT_DIR"/ext/*/*.h; do
	if [[ -f "$file" ]]; then
		hdr_basename=$(basename "$file")
		# Skip files that are allowed to reference internal functions
		if [[ "$hdr_basename" != "trace.h" && "$hdr_basename" != "co.h" ]]; then
			if ! check_file "$file"; then
				((violations++)) || true
			fi
		fi
	fi
done

echo "=== Summary ==="
if [[ $violations -eq 0 ]]; then
	echo -e "${GREEN}All checks passed!${NC} No unsafe _lunet_* calls found."
	exit 0
else
	echo -e "${RED}Found $violations file(s) with violations.${NC}"
	echo ""
	echo "The _lunet_* functions are internal implementations that bypass"
	echo "safety checks. Use the safe wrappers from trace.h instead:"
	echo ""
	echo "  | Internal (unsafe)           | Safe wrapper (use this)        |"
	echo "  |-----------------------------|--------------------------------|"
	echo "  | _lunet_ensure_coroutine()   | lunet_ensure_coroutine()       |"
	echo ""
	echo "See AGENTS.md for the full C Code Conventions."
	exit 1
fi
