#!/bin/sh
set -e
MODE="${1:-clab}"
apk add --no-cache iproute2 iputils iptables tcpdump >/dev/null

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

if [ "$MODE" = "clab" ]; then
    ip addr add 10.20.11.1/29 dev eth1 && ip link set eth1 up
    ip addr add 10.20.11.9/29 dev eth2 && ip link set eth2 up
    ip addr add 172.20.3.1/29 dev eth3 && ip link set eth3 up
    ip addr add 172.20.1.1/29 dev eth4 && ip link set eth4 up
    ip addr add 172.20.2.1/29 dev eth5 && ip link set eth5 up
fi

# Route HQ Loopback (10.20.10.1/32) and HQ Ops Broker/Media (10.20.4.0/24) to HQ Hub by default
ip route replace 10.20.10.1/32 via 172.20.1.2
ip route replace 10.20.10.2/32 via 172.20.2.2
ip route replace 10.20.4.0/24 via 172.20.1.2

# Return routes back to Lagos-1 Depot (10.20.9.0/28) & Mobile Stubs
ip route replace 10.20.9.0/28 via 10.20.11.2 metric 10
ip route add 10.20.9.0/28 via 10.20.11.10 metric 20 2>/dev/null || true
ip route add 10.20.9.0/28 via 172.20.3.2 metric 30 2>/dev/null || true

IF_FIBRE=$(ip -o -4 addr show | awk '/10\.20\.11\.1\// {print $2}')
IF_5G=$(ip -o -4 addr show | awk '/10\.20\.11\.9\// {print $2}')
IF_VSAT=$(ip -o -4 addr show | awk '/172\.20\.3\.1\// {print $2}')

# Baseline Nigerian WAN link profiles (aligned with Table 1)
# Tier 1: Metro Fibre -> ~8 ms RTT (4-12 ms window)
tc qdisc replace dev "$IF_FIBRE" root netem delay 8ms
# Tier 2: 5G Sub-6 GHz n78 FWA -> ~26 ms RTT with 3 ms jitter (18-35 ms window)
tc qdisc replace dev "$IF_5G" root netem delay 26ms 3ms
# Tier 3: Ku/Ka LEO VSAT (Lagos PoP) -> ~58 ms RTT with 5 ms jitter (50-66 ms window)
tc qdisc replace dev "$IF_VSAT" root netem delay 58ms 5ms rate 2mbit
