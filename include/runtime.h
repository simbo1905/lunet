#ifndef RUNTIME_H
#define RUNTIME_H

// Global runtime configuration flags
typedef struct {
    int dangerously_skip_loopback_restriction;
} lunet_runtime_config_t;

extern lunet_runtime_config_t g_lunet_config;

#endif // RUNTIME_H
