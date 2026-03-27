#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TLS_DIR="${REPO_ROOT}/.state/rdp-tls"
CA_KEY="${TLS_DIR}/ca.key"
CA_CERT="${TLS_DIR}/ca.crt"
SERVER_KEY="${TLS_DIR}/server.key"
SERVER_CSR="${TLS_DIR}/server.csr"
SERVER_CERT="${TLS_DIR}/server.crt"
SERVER_EXT="${TLS_DIR}/server.ext"
OPENSSL_CNF="${TLS_DIR}/openssl.cnf"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
CA_SUBJECT="${POB_RDP_CA_SUBJECT:-/CN=POB Local RDP Root CA}"
SERVER_SUBJECT="${POB_RDP_SERVER_SUBJECT:-/CN=localhost}"
force=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      force=1
      ;;
    *)
      printf 'Usage: %s [--force]\n' "$0" >&2
      exit 1
      ;;
  esac
  shift
done

mkdir -p "$TLS_DIR"

if [[ "$force" -eq 1 ]]; then
  rm -f "$CA_KEY" "$CA_CERT" "$SERVER_KEY" "$SERVER_CSR" "$SERVER_CERT" "$SERVER_EXT" "$OPENSSL_CNF"
fi

cat >"$OPENSSL_CNF" <<'EOF'
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca
prompt = no

[ req_distinguished_name ]
CN = POB Local RDP Root CA

[ v3_ca ]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
EOF

cat >"$SERVER_EXT" <<'EOF'
basicConstraints=CA:FALSE
keyUsage=digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=@alt_names

[alt_names]
DNS.1=localhost
IP.1=127.0.0.1
IP.2=::1
EOF

if [[ ! -f "$CA_KEY" || ! -f "$CA_CERT" ]]; then
  openssl req -x509 -nodes -newkey rsa:4096 \
    -days 3650 \
    -keyout "$CA_KEY" \
    -out "$CA_CERT" \
    -config "$OPENSSL_CNF" \
    -subj "$CA_SUBJECT"
fi

if [[ ! -f "$SERVER_KEY" || ! -f "$SERVER_CERT" ]]; then
  openssl req -nodes -newkey rsa:2048 \
    -keyout "$SERVER_KEY" \
    -out "$SERVER_CSR" \
    -subj "$SERVER_SUBJECT"

  openssl x509 -req \
    -in "$SERVER_CSR" \
    -CA "$CA_CERT" \
    -CAkey "$CA_KEY" \
    -CAcreateserial \
    -out "$SERVER_CERT" \
    -days 825 \
    -sha256 \
    -extfile "$SERVER_EXT"
fi

chmod 0600 "$CA_KEY" "$SERVER_KEY"
chmod 0644 "$CA_CERT" "$SERVER_CERT"

if ! security find-certificate -a -c "POB Local RDP Root CA" "$KEYCHAIN" >/dev/null 2>&1; then
  security add-trusted-cert -d -r trustRoot -k "$KEYCHAIN" "$CA_CERT"
fi

printf 'RDP CA: %s\n' "$CA_CERT"
printf 'RDP cert: %s\n' "$SERVER_CERT"
openssl x509 -in "$SERVER_CERT" -noout -subject -issuer -dates -fingerprint -sha256
