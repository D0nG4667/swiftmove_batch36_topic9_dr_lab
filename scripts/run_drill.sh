#!/bin/sh
# SwiftMove Nigeria Ltd - Batch 36 Quarterly DR Failover Drill Controller (Matches Table 2)
set -e
export MSYS_NO_PATHCONV=1

if docker ps --format '{{.Names}}' | grep -q '^clab-swiftmove-b36-dr-'; then
    PREFIX="clab-swiftmove-b36-dr-"
else
    PREFIX="swiftmove-"
fi

WAN="${PREFIX}wan-core"
GW1="${PREFIX}gw1-los1-pri"
GW2="${PREFIX}gw2-los1-dr"
EDGE="${PREFIX}edge-los1"

IF_FIBRE=$(docker exec "$WAN" sh -c "ip -o -4 addr show | awk '/10\.20\.11\.1\// {print \$2}'")
IF_5G=$(docker exec "$WAN" sh -c "ip -o -4 addr show | awk '/10\.20\.11\.9\// {print \$2}'")
IF_HQ=$(docker exec "$WAN" sh -c "ip -o -4 addr show | awk '/172\.20\.1\.1\// {print \$2}'")

ACTION="${1:-status}"

case "$ACTION" in
    baseline)
        echo "[*] Restoring Baseline: Metro Fibre=8ms (LP 200), 5G=26ms (LP 150), LEO VSAT=58ms (LP 100), Lagos HQ=.10.1"
        docker exec "$WAN" tc qdisc replace dev "$IF_FIBRE" root netem delay 8ms
        docker exec "$WAN" tc qdisc replace dev "$IF_5G" root netem delay 26ms 3ms
        docker exec "$WAN" ip link set "$IF_HQ" up
        docker exec "$WAN" ip route replace 10.20.4.0/24 via 172.20.1.2
        ;;
    fibrecut)
        echo "[Stage 1] Simulating Metro Fibre Cut: 100% loss on 10.20.11.0/28 -> VRRP shifts 10.20.9.1 to 5G FWA"
        docker exec "$WAN" tc qdisc replace dev "$IF_FIBRE" root netem loss 100%
        ;;
    brownout)
        echo "[Stage 2] Injecting 185 ms Metro Fibre Brownout (>= 150 ms NQA SLA) -> VRRP priority drops 120 to 70"
        docker exec "$WAN" tc qdisc replace dev "$IF_FIBRE" root netem delay 185ms 6ms
        ;;
    vsat-cascade)
        echo "[Stage 3] Disabling Metro Fibre & 5G FWA -> Cascades to LEO VSAT (LP 100) & revokes UDP 9000 video"
        docker exec "$WAN" tc qdisc replace dev "$IF_FIBRE" root netem loss 100%
        docker exec "$WAN" tc qdisc replace dev "$IF_5G" root netem loss 100%
        echo "[*] Waiting 7s for 3 failed NQA probes on 5G FWA..."
        sleep 7
        echo "[*] Testing unauthorised RTSP (554) and revoked SRT (9000) video drops from Drone 10.20.5.10:"
        docker exec "$EDGE" python3 /opt/scripts/telemetry_probe.py --test-video-blocks
        docker exec "$GW2" iptables -L FORWARD -v -n
        ;;
    hub-cutover)
        echo "[Stage 4] Isolating Lagos HQ Loopback 10.20.10.1/32 -> Re-homing Broker 10.20.4.10 to Warm DR Hub 10.20.10.2/32"
        docker exec "$WAN" ip link set "$IF_HQ" down
        docker exec "$WAN" ip route replace 10.20.4.0/24 via 172.20.2.2
        ;;
    status)
        echo "=== DEPOT-LOS1-GW1 (10.20.9.2/28 | Primary Fibre LP 200) ==="
        docker exec "$GW1" ip -4 addr show | grep -E "10\.20\.9\."
        docker exec "$GW1" tail -n 6 /var/log/vrrp.log
        echo ""
        echo "=== DEPOT-LOS1-GW2 (10.20.9.3/28 | 5G LP 150 & LEO VSAT LP 100) ==="
        docker exec "$GW2" ip -4 addr show | grep -E "10\.20\.9\."
        docker exec "$GW2" tail -n 6 /var/log/vrrp.log
        ;;
    *)
        echo "Usage: $0 {baseline|fibrecut|brownout|vsat-cascade|hub-cutover|status}"
        exit 1
        ;;
esac
