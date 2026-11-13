#!/bin/sh
# Runs 2s NQA tunnel probes on 5G FWA (10.20.11.9); after 3 lost/high-RTT probes (6s), cascades to LEO VSAT (172.20.3.1)
# Also enforces SDN revocation of AF41 UDP 9000 SRT high-definition video on degraded VSAT fallback
IF_5G=$(ip -o -4 addr show | awk '/10\.20\.11\.10\// {print $2}')
IF_VSAT=$(ip -o -4 addr show | awk '/172\.20\.3\.2\// {print $2}')
ACTIVE="5G"
FAILS=0
GOODS=0

while true; do
    OUT=$(ping -I 10.20.11.10 -c 1 -W 1 10.20.11.9 2>/dev/null)
    RC=$?
    RTT=$(echo "$OUT" | sed -n 's/.*time=\([0-9]*\).*/\1/p')
    if [ $RC -ne 0 ] || [ -z "$RTT" ] || [ "$RTT" -ge 150 ]; then
        FAILS=$((FAILS + 1))
        GOODS=0
        if [ "$ACTIVE" = "5G" ] && [ $FAILS -ge 3 ]; then
            ip route replace 10.20.0.0/20 via 172.20.3.1 dev "$IF_VSAT"
            ip route replace 10.20.4.0/24 via 172.20.3.1 dev "$IF_VSAT"
            ip route replace 10.20.10.0/26 via 172.20.3.1 dev "$IF_VSAT"
            iptables -C FORWARD -p udp --dport 9000 -j DROP 2>/dev/null || iptables -I FORWARD 1 -p udp --dport 9000 -j DROP
            logger -t SDN-DR-CASCADE "3 NQA probes failed on 5G FWA; shifted to LEO VSAT (LP 100) and revoked UDP 9000 AF41 video tag"
            ACTIVE="VSAT"
        fi
    else
        GOODS=$((GOODS + 1))
        FAILS=0
        if [ "$ACTIVE" = "VSAT" ] && [ $GOODS -ge 5 ]; then
            ip route replace 10.20.0.0/20 via 10.20.11.9 dev "$IF_5G"
            ip route replace 10.20.4.0/24 via 10.20.11.9 dev "$IF_5G"
            ip route replace 10.20.10.0/26 via 10.20.11.9 dev "$IF_5G"
            iptables -D FORWARD -p udp --dport 9000 -j DROP 2>/dev/null || true
            logger -t SDN-DR-CASCADE "5G FWA healthy (${RTT}ms); restored LP 150 5G FWA route"
            ACTIVE="5G"
        fi
    fi
    sleep 2
done
