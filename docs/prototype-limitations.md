# Prototype Limitations and Production Readiness

## Scope statement

This repository implements a **logical network behavior demonstration** using Linux containers, not a production-ready disaster-recovery network. The scripts can alter routes, queue disciplines, addresses, firewall rules, and kernel IPsec state inside the lab. That makes the prototype functional as a controlled experiment, but it does not make it an engineered, supported, or secured production deployment.

Use the results to generate questions and test cases. Do not treat a successful drill, screenshot, log, or packet capture as proof of physical service availability, production security, regulatory compliance, or an achieved RTO/RPO.

## What the prototype can demonstrate

- A Keepalived VRRP VIP can move between two Linux gateway containers when the tracked check reduces GW1 priority.
- `tc netem` can inject configured delay or packet loss into container WAN links.
- A separate GW2 watcher can switch example routes from 5G to VSAT after its configured probe failures and can add/remove a selected video-port drop rule.
- A manual route change can move the broker subnet from the HQ path to the warm-DR path.
- Linux firewall counters and `tcpdump` can provide observable evidence of selected packet handling and ESP traffic in this specific lab run.
- A synthetic UDP request/acknowledgement probe can record individual round-trip times and write CSV rows.

These claims are bounded to the configured virtual topology and available test outputs. They are not equivalent to application-level continuity or carrier-grade failover.

## Important implementation gaps

| Area | Current prototype behavior | Why it is not production evidence / required next step |
| --- | --- | --- |
| Physical and carrier network | Docker bridges or Containerlab links represent the segments. `tc` imposes example impairment. | No real optics, radio, satellite terminal, provider routing, shared-risk group, last-mile diversity, or carrier SLA is modeled. Validate paths, common failure domains, and service targets with providers and physical testing. |
| Gateway health tracking | GW1 executes a shell ping check through the fibre path with a backup ping target. Keepalived reduces priority after three failures. | This is not a full BFD session or a vendor NQA implementation. The script parses ping text with a simplified integer pattern and does not provide robust loss/jitter/rolling-window analysis, hysteresis, or calibrated measurement. Specify and validate detection, false-positive, and hold-down behavior on target hardware. |
| WAN selection | GW2 independently probes its 5G next hop every two seconds, uses three failures/high RTT to select VSAT, and five successes to return to 5G. | The probe is a simple ping to the adjacent WAN-core address, not an end-to-end path or application health check. Route convergence, asymmetric paths, flap behavior, provider availability, and multi-failure interactions are not exhaustively tested. |
| VRRP authentication | The shared example password was removed from the Linux and Huawei reference configurations. | The Linux lab therefore does not authenticate VRRP peers. This is acceptable only for an isolated demonstration; define and validate control-plane protections for the target platform and network. |
| Hub recovery | The drill manually takes down a WAN-core interface and replaces a route for `10.20.4.0/24`. | No automated hub service health detection, orchestration, data replication, application startup, DNS/service discovery, split-brain prevention, or failback control exists. Design and test the complete service recovery workflow. |
| Telemetry and SLA measurement | A Python sender transmits JSON over UDP to port 8883; a receiver returns a small acknowledgement. It checks each measured RTT against 150 ms. | This is not MQTT or TLS. It does not compute p95 despite the banner text, and a per-packet threshold result is not a statistical SLA. UDP delivery is not durable or guaranteed. Implement the actual protocol, security, representative traffic, and a defined measurement methodology for production. |
| Timeout/buffering output | On timeout, the probe writes labels such as `NVME_BUFFER` and `RPO_0_BUFFERED` to the console/CSV. | No NVMe device, persistent queue, replay, deduplication, or data-integrity recovery is implemented. These labels do not demonstrate buffering or RPO zero. Implement storage and recovery semantics before making such claims. |
| Privacy token | The script hashes a fixed drill identifier with a hard-coded prefix. Payload fields are synthetic. | This is not a vetted anonymization or privacy-control implementation and does not establish compliance with NDPA or any other regulation. Use approved data handling, threat modeling, retention, access control, and legal review for real personal data. |
| Firewall policy | Selected `iptables` allow/drop rules and counters are created in the Linux namespaces. Default chain policies are not a complete default-deny security posture; the 5G video test rule is added dynamically. | No full zone model, stateful policy review, comprehensive protocol coverage, anti-spoofing design, logging/alert pipeline, or adversarial test is provided. Build and independently validate a least-privilege policy on the intended platform. |
| QoS | `tc` applies example shaping and classifies selected DSCP values on container egress. | It does not prove end-to-end DSCP preservation, queue scheduling, policing, provider treatment, or application performance. Validate each hop and behavior under realistic congestion on target platforms. |
| IPsec | `enable_ipsec.sh` installs kernel XFRM ESP security associations with temporary keys generated at runtime, or supplied through environment variables. | There is no IKE negotiation, identity/authentication lifecycle, key rotation, operational monitoring, or production key management. This is a demonstration only; design and test a complete supported VPN configuration. |
| Availability and capacity | The topology has one WAN-core container and small endpoint/hub containers. | The simulator itself is a failure point and has no capacity, scale, resource contention, or availability validation. Model redundant control/forwarding components and test representative load. |
| Platform configuration | The Huawei VRP file is a separate reference and is not executed by either topology. | Syntax and feature behavior depend on device model and firmware; the file may need adaptation. Validate with the vendor documentation, parser/lab, target hardware, and change-control process. |
| Evidence and compliance | Assets include screenshots, console captures, and sample outputs. | Artifacts are records of particular lab runs, not independent acceptance results, production SLA measurements, or proof of compliance. Record test setup, software versions, timestamps, expected results, and reproducibility for formal acceptance. |

## Production-readiness gate

Do not promote this prototype directly into a live network. A physical implementation should not proceed until owners have reviewed and approved, at minimum:

- **Requirements:** business impact, service dependencies, RTO/RPO, availability, latency, loss, jitter, and capacity targets.
- **Addressing and routing:** approved IP/VLAN plan, routing protocol and policy, route filtering, return-path design, convergence, failover and failback behavior.
- **Failure-domain independence:** site power, access circuits, provider/duct diversity, cellular coverage, satellite visibility, provider upstreams, and common-mode risks.
- **Security:** default-deny firewall policy, management plane, authentication, logging, secrets/key lifecycle, VPN design, threat model, and security testing.
- **Application and data recovery:** replicated state, consistency, backup/restore, service discovery, split-brain prevention, and tested recovery order.
- **QoS and capacity:** actual traffic profiles, queue behavior, provider treatment, congestion tests, and service degradation policy.
- **Hardware/vendor validation:** exact hardware and software versions, supported features, configuration syntax, interoperability, and rollback plan.
- **Acceptance testing:** witnessed scenarios, measured packet and service outcomes, pass/fail criteria, evidence retention, and operational runbooks.

## Safe use

- Run only in an isolated lab with synthetic traffic and non-production credentials.
- Do not expose lab containers or management ports to untrusted networks.
- Do not persist or reuse the temporary IPsec keys outside the lab.
- Review every command and configuration before adapting it to physical devices.
- Treat all asset logs and screenshots as illustrative records unless independently reproduced and formally accepted.

For the architectural intent and diagrams, see [Logical design](logical-design.md). The root [README](../README.md) contains startup and drill instructions.
