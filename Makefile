.PHONY: all build deps test clean benchdeps bench-setup-laravel bench-setup-django bench-start-laravel bench-start-django bench-stop-laravel bench-stop-django bench-stop-all bench-test

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

# Benchmarking targets
benchdeps:
	@echo "Setting up benchmark dependencies..."
	@mkdir -p bench
	@command -v php >/dev/null 2>&1 || { echo >&2 "Error: PHP 8.2+ required. Install from https://www.php.net"; exit 1; }
	@command -v composer >/dev/null 2>&1 || { echo >&2 "Error: Composer required. Install from https://getcomposer.org"; exit 1; }
	@command -v python3 >/dev/null 2>&1 || { echo >&2 "Error: Python 3.9+ required. Install Python"; exit 1; }
	@command -v git >/dev/null 2>&1 || { echo >&2 "Error: Git required"; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo >&2 "Error: curl required"; exit 1; }
	@test -f bin/bench_setup_laravel.lua || { echo >&2 "Error: bin/bench_setup_laravel.lua not found"; exit 1; }
	@test -f bin/bench_setup_django.lua || { echo >&2 "Error: bin/bench_setup_django.lua not found"; exit 1; }
	@test -f bin/bench_start_laravel.sh || { echo >&2 "Error: bin/bench_start_laravel.sh not found"; exit 1; }
	@test -f bin/bench_start_django.sh || { echo >&2 "Error: bin/bench_start_django.sh not found"; exit 1; }
	@test -f bin/realworld_tools.lua || { echo >&2 "Error: bin/realworld_tools.lua not found"; exit 1; }
	@echo "All benchmark dependencies and scripts found!"

bench-setup-laravel: benchdeps
	@echo "Setting up Laravel benchmark environment..."
	@(command -v timeout >/dev/null 2>&1 && timeout 300 lua bin/bench_setup_laravel.lua) || lua bin/bench_setup_laravel.lua || { echo "Laravel setup failed"; exit 1; }

bench-setup-django: benchdeps
	@echo "Setting up Django benchmark environment..."
	@(command -v timeout >/dev/null 2>&1 && timeout 300 lua bin/bench_setup_django.lua) || lua bin/bench_setup_django.lua || { echo "Django setup failed"; exit 1; }

bench-start-laravel: bench-setup-laravel
	@echo "Starting Laravel server..."
	bash bin/bench_start_laravel.sh

bench-start-django: bench-setup-django
	@echo "Starting Django server..."
	bash bin/bench_start_django.sh

bench-stop-laravel:
	@echo "Stopping Laravel server..."
	bash bin/bench_stop_laravel.sh || true

bench-stop-django:
	@echo "Stopping Django server..."
	bash bin/bench_stop_django.sh || true

bench-test: bench-start-laravel bench-start-django
	@echo "Running benchmark tests..."
	@echo ""
	@echo "Testing Laravel (http://localhost:8000)..."
	@(command -v timeout >/dev/null 2>&1 && timeout 30 lua bin/realworld_tools.lua test-all http://localhost:8000) || lua bin/realworld_tools.lua test-all http://localhost:8000 || true
	@echo ""
	@echo "Testing Django (http://localhost:8001)..."
	@(command -v timeout >/dev/null 2>&1 && timeout 30 lua bin/realworld_tools.lua test-all http://localhost:8001) || lua bin/realworld_tools.lua test-all http://localhost:8001 || true

bench-stop-all:
	@echo "Stopping benchmark servers..."
	bash bin/bench_stop_laravel.sh || true
	bash bin/bench_stop_django.sh || true
	@echo "Benchmark servers stopped. NOTE: bench/ directory and test evidence preserved."
	@echo "To view test results, check: bench/laravel_server.log bench/django_server.log"
	@echo "To completely remove bench/ and restart fresh: rm -rf bench/"
