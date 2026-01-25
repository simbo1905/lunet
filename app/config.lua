local db_config = require("app.db_config")

-- Read env vars using os.getenv
-- Supports:
--   unix://path/to/socket
--   tcp://127.0.0.1:8080
--   127.0.0.1:8080 (implicit tcp)
local listen_addr = os.getenv("LUNET_LISTEN") or "tcp://127.0.0.1:8080"

return {
    db = db_config,
    server = {
        listen = listen_addr,
    },
    jwt_secret = "change-me-in-production-use-random-32-bytes",
    jwt_expiry = 86400 * 7,
}
