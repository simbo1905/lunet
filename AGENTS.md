# Agent Notes

## MariaDB Database Server

Database runs in a Lima VM named `mariadb12`.

### Start the VM
```bash
limactl start mariadb12
```

### Load schema
```bash
mariadb -u root -proot -h 127.0.0.1 -P 3306 < /Users/Shared/lunet/app/schema.sql
```

### Connect
```bash
mariadb -u root -proot -h 127.0.0.1 -P 3306
```

### Stop the VM
```bash
limactl stop mariadb12
```
