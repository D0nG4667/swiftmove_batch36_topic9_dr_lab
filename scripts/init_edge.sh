#!/bin/sh
set -e
MODE="${1:-clab}"
apk add --no-cache python3 iproute2 iputils tcpdump >/dev/null

if [ "$MODE" = "clab" ]; then
    ip addr add 10.20.9.10/28 dev eth1 && ip link set eth1 up
fi

# Add Batch 36 virtual stub loopbacks representing Drone Pool (10.20.5.0/25) & Truck Pool (10.20.0.0/22)
ip addr add 10.20.5.10/32 dev lo 2>/dev/null || true
ip addr add 10.20.0.10/32 dev lo 2>/dev/null || true

# Default route points to VRRP Virtual IP 10.20.9.1 (Lagos-1 Depot Edge subnet 10.20.9.0/28)
ip route replace default via 10.20.9.1
