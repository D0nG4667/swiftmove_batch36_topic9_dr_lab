# Appendix

## Sample Container-Lab DR Drill Records

The captures below are sample records from runs of the containerized Batch 36 Lagos Depot 1 topology (`10.20.9.0/28`, VRRP virtual IP `10.20.9.1`). The lab uses Keepalived VRRP, Linux `tc netem` WAN impairment, `iptables` packet filtering, and optional kernel IPsec ESP security associations with temporary lab keys.

**Project application.** This logical design applies to SwiftMove Nigeria's Lagos operations: Lagos Depot 1 is the protected edge site, Primary Lagos HQ (`10.20.10.1`) is the normal hub destination, and the warm DR hub (`10.20.10.2`) is the alternate destination. The drill notes below describe how the depot's WAN and hub paths are intended to behave; they do not represent a validated physical deployment.

The telemetry program sends synthetic JSON over UDP to port `8883`; its receiver returns a simple acknowledgement. It is not an MQTT/TLS broker. The token printed by the script is generated from a fixed demonstration identifier and prefix; it is not a validated privacy or regulatory control. These logs and figures document example lab behavior only. They are not independent acceptance results, physical-network SLA measurements, proof of RPO/RTO, or evidence of regulatory compliance.

**Figure A1**
*Stage 1 Primary Metro Fibre Cut (`10.20.11.0/28`) Triggering VRRP Priority Decrement (`120` to `70`) and Switchover to 5G FWA*

```text
hp@DonGabbys-EliteBook MINGW64 ~/Desktop/gab/MIVA/MIT8105/swiftmove_batch36_topic9_dr_lab
$ ./scripts/run_drill.sh fibrecut && sleep 16 && ./scripts/run_drill.sh status
[Stage 1] Simulating Metro Fibre Cut: 100% loss on 10.20.11.0/28 -> VRRP shifts 10.20.9.1 to 5G FWA
=== DEPOT-LOS1-GW1 (10.20.9.2/28 | Primary Fibre LP 200) ===
    inet 10.20.9.2/28 brd 10.20.9.15 scope global eth0
Nov 12 22:51:53 6010575e0fd0 daemon.info Keepalived_vrrp[10098]: Script `chk_fibre_sla` now returning 1
Nov 12 22:52:01 6010575e0fd0 daemon.info Keepalived_vrrp[10098]: VRRP_Script(chk_fibre_sla) failed (exited with status 1)
Nov 12 22:52:01 6010575e0fd0 daemon.info Keepalived_vrrp[10098]: (SWIFTMOVE_LOS1) Changing effective priority from 120 to 70
Nov 12 22:52:04 6010575e0fd0 daemon.info Keepalived_vrrp[10098]: (SWIFTMOVE_LOS1) Master received advert from 10.20.9.3 with higher priority 100, ours 70
Nov 12 22:52:04 6010575e0fd0 daemon.info Keepalived_vrrp[10098]: (SWIFTMOVE_LOS1) Entering BACKUP STATE
Nov 12 22:52:04 6010575e0fd0 daemon.info Keepalived_vrrp[10098]: (SWIFTMOVE_LOS1) removing VIPs.

=== DEPOT-LOS1-GW2 (10.20.9.3/28 | 5G LP 150 & LEO VSAT LP 100) ===
    inet 10.20.9.3/28 brd 10.20.9.15 scope global eth0
    inet 10.20.9.1/28 scope global secondary eth0
Nov 12 22:52:09 622dc195a01e daemon.info Keepalived_vrrp[55]: (SWIFTMOVE_LOS1) Sending/queueing gratuitous ARPs on eth0 for 10.20.9.1
Nov 12 22:52:09 622dc195a01e daemon.info Keepalived_vrrp[55]: Sending gratuitous ARP on eth0 for 10.20.9.1
Nov 12 22:52:09 622dc195a01e daemon.info Keepalived_vrrp[55]: Sending gratuitous ARP on eth0 for 10.20.9.1
```

*Note.* In the SwiftMove Lagos-1 design, this stage represents loss of the depot's primary Metro Fibre path toward Primary Lagos HQ. In this sample, the GW1 tracking script reports failure, Keepalived reduces effective priority from `120` to `70`, and GW2 (`10.20.9.3/28`, priority `100`) takes the `10.20.9.1/28` virtual address and sends gratuitous ARP so the depot can use its DR gateway. Timing depends on the container run and is not a convergence guarantee.

