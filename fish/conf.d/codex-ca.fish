# Codex TLS trust anchor: ISRG Root YR (Let's Encrypt's Gen-Y root, 2025-2045).
#
# Why this exists: codex's HTTP stack is rustls-based and only trusts roots it
# finds in the platform store. macOS has not shipped Root YR yet, and rustls
# will NOT accept the cross-signed path (Root YR signed by ISRG Root X1) that
# servers send in their chain — OpenSSL/curl/Node do, which is why only codex
# failed. Any host on a Gen-Y LE cert dies with a bare transport error:
#   "http/request failed: error sending request for url (...)"
# with error_is_connect=true and NO cert-specific message. Observed 2026-08-08
# on assistant.ai.miccust.dev (MCP startup); it is not an auth or config fault.
#
# CODEX_CA_CERTIFICATE is ADDITIVE to the native roots (verified) and scoped to
# codex only — unlike SSL_CERT_FILE, which would repoint curl/python/git too.
#
# Cert is the official self-signed root from https://letsencrypt.org/certs/gen-y/root-yr.pem
# SHA256 E5:7B:7E:6F:15:0C:41:91:02:E8:D5:C0:55:72:9F:F9:67:B9:D1:A8:29:BF:00:CE:C8:9C:A6:04:EB:F4:A8:6F
# Drop this file once macOS ships Root YR in the system keychain.
if test -f ~/.config/ca/isrg-root-yr.pem
    set -gx CODEX_CA_CERTIFICATE ~/.config/ca/isrg-root-yr.pem
end
