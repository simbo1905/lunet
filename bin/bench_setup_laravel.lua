#!/usr/bin/env lua

local function run(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    local result = handle:read("*a")
    handle:close()
    return result
end

local function check_command(cmd)
    local result = run("which " .. cmd)
    return result ~= "" and result or nil
end

local log_file = nil

local function setup_logging()
    local tmp_dir = os.getenv("TMP_DIR") or "/Users/Shared/lunet/.tmp"
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local run_dir = tmp_dir .. "/bench_" .. timestamp
    run(string.format("mkdir -p '%s'", run_dir))
    log_file = run_dir .. "/laravel_setup.log"
    return run_dir
end

local function log(msg)
    local output = "[BENCH-LARAVEL] " .. msg
    print(output)
    if log_file then
        local f = io.open(log_file, "a")
        if f then
            f:write(output .. "\n")
            f:close()
        end
    end
end

local function fail(msg)
    log("ERROR: " .. msg)
    os.exit(1)
end

setup_logging()

-- Check dependencies
log("Checking dependencies...")
if not check_command("php") then
    fail("PHP is not installed. Install PHP 8.2+")
end

if not check_command("composer") then
    fail("Composer is not installed. Install from https://getcomposer.org")
end

if not check_command("git") then
    fail("Git is not installed")
end

-- Paths
local bench_dir = os.getenv("BENCH_DIR") or "/Users/Shared/lunet/bench"
local tmp_dir = os.getenv("TMP_DIR") or "/Users/Shared/lunet/.tmp"
local laravel_dir = bench_dir .. "/laravel-app"

-- Create directories
log("Creating directories...")
run("mkdir -p " .. bench_dir)
run("mkdir -p " .. tmp_dir)

-- Check if already set up
if io.open(laravel_dir .. "/composer.json", "r") then
    log("Laravel app already cloned, skipping git clone")
else
    log("Cloning Laravel realworld example (yukicountry - Laravel 11)...")
    run("cd " .. tmp_dir .. " && git clone --depth 1 https://github.com/yukicountry/realworld-laravel-layered-architecture.git yukicountry-laravel 2>&1 | tail -5")
    
    if not io.open(tmp_dir .. "/yukicountry-laravel/composer.json", "r") then
        fail("Failed to clone Laravel repository")
    end
    
    log("Copying Laravel app to bench directory...")
    run("cp -r " .. tmp_dir .. "/yukicountry-laravel " .. laravel_dir)
end

-- Install dependencies
log("Installing Composer dependencies...")
local install_result = run("cd " .. laravel_dir .. " && composer install 2>&1 | tail -20")
if install_result:find("error", 1, true) or install_result:find("Error", 1, true) then
    log("Composer output (last lines):")
    print(install_result)
    fail("Composer install had errors")
end

-- Create .env file
log("Setting up .env file...")
local env_content = [[
APP_NAME=Conduit
APP_ENV=local
APP_KEY=
APP_DEBUG=true
APP_URL=http://localhost:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=conduit
DB_USERNAME=root
DB_PASSWORD=root

JWT_SECRET=benchmark-jwt-secret-change-in-production
]]

local env_file = io.open(laravel_dir .. "/.env", "w")
if not env_file then
    fail("Cannot create .env file")
end
env_file:write(env_content)
env_file:close()

-- Generate app key
log("Generating Laravel app key...")
run("cd " .. laravel_dir .. " && php artisan key:generate --force 2>&1")

-- Run migrations
log("Running database migrations...")
local migration_result = run("cd " .. laravel_dir .. " && php artisan migrate --force 2>&1 | tail -20")
if migration_result:find("error", 1, true) or migration_result:find("Error", 1, true) then
    log("Migration output:")
    print(migration_result)
    log("This might be ok if tables already exist")
end

log("Laravel setup complete!")
log("App location: " .. laravel_dir)
log("Setup log saved to: " .. log_file)
print("To start the dev server, run:")
print("cd " .. laravel_dir .. " && php artisan serve --port=8000")
