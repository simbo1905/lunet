# Agent Notes: RealWorld Conduit Backend

## **Operational Rules (STRICT)**

1.  **NO RAW CURL:** Do not run `curl` directly against the server. Use `bin/test_curl.sh` which enforces timeouts and logging.
2.  **TIMEOUTS:** All commands interacting with the server or DB must have a timeout (`timeout 3` or `curl --max-time 3`).
3.  **NO DATA LOSS:** Never use `rm -rf` to clear directories. Move them to `.tmp/` with a timestamp: `mv dir .tmp/dir.YYYYMMDD_HHMMSS`.
4.  **LOGGING:** All test runs must log stdout/stderr to `.tmp/logs/YYYYMMDD_HHMMSS/`.

## MariaDB Infrastructure (Lima VM)

The project uses a MariaDB instance running in a Lima VM named `mariadb12`.
Port `3306` is forwarded to the host `127.0.0.1:3306`.

### Quick Reference

**1. Ensure VM is running:**
```bash
limactl start mariadb12
```

**2. Setup Database & Permissions (Idempotent):**
Run this if the DB is fresh or was dropped. It allows access from the macOS host (gateway IP `192.168.5.2` or `%`) and creates the `conduit` schema.
```bash
limactl shell mariadb12 sudo mariadb -e "
    CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root';
    GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
    CREATE DATABASE IF NOT EXISTS conduit;
    FLUSH PRIVILEGES;"
```

**3. Load/Reset Schema:**
Loads the application schema into the `conduit` database.
```bash
mariadb -u root -proot -h 127.0.0.1 -P 3306 --skip-ssl conduit < app/schema.sql
```

**4. Connect via Client:**
```bash
mariadb -u root -proot -h 127.0.0.1 -P 3306 --skip-ssl conduit
```

### Config for Application (`app/config.lua`)
The application connects via TCP to localhost forwarded port.
```lua
db = {
    host = "127.0.0.1",
    port = 3306,
    user = "root",
    password = "root",
    database = "conduit",
}
```
