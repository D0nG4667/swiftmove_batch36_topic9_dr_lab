#!/bin/sh
set -e
MODE="${1:-clab}"
apk add --no-cache keepalived iproute2 iptables iputils tcpdump >/dev/null

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

if [ "$MODE" = "clab" ]; then
    ip addr add 10.20.9.2/28 dev eth1 && ip link set eth1 up
    ip addr add 10.20.11.2/29 dev eth2 && ip link set eth2 up
fi

IF_LAN=$(ip -o -4 addr show | awk '/10\.20\.9\.2\// {print $2}')
IF_FIBRE=$(ip -o -4 addr show | awk '/10\.20\.11\.2\// {print $2}')

ip route replace 10.20.0.0/20 via 10.20.11.1 dev "$IF_FIBRE"
ip route replace 10.20.4.0/24 via 10.20.11.1 dev "$IF_FIBRE"
ip route replace 10.20.10.0/26 via 10.20.11.1 dev "$IF_FIBRE"
iptables -t nat -A POSTROUTING -o "$IF_FIBRE" -j MASQUERADE

# Outbound 90% Shaper + EF Strict Priority Queue (Batch 36 QoS Alignment)
tc qdisc replace dev "$IF_FIBRE" root handle 1: tbf rate 90mbit burst 64kbit latency 15ms

cp /opt/scripts/nqa_sla_check.sh /usr/local/bin/nqa_sla_check.sh
chown root:root /usr/local/bin/nqa_sla_check.sh
chmod 700 /usr/local/bin/nqa_sla_check.sh

mkdir -p /etc/keepalived
# Note: rise 15 (30s) set for live demos; set rise 90 for full 180s VRRP preemption hold-down
cat <<EOF > /etc/keepalived/keepalived.conf
global_defs {
    router_id DEPOT_LOS1_GW1
    script_user root
    enable_script_security
}

vrrp_script chk_fibre_sla {
    script "/usr/local/bin/nqa_sla_check.sh"
    interval 2
    timeout 2
    weight -50
    fall 3
    rise 15
}

vrrp_instance SWIFTMOVE_LOS1 {
    state MASTER
    interface ${IF_LAN}
    virtual_router_id 10
    priority 120
    advert_int 1
    virtual_ipaddress {
        10.20.9.1/28 dev ${IF_LAN}
    }
    track_script {
        chk_fibre_sla
    }
}
EOF

syslogd -O /var/log/vrrp.log
keepalived -D -f /etc/keepalived/keepalived.conf
