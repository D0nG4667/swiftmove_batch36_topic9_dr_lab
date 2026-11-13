#!/bin/sh
set -e
MODE="${1:-clab}"
apk add --no-cache keepalived iproute2 iptables iputils tcpdump >/dev/null

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true

if [ "$MODE" = "clab" ]; then
    ip addr add 10.20.9.3/28 dev eth1 && ip link set eth1 up
    ip addr add 10.20.11.10/29 dev eth2 && ip link set eth2 up
    ip addr add 172.20.3.2/29 dev eth3 && ip link set eth3 up
fi

IF_LAN=$(ip -o -4 addr show | awk '/10\.20\.9\.3\// {print $2}')
IF_5G=$(ip -o -4 addr show | awk '/10\.20\.11\.10\// {print $2}')
IF_VSAT=$(ip -o -4 addr show | awk '/172\.20\.3\.2\// {print $2}')

# Default DR path: 5G Sub-6 FWA (LP 150); fallback: LEO VSAT (LP 100)
ip route replace 10.20.0.0/20 via 10.20.11.9 dev "$IF_5G"
ip route replace 10.20.4.0/24 via 10.20.11.9 dev "$IF_5G"
ip route replace 10.20.10.0/26 via 10.20.11.9 dev "$IF_5G"
iptables -t nat -A POSTROUTING -o "$IF_5G" -j MASQUERADE
iptables -t nat -A POSTROUTING -o "$IF_VSAT" -j MASQUERADE

# Illustrative forwarding rules:
# Permit TCP/UDP 8883 (telemetry probe -> 10.20.4.10) & UDP 14550 (MAVLink)
# Explicitly DROP unauthorised RTSP/RTMP/RTP video (554, 8554, 1935, 5004)
iptables -A FORWARD -p udp --dport 8883 -d 10.20.4.10 -j ACCEPT
iptables -A FORWARD -p tcp --dport 8883 -d 10.20.4.10 -j ACCEPT
iptables -A FORWARD -p udp --dport 14550 -j ACCEPT
iptables -A FORWARD -p icmp -j ACCEPT
for PORT in 554 8554 5004; do
    iptables -A FORWARD -p udp --dport "$PORT" -j DROP
    iptables -A FORWARD -p tcp --dport "$PORT" -j DROP
done
iptables -A FORWARD -p tcp --dport 1935 -j DROP

# Outbound 90% Shaping + Strict Priority EF Queue (9 Mbit/s on 5G; 1.8 Mbit/s floor on LEO VSAT)
tc qdisc replace dev "$IF_5G" root handle 1: htb default 20
tc class add dev "$IF_5G" parent 1: classid 1:1 htb rate 9mbit ceil 9mbit
tc class add dev "$IF_5G" parent 1:1 classid 1:10 htb rate 1800kbit ceil 1800kbit prio 0
tc class add dev "$IF_5G" parent 1:1 classid 1:20 htb rate 7200kbit ceil 9mbit prio 2
tc filter add dev "$IF_5G" protocol ip parent 1:0 prio 1 u32 match ip tos 0xb8 0xfc flowid 1:10

tc qdisc replace dev "$IF_VSAT" root handle 1: htb default 20
tc class add dev "$IF_VSAT" parent 1: classid 1:1 htb rate 1800kbit ceil 1800kbit
tc class add dev "$IF_VSAT" parent 1:1 classid 1:10 htb rate 360kbit ceil 360kbit prio 0
tc class add dev "$IF_VSAT" parent 1:1 classid 1:20 htb rate 1440kbit ceil 1800kbit prio 2
tc filter add dev "$IF_VSAT" protocol ip parent 1:0 prio 1 u32 match ip tos 0xb8 0xfc flowid 1:10

mkdir -p /etc/keepalived
cat <<EOF > /etc/keepalived/keepalived.conf
global_defs {
    router_id DEPOT_LOS1_GW2
}

vrrp_instance SWIFTMOVE_LOS1 {
    state BACKUP
    interface ${IF_LAN}
    virtual_router_id 10
    priority 100
    advert_int 1
    virtual_ipaddress {
        10.20.9.1/28 dev ${IF_LAN}
    }
}
EOF

syslogd -O /var/log/vrrp.log
keepalived -D -f /etc/keepalived/keepalived.conf
nohup sh /opt/scripts/dr_uplink_watch.sh >/dev/null 2>&1 &
