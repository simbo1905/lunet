.PHONY: all build deps test clean bench-django bench-django-stop

all: build

build:
	mkdir -p build
	cd build && cmake .. && make

deps:
	@command -v luarocks >/dev/null 2>&1 || { echo >&2 "Error: luarocks not found. Please install it."; exit 1; }
	@echo "Installing dependencies..."
	luarocks install busted --local
	luarocks install luacheck --local

test: deps
	@echo "Running tests..."
	@eval $$(luarocks path --bin) && busted spec/

check: deps
	@echo "Running static analysis..."
	@eval $$(luarocks path --bin) && luacheck app/

clean:
	rm -rf build

# =============================================================================
# Django Benchmark
# Requires: mise with Python 3.12, PostgreSQL with 'conduit' database
# See bench/AGENTS.md for setup details
# =============================================================================

bench-django:
	@echo "Starting Django benchmark server..."
	@command -v mise >/dev/null 2>&1 || { echo >&2 "Error: mise required. See https://mise.jdx.dev"; exit 1; }
	@command -v nginx >/dev/null 2>&1 || { echo >&2 "Error: nginx required. brew install nginx"; exit 1; }
	@test -f bin/bench_setup_django.lua || { echo >&2 "Error: bin/bench_setup_django.lua not found"; exit 1; }
	@test -f bin/bench_start_django.sh || { echo >&2 "Error: bin/bench_start_django.sh not found"; exit 1; }
	lua bin/bench_setup_django.lua
	bash bin/bench_start_django.sh
	@echo ""
	@echo "Django benchmark running:"
	@echo "  Frontend: http://localhost:9091"
	@echo "  API:      http://localhost:9090/api"

bench-django-stop:
	@echo "Stopping Django benchmark server..."
	bash bin/bench_stop_django.sh || true
