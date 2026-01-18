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
    log_file = run_dir .. "/django_setup.log"
    return run_dir
end

local function log(msg)
    local output = "[BENCH-DJANGO] " .. msg
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

local python_cmd = nil
if check_command("python3") then
    python_cmd = "python3"
elseif check_command("python") then
    python_cmd = "python"
else
    fail("Python 3.9+ is required. Install Python 3.9+")
end

local pip_cmd = python_cmd:gsub("python", "pip")

log("Using Python: " .. python_cmd)

if not check_command("git") then
    fail("Git is not installed")
end

-- Paths
local bench_dir = os.getenv("BENCH_DIR") or "/Users/Shared/lunet/bench"
local tmp_dir = os.getenv("TMP_DIR") or "/Users/Shared/lunet/.tmp"
local django_dir = bench_dir .. "/django-app"

-- Create directories
log("Creating directories...")
run("mkdir -p " .. bench_dir)
run("mkdir -p " .. tmp_dir)

-- Check if already set up
if io.open(django_dir .. "/manage.py", "r") then
    log("Django app already cloned, skipping git clone")
else
    log("Cloning Django-Ninja realworld example (Django 5.2.1)...")
    run("cd " .. tmp_dir .. " && rm -rf django-ninja 2>/dev/null; git clone --depth 1 https://github.com/c4ffein/realworld-django-ninja.git django-ninja 2>&1 | tail -5")
    
    if not io.open(tmp_dir .. "/django-ninja/manage.py", "r") then
        fail("Failed to clone Django repository")
    end
    
    log("Copying Django app to bench directory...")
    run("cp -r " .. tmp_dir .. "/django-ninja " .. django_dir)
end

-- Create virtual environment
log("Creating Python virtual environment...")
local venv_dir = django_dir .. "/venv"
if not io.open(venv_dir .. "/bin/python", "r") then
    run(python_cmd .. " -m venv " .. venv_dir)
end

local venv_python = venv_dir .. "/bin/python"
local venv_pip = venv_dir .. "/bin/pip"

-- Upgrade pip
log("Upgrading pip...")
run(venv_pip .. " install --upgrade pip 2>&1 | tail -5")

-- Install dependencies
log("Installing Python dependencies...")
if io.open(django_dir .. "/pyproject.toml", "r") then
    log("Using pyproject.toml for dependencies...")
    run(venv_pip .. " install -e . 2>&1 | tail -20")
elseif io.open(django_dir .. "/requirements.txt", "r") then
    log("Using requirements.txt for dependencies...")
    run(venv_pip .. " install -r " .. django_dir .. "/requirements.txt 2>&1 | tail -20")
else
    fail("No pyproject.toml or requirements.txt found")
end

-- Create .env file
log("Setting up .env file...")
local env_content = [[
DEBUG=True
SECRET_KEY=benchmark-secret-key-change-in-production

DATABASE_ENGINE=django.db.backends.mysql
DATABASE_NAME=conduit
DATABASE_USER=root
DATABASE_PASSWORD=root
DATABASE_HOST=127.0.0.1
DATABASE_PORT=3306

JWT_SECRET=benchmark-jwt-secret-change-in-production
]]

local env_file = io.open(django_dir .. "/.env", "w")
if not env_file then
    fail("Cannot create .env file")
end
env_file:write(env_content)
env_file:close()

-- Run migrations
log("Running database migrations...")
local migration_result = run("cd " .. django_dir .. " && " .. venv_python .. " manage.py migrate --noinput 2>&1 | tail -20")
if migration_result:find("error", 1, true) or migration_result:find("Error", 1, true) then
    log("Migration output:")
    print(migration_result)
    log("This might be ok if tables already exist")
end

log("Django setup complete!")
log("App location: " .. django_dir)
log("Python venv: " .. venv_dir)
log("Setup log saved to: " .. log_file)
print("To start the dev server, run:")
print("cd " .. django_dir .. " && " .. venv_python .. " manage.py runserver 8001")
