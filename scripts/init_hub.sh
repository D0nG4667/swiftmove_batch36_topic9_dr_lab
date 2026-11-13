#!/bin/sh
set -e
MODE="${1:-clab}"
ROLE="${2:-hq}"
apk add --no-cache python3 iproute2 iputils iptables tcpdump >/dev/null

if [ "$ROLE" = "hq" ]; then
    if [ "$MODE" = "clab" ]; then
        ip addr add 172.20.1.2/29 dev eth1 && ip link set eth1 up
    fi
    ip addr add 10.20.10.1/32 dev lo 2>/dev/null || true
    ip addr add 10.20.4.10/24 dev lo 2>/dev/null || true
    ip addr add 10.20.4.20/24 dev lo 2>/dev/null || true
    ip route replace default via 172.20.1.1
    HUB_NAME="LAGOS-HQ (10.20.10.1 | hq-fw-01)"
else
    if [ "$MODE" = "clab" ]; then
        ip addr add 172.20.2.2/29 dev eth1 && ip link set eth1 up
    fi
    ip addr add 10.20.10.2/32 dev lo 2>/dev/null || true
    ip addr add 10.20.4.10/24 dev lo 2>/dev/null || true
    ip addr add 10.20.4.20/24 dev lo 2>/dev/null || true
    ip route replace default via 172.20.2.1
    HUB_NAME="WARM-DR-HUB (10.20.10.2 | dr-fw-01)"
fi

# Transactional SDN Firewall Parity across hq-fw-01 and dr-fw-01 (Batch 36 Topic 4 & Topic 9)
iptables -F INPUT
# Rule 1: Permit MQTT/TLS Telemetry (TCP/UDP 8883) to Broker 10.20.4.10
iptables -A INPUT -p tcp --dport 8883 -d 10.20.4.10 -j ACCEPT
iptables -A INPUT -p udp --dport 8883 -d 10.20.4.10 -j ACCEPT
# Rule 2: Permit MAVLink Command/Telemetry (UDP 14550)
iptables -A INPUT -p udp --dport 14550 -j ACCEPT
# Rule 3: Permit Authorised SRT Mission Video (UDP 9000) to Media Gateway 10.20.4.20
iptables -A INPUT -p udp --dport 9000 -d 10.20.4.20 -j ACCEPT
# Rule 4: Explicitly Block & Log Unauthorised RTSP/RTMP/RTP Video (554, 8554, 1935, 5004)
for PORT in 554 8554 5004; do
    iptables -A INPUT -p udp --dport "$PORT" -j DROP
    iptables -A INPUT -p tcp --dport "$PORT" -j DROP
done
iptables -A INPUT -p tcp --dport 1935 -j DROP
iptables -A INPUT -p icmp -j ACCEPT

nohup python3 /opt/scripts/telemetry_probe.py --role receiver --hub-name "$HUB_NAME" >/var/log/hub_broker.log 2>&1 &
