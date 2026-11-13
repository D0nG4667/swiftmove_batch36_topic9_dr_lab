#!/bin/sh
# Installs lab RFC 4106 AES-256-GCM IPsec ESP SAs between GW2-LOS1-DR and both hubs
set -e
if docker ps --format '{{.Names}}' | grep -q '^clab-swiftmove-b36-dr-'; then
    PREFIX="clab-swiftmove-b36-dr-"
else
    PREFIX="swiftmove-"
fi

GW2="${PREFIX}gw2-los1-dr"
HQ="${PREFIX}hq-hub"
DR="${PREFIX}dr-hub"

generate_key() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 36
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c 'import secrets; print(secrets.token_hex(36))'
    else
        echo "[!] IPsec demo requires openssl or python3 to generate temporary keys." >&2
        exit 1
    fi
}

KEY_5G="${IPSEC_KEY_5G:-0x$(generate_key)}"
KEY_VSAT="${IPSEC_KEY_VSAT:-0x$(generate_key)}"

validate_key() {
    NAME="$1"
    KEY="$2"
    case "$KEY" in
        0x*) HEX="${KEY#0x}" ;;
        *) echo "[!] $NAME must be 0x-prefixed 36-byte RFC4106 key material." >&2; exit 1 ;;
    esac
    case "$HEX" in
        *[!0-9a-fA-F]*) echo "[!] $NAME must contain hexadecimal characters only." >&2; exit 1 ;;
    esac
    if [ "${#HEX}" -ne 72 ]; then
        echo "[!] $NAME must contain exactly 72 hexadecimal characters." >&2
        exit 1
    fi
}

validate_key "IPSEC_KEY_5G" "$KEY_5G"
validate_key "IPSEC_KEY_VSAT" "$KEY_VSAT"

echo "[*] Provisioning AES-256-GCM IPsec ESP tunnels to HQ (hq-fw-01) and DR Hub (dr-fw-01)..."

docker exec "$GW2" sh -c "
ip xfrm state flush; ip xfrm policy flush
# 5G FWA (10.20.11.10) <-> Broker 10.20.4.10
ip xfrm state add src 10.20.11.10 dst 10.20.4.10 proto esp spi 0x3611 mode transport aead 'rfc4106(gcm(aes))' $KEY_5G 128
ip xfrm state add src 10.20.4.10 dst 10.20.11.10 proto esp spi 0x3612 mode transport aead 'rfc4106(gcm(aes))' $KEY_5G 128
ip xfrm policy add src 10.20.11.10/32 dst 10.20.4.10/32 dir out tmpl src 10.20.11.10 dst 10.20.4.10 proto esp mode transport
ip xfrm policy add src 10.20.4.10/32 dst 10.20.11.10/32 dir in tmpl src 10.20.4.10 dst 10.20.11.10 proto esp mode transport

# LEO VSAT (172.20.3.2) <-> Broker 10.20.4.10
ip xfrm state add src 172.20.3.2 dst 10.20.4.10 proto esp spi 0x3621 mode transport aead 'rfc4106(gcm(aes))' $KEY_VSAT 128
ip xfrm state add src 10.20.4.10 dst 172.20.3.2 proto esp spi 0x3622 mode transport aead 'rfc4106(gcm(aes))' $KEY_VSAT 128
ip xfrm policy add src 172.20.3.2/32 dst 10.20.4.10/32 dir out tmpl src 172.20.3.2 dst 10.20.4.10 proto esp mode transport
ip xfrm policy add src 10.20.4.10/32 dst 172.20.3.2/32 dir in tmpl src 10.20.4.10 dst 172.20.3.2 proto esp mode transport
"

for HUB in "$HQ" "$DR"; do
    docker exec "$HUB" sh -c "
    ip xfrm state flush; ip xfrm policy flush
    ip xfrm state add src 10.20.11.10 dst 10.20.4.10 proto esp spi 0x3611 mode transport aead 'rfc4106(gcm(aes))' $KEY_5G 128
    ip xfrm state add src 10.20.4.10 dst 10.20.11.10 proto esp spi 0x3612 mode transport aead 'rfc4106(gcm(aes))' $KEY_5G 128
    ip xfrm policy add src 10.20.4.10/32 dst 10.20.11.10/32 dir out tmpl src 10.20.4.10 dst 10.20.11.10 proto esp mode transport
    ip xfrm policy add src 10.20.11.10/32 dst 10.20.4.10/32 dir in tmpl src 10.20.11.10 dst 10.20.4.10 proto esp mode transport

    ip xfrm state add src 172.20.3.2 dst 10.20.4.10 proto esp spi 0x3621 mode transport aead 'rfc4106(gcm(aes))' $KEY_VSAT 128
    ip xfrm state add src 10.20.4.10 dst 172.20.3.2 proto esp spi 0x3622 mode transport aead 'rfc4106(gcm(aes))' $KEY_VSAT 128
    ip xfrm policy add src 10.20.4.10/32 dst 172.20.3.2/32 dir out tmpl src 10.20.4.10 dst 172.20.3.2 proto esp mode transport
    ip xfrm policy add src 172.20.3.2/32 dst 10.20.4.10/32 dir in tmpl src 172.20.3.2 dst 10.20.4.10 proto esp mode transport
    "
done

echo "[+] AES-256-GCM IPsec ESP active across 5G FWA (SPI 0x3611) & LEO VSAT (SPI 0x3621) with HQ/DR Hub parity."