**Figure A2**
*Stage 2 Metro Fibre Brownout (`185 ms` Delay) Breaching the `150 ms` NQA Ceiling and Shifting `10.20.9.1/28` to `DEPOT-LOS1-GW2`*

```text
hp@DonGabbys-EliteBook MINGW64 ~/Desktop/gab/MIVA/MIT8105/swiftmove_batch36_topic9_dr_lab
$ ./scripts/run_drill.sh brownout && sleep 8 && ./scripts/run_drill.sh status
[Stage 2] Injecting 185 ms Metro Fibre Brownout (>= 150 ms NQA SLA) -> VRRP priority drops 120 to 70
=== DEPOT-LOS1-GW1 (10.20.9.2/28 | Primary Fibre LP 200) ===
    inet 10.20.9.2/28 brd 10.20.9.15 scope global eth0
Nov 12 22:11:45 6010575e0fd0 daemon.info Keepalived_vrrp[34]: (SWIFTMOVE_LOS1) Entering BACKUP STATE
Nov 12 22:11:45 6010575e0fd0 daemon.info Keepalived_vrrp[34]: (SWIFTMOVE_LOS1) removing VIPs.
Nov 12 22:11:46 6010575e0fd0 user.notice NQA-SLA: SLA BREACH on Metro Fibre (10.20.11.2): RTT=183ms >= 150ms ceiling
Nov 12 22:11:48 6010575e0fd0 user.notice NQA-SLA: SLA BREACH on Metro Fibre (10.20.11.2): RTT=187ms >= 150ms ceiling
Nov 12 22:11:50 6010575e0fd0 user.notice NQA-SLA: SLA BREACH on Metro Fibre (10.20.11.2): RTT=190ms >= 150ms ceiling
Nov 12 22:11:52 6010575e0fd0 user.notice NQA-SLA: SLA BREACH on Metro Fibre (10.20.11.2): RTT=190ms >= 150ms ceiling

=== DEPOT-LOS1-GW2 (10.20.9.3/28 | 5G LP 150 & LEO VSAT LP 100) ===
    inet 10.20.9.3/28 brd 10.20.9.15 scope global eth0
    inet 10.20.9.1/28 scope global secondary eth0
Nov 12 22:11:50 622dc195a01e daemon.info Keepalived_vrrp[55]: (SWIFTMOVE_LOS1) Sending/queueing gratuitous ARPs on eth0 for 10.20.9.1
Nov 12 22:11:50 622dc195a01e daemon.info Keepalived_vrrp[55]: Sending gratuitous ARP on eth0 for 10.20.9.1
Nov 12 22:11:50 622dc195a01e daemon.info Keepalived_vrrp[55]: Sending gratuitous ARP on eth0 for 10.20.9.1
```

*Note.* For the Lagos-1 Depot to Primary Lagos HQ path, this stage represents a degraded-but-up primary circuit. Although the simulated interface remains up, the sample shows measured ping RTT values between `183 ms` and `190 ms` against the configured `150 ms` threshold, followed by GW1 entering `BACKUP STATE`. This is a simple lab check, not a statistical SLA measurement or vendor NQA result.

**Figure A3**
*Stage 3 Dual Terrestrial Outage Cascading to LEO VSAT (`LP 100`) with `AF41` Video Tag Revocation and `RTSP` Filtering*

