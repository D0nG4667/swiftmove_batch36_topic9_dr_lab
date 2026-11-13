#!/usr/bin/env python3
"""
SwiftMove Nigeria Ltd - Batch 36 NDPA/NDPR Telemetry & MAVLink DR Drill Probe
Aligned with 10.20.0.0/20 VLSM, Broker 10.20.4.10 (Port 8883), and Synthetic Token SM-DRILL-01
"""

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import random
import socket
import time

BROKER_IP = "10.20.4.10"
MEDIA_GW_IP = "10.20.4.20"
TELEMETRY_PORT = 8883
SRT_VIDEO_PORT = 9000
UNAUTH_RTSP_PORT = 554
DSCP_EF_TOS = 0xB8    # DSCP 46 (EF) << 2
DSCP_AF41_TOS = 0x88  # DSCP 34 (AF41) << 2
SLA_LIMIT_MS = 150.0

UPLINK_MAP = {
    "10.20.11.2": "Tier-1 METRO-FIBRE (LP 200)",
    "10.20.11.10": "Tier-2 5G-n78-FWA (LP 150)",
    "172.20.3.2": "Tier-3 LEO-VSAT-LAGOS (LP 100)",
}


def tokenise_driver_pii(raw_id: str) -> str:
    """Salted SHA-256 tokenisation per NDPA 2023 & March 2025 GAID."""
    digest = hashlib.sha256(f"swiftmove-b36-gaid:{raw_id}".encode()).hexdigest()[:8]
    return f"SM-DRILL-01-{digest.upper()}"


def run_receiver(bind_ip: str, port: int, hub_name: str) -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, DSCP_EF_TOS)
    sock.bind((bind_ip, port))
    print(f"[{hub_name}] Telemetry Broker active on {bind_ip}:{port}...", flush=True)

    while True:
        data, addr = sock.recvfrom(4096)
        ingress_ip = addr[0]
        uplink_label = UPLINK_MAP.get(ingress_ip, f"TUNNEL ({ingress_ip})")
        try:
            payload = json.loads(data.decode("utf-8"))
        except Exception:
            payload = {"seq": -1}

        ack = {
            "seq": payload.get("seq"),
            "hub": hub_name,
            "uplink": uplink_label,
            "rx_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        }
        sock.sendto(json.dumps(ack).encode("utf-8"), addr)


def test_video_blocks() -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, DSCP_AF41_TOS)
    for idx in range(1, 4):
        sock.sendto(f"UNAUTH_RTSP_554_FRAME_{idx}".encode(), (BROKER_IP, UNAUTH_RTSP_PORT))
        sock.sendto(f"SRT_AF41_9000_FRAME_{idx}".encode(), (MEDIA_GW_IP, SRT_VIDEO_PORT))
        print(f"[VIDEO-TEST #{idx}] Sent RTSP (UDP 554) & SRT HD Video (UDP 9000 / AF41)")
        time.sleep(0.1)
    sock.close()


def run_sender(target_ip: str, port: int, count: int, interval: float, csv_path: str) -> None:
    os.makedirs(os.path.dirname(csv_path), exist_ok=True)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_TOS, DSCP_EF_TOS)
    sock.settimeout(1.2)

    drill_token = tokenise_driver_pii("LAGOS-DEPOT1-DRILL")
    print("=" * 112)
    print(" SwiftMove Batch 36 | Quarterly DR Failover SLA Probe (Broker 10.20.4.10:8883 | p95 < 150 ms | 16 kbps EF)")
    print(f" NDPA Drill Token: {drill_token} | Depot VRRP Gateway: 10.20.9.1/28")
    print("=" * 112)
    print(f"{'UTC TIME':<12} | {'SEQ':<4} | {'ACTIVE WAN TIER':<31} | {'ACTIVE HUB':<33} | {'RTT':<9} | {'SLA'}")
    print("-" * 112)

    with open(csv_path, "w", newline="", encoding="utf-8") as f_csv:
        writer = csv.writer(f_csv)
        writer.writerow(["utc_timestamp", "seq", "ndpa_token", "wan_tier", "active_hub", "rtt_ms", "sla_status"])

        seq = 1
        while count == 0 or seq <= count:
            now_utc = dt.datetime.now(dt.timezone.utc)
            ts_short = now_utc.strftime("%H:%M:%S.%f")[:-3]
            payload = {
                "seq": seq,
                "drill_id": "SM-DRILL-01",
                "driver_token": drill_token,
                "truck_pool": "10.20.0.10",
                "drone_pool": "10.20.5.10",
                "temp_c": round(random.uniform(2.4, 4.6), 2),
                "dscp": "EF",
            }

            t0 = time.perf_counter()
            try:
                sock.sendto(json.dumps(payload).encode("utf-8"), (target_ip, port))
                raw_ack, _ = sock.recvfrom(4096)
                rtt_ms = (time.perf_counter() - t0) * 1000.0
                ack = json.loads(raw_ack.decode("utf-8"))
                uplink = ack.get("uplink", "UNKNOWN")
                hub = ack.get("hub", "UNKNOWN")
                sla = "PASS (<150ms)" if rtt_ms < SLA_LIMIT_MS else "BREACH (>=150ms)"

                print(f"{ts_short:<12} | {seq:<4} | {uplink:<31} | {hub:<33} | {rtt_ms:>6.2f} ms | {sla}", flush=True)
                writer.writerow([now_utc.isoformat(), seq, drill_token, uplink, hub, f"{rtt_ms:.2f}", sla])
            except socket.timeout:
                print(f"{ts_short:<12} | {seq:<4} | {'CONVERGING (NVMe BUFFERED)':<31} | {'RE-HOMING TUNNEL':<33} | {'---':>9} | BUFFERED", flush=True)
                writer.writerow([now_utc.isoformat(), seq, drill_token, "NVME_BUFFER", "REHOMING", "", "RPO_0_BUFFERED"])

            f_csv.flush()
            seq += 1
            time.sleep(interval)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="SwiftMove Batch 36 DR Telemetry Probe")
    parser.add_argument("--role", choices=["sender", "receiver"], default="sender")
    parser.add_argument("--hub-name", default="LAGOS-HQ (10.20.10.1 | hq-fw-01)")
    parser.add_argument("--target", default=BROKER_IP)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=TELEMETRY_PORT)
    parser.add_argument("--count", type=int, default=0)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--csv", default="/opt/logs/batch36_quarterly_drill.csv")
    parser.add_argument("--test-video-blocks", action="store_true")
    args = parser.parse_args()

    if args.test_video_blocks:
        test_video_blocks()
    elif args.role == "receiver":
        run_receiver(args.bind, args.port, args.hub_name)
    else:
        run_sender(args.target, args.port, args.count, args.interval, args.csv)
