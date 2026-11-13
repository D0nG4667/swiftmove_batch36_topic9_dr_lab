#!/bin/sh
# Simulates BFD physical link check + Huawei NQA SLA probe (< 150 ms) to HQ (10.20.10.1) or DR Hub (10.20.10.2)
OUT=$(ping -I 10.20.11.2 -c 1 -W 1 10.20.10.1 2>/dev/null)
if [ $? -ne 0 ]; then
    # Check if HQ itself cut over to Warm DR Hub (10.20.10.2) while Metro Fibre is still healthy
    OUT=$(ping -I 10.20.11.2 -c 1 -W 1 10.20.10.2 2>/dev/null) || exit 1
fi
RTT=$(echo "$OUT" | sed -n 's/.*time=\([0-9]*\).*/\1/p')
[ -z "$RTT" ] && exit 1
if [ "$RTT" -ge 150 ]; then
    logger -t NQA-SLA "SLA BREACH on Metro Fibre (10.20.11.2): RTT=${RTT}ms >= 150ms ceiling"
    exit 1
fi
exit 0