```text
hp@DonGabbys-EliteBook MINGW64 ~/Desktop/gab/MIVA/MIT8105/swiftmove_batch36_topic9_dr_lab
$ ./scripts/run_drill.sh vsat-cascade
[Stage 3] Disabling Metro Fibre & 5G FWA -> Cascades to LEO VSAT (LP 100) & revokes UDP 9000 video
[*] Waiting 7s for 3 failed NQA probes on 5G FWA...
Nov 12 22:30:14 622dc195a01e user.notice SDN-DR-CASCADE: 3 NQA probes failed on 5G FWA; shifted to LEO VSAT (LP 100) and revoked UDP 9000 AF41 video tag
[*] Testing unauthorised RTSP (554) and revoked SRT (9000) video drops from Drone 10.20.5.10:
[VIDEO-TEST #1] Sent RTSP (UDP 554) & SRT HD Video (UDP 9000 / AF41)
[VIDEO-TEST #2] Sent RTSP (UDP 554) & SRT HD Video (UDP 9000 / AF41)
[VIDEO-TEST #3] Sent RTSP (UDP 554) & SRT HD Video (UDP 9000 / AF41)
Chain FORWARD (policy ACCEPT 3 packets, 147 bytes)
 pkts bytes target     prot opt in     out     source               destination
    3   147 DROP       17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:9000
 1485  286K ACCEPT     17   --  *      *       0.0.0.0/0            10.20.4.10           udp dpt:8883
    0     0 ACCEPT     6    --  *      *       0.0.0.0/0            10.20.4.10           tcp dpt:8883
    0     0 ACCEPT     17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:14550
    0     0 ACCEPT     1    --  *      *       0.0.0.0/0            0.0.0.0/0
    6   306 DROP       17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:554
    0     0 DROP       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:554
    0     0 DROP       17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:8554
    0     0 DROP       17   --  *      *       0.0.0.0/0            0.0.0.0/0            udp dpt:5004
    0     0 DROP       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:1935
```

*Note.* This stage represents a compound outage affecting the Lagos-1 Depot's Metro Fibre and 5G paths toward the Lagos hub services. After three failed 5G FWA probes, the watcher shifts example routes to the tertiary LEO VSAT link (`172.20.3.2`) and inserts a top-level `DROP` rule on `UDP 9000` (`3` packets, `147` bytes dropped). The sample also shows `UDP 554` packets dropped and matching `UDP 8883` packets accepted toward `10.20.4.10`. The latter are synthetic UDP probe/acknowledgement datagrams, not MQTT messages.

**Figure A4**
*Stage 4 Primary Lagos HQ (`10.20.10.1/32`) Isolation, Warm DR Hub (`10.20.10.2/32`) Cutover, and `AES-256-GCM` ESP Packet Capture*

```text
hp@DonGabbys-EliteBook MINGW64 ~/Desktop/gab/MIVA/MIT8105/swiftmove_batch36_topic9_dr_lab
$ ./scripts/enable_ipsec.sh
[*] Provisioning AES-256-GCM IPsec ESP tunnels to HQ (hq-fw-01) and DR Hub (dr-fw-01)...
[+] AES-256-GCM IPsec ESP active across 5G FWA (SPI 0x3611) & LEO VSAT (SPI 0x3621) with HQ/DR Hub parity.

hp@DonGabbys-EliteBook MINGW64 ~/Desktop/gab/MIVA/MIT8105/swiftmove_batch36_topic9_dr_lab
$ ./scripts/run_drill.sh hub-cutover && docker exec swiftmove-dr-hub tcpdump -ni any esp -c 5
[Stage 4] Isolating Lagos HQ Loopback 10.20.10.1/32 -> Re-homing Broker 10.20.4.10 to Warm DR Hub 10.20.10.2/32
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes
22:41:28.995500 eth0  In  IP 172.20.3.2 > 10.20.4.10: ESP(spi=0x00003621,seq=0x15b), length 208
22:41:31.199879 eth0  In  IP 172.20.3.2 > 10.20.4.10: ESP(spi=0x00003621,seq=0x15c), length 208
22:41:33.402028 eth0  In  IP 172.20.3.2 > 10.20.4.10: ESP(spi=0x00003621,seq=0x15d), length 208
22:41:35.605048 eth0  In  IP 172.20.3.2 > 10.20.4.10: ESP(spi=0x00003621,seq=0x15e), length 208
22:41:37.808471 eth0  In  IP 172.20.3.2 > 10.20.4.10: ESP(spi=0x00003621,seq=0x15f), length 208
5 packets captured
5 packets received by filter
0 packets dropped by kernel
```

*Note.* This stage represents loss of Primary Lagos HQ and a manual re-route of the Lagos-1 Depot's broker traffic to the warm DR hub. The sample shows five ESP frames on the DR hub capture (`spi=0x00003621`, sequence values `0x15b` through `0x15f`, `208` bytes) and zero kernel packet drops during that capture. It demonstrates ESP traffic in this particular lab run; it does not validate production cryptographic configuration, key management, end-to-end application recovery, or security suitability. The script generates temporary lab key material and must not be used as-is outside the lab.
