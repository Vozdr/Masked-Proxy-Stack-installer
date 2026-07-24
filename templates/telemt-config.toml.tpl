[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[general.links]
show = "*"
public_host = "__TELEMT_DOMAIN__"
public_port = 443

[server]
port = 443
metrics_listen = "0.0.0.0:9090"
metrics_whitelist = ["0.0.0.0/0"]

[server.api]
enabled = true
listen = "0.0.0.0:9091"
whitelist = ["127.0.0.1/32", "::1/128"]
minimal_runtime_enabled = false
minimal_runtime_cache_ttl_ms = 1000

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "__TELEMT_DOMAIN__"
mask = true
mask_host = "fake-gate"
mask_port = 443
tls_emulation = true
tls_front_dir = "tlsfront"

[access]

[access.users]
__TELEMT_BOOTSTRAP_USER__ = "__TELEMT_BOOTSTRAP_SECRET__"

[access.user_max_unique_ips]

[access.user_max_tcp_conns]

[access.user_data_quota]

[access.user_rate_limits]

[access.user_expirations]

[access.user_enabled]
__TELEMT_BOOTSTRAP_USER__ = false

[timeouts]
