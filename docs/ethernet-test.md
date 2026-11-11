# Wired ethernet test with ASPM on and off

Tested 2026-11-11 on a Lenovo 83GX, RTL8168h rev 15, link 1 Gbps/Full,
gateway on the same LAN segment, kernel 7.2.15.

## Method

ICMP echo at 100 packets/s for 60 s, once with ASPM off and once with it on.
Each run was counted with `ping -q`. NIC counters were read with
`ethtool -S enp2s0` before and after, and the kernel log was checked for
`timeout` or `reset`.

ASPM was turned off by writing `0` to `l1_aspm`, `l1_1_aspm`, `l1_2_aspm`,
`l1_1_pcipm` and `l1_2_pcipm`, and back on by writing `1`.

## Results

| Run | Packets | Loss | RTT min / avg / max (ms) |
|---|---|---|---|
| ASPM on | 6001 / 6001 | 0 % | 0.74 / 1.31 / 5.63 |
| ASPM off | 5240 / 5240 | 0 % | 0.38 / 0.60 / 2.73 |
| ASPM on (repeat) | 6000 / 6000 | 0 % | 0.46 / 1.31 / 4.68 |

ASPM on adds about 0.7 ms average RTT, which is the expected cost of leaving
L1.

NIC counters `tx_errors`, `rx_errors` and `rx_missed` stayed at 0 through
every run. The kernel log had no `timeout` or `reset` lines.

## Flood ping: not resolved

A flood ping (`ping -f`, 60 s) with ASPM on lost 38.9 % of packets
(7295 of 11930 received). The NIC counters did not move, which points away
from the NIC. The likely cause is the gateway rate-limiting ICMP under flood
load, but that has not been tested with ASPM off, so it is not proven.

## Not tested

Sustained TCP throughput at line rate for several minutes. ICMP at 100 pps
does not exercise the DMA and interrupt path the way a bulk transfer does.
Until that is done, the claim is limited to "no loss and no errors at 100
packets/s".
