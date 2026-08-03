# sparkle-fv evaluation report

Config: `{"timeout_s": 300, "max_bmc": 45, "max_k": 12, "llm": false, "z3": "4.16 (sparkle-fv) / 4.8.12 (smtbmc)", "yosys": "0.33", "verilator": "5.020"}`

## Aggregate

| tool | solved | total | wall time (s) |
|---|---|---|---|
| **sparkle-fv** (BMC+k-ind+Houdini) | 30 | 32 | 751.7 |
| yosys-smtbmc (BMC+ind, SymbiYosys engine) | 30 | 32 | 529.5 |

## Per-variant results

| benchmark | variant | expect | state bits | sparkle-fv | method | t(s) | verilator | smtbmc | t(s) |
|---|---|---|---|---|---|---|---|---|---|
| alu32 | design.sv | safe | 85 | ✅ SAFE | kind | 0.14 | — | ✅ SAFE | 19.03 |
| alu32 | bug1.sv | bug | 85 | ✅ BUG | kind-base | 0.45 | ✓ | ✅ BUG | 0.18 |
| alu32 | bug2.sv | bug | 85 | ✅ BUG | kind-base | 0.46 | ✓ | ✅ BUG | 0.14 |
| async_handshake | design.sv | safe | 29 | ✅ SAFE | kind | 0.78 | — | ✅ SAFE | 1.74 |
| async_handshake | bug1.sv | bug | 29 | ✅ BUG | kind-base | 1.24 | ✓ | ✅ BUG | 0.17 |
| axi_lite_slave | design.sv | safe | 12 | ✅ SAFE | kind | 0.14 | — | ✅ SAFE | 1.26 |
| axi_lite_slave | bug1.sv | bug | 12 | ✅ BUG | kind-base | 0.34 | ✓ | ✅ BUG | 0.10 |
| axi_lite_slave | bug2.sv | bug | 12 | ✅ BUG | kind-base | 0.17 | ✓ | ✅ BUG | 0.09 |
| counter_wrap | design.sv | safe | 10 | ✅ SAFE | kind | 0.03 | — | ✅ SAFE | 0.95 |
| counter_wrap | bug1.sv | bug | 10 | ✅ BUG | bmc | 1.39 | ✓ | ✅ BUG | 0.27 |
| gray_counter | design.sv | safe | 29 | ✅ SAFE | kind | 0.08 | — | ✅ SAFE | 2.83 |
| gray_counter | bug1.sv | bug | 29 | ✅ BUG | bmc | 18.92 | ✓ | ✅ BUG | 1.58 |
| lfsr | design.sv | safe | 18 | ✅ SAFE | kind | 0.03 | — | ✅ SAFE | 1.07 |
| lfsr | bug1.sv | bug | 18 | ✅ BUG | kind-base | 0.07 | ✓ | ✅ BUG | 0.10 |
| memctrl | design.sv | safe | 34 | ➖ UNKNOWN | bmc | 300.03 | — | ➖ UNKNOWN | 150.98 |
| memctrl | bug1.sv | bug | 34 | ✅ BUG | kind-base | 0.21 | ✓ | ✅ BUG | 0.13 |
| memctrl | bug2.sv | bug | 34 | ✅ BUG | kind-base | 0.21 | ✓ | ✅ BUG | 0.14 |
| pipeline_hazard | design.sv | safe | 375 | ➖ UNKNOWN | bmc | 351.87 | — | ➖ UNKNOWN | 173.83 |
| pipeline_hazard | bug1.sv | bug | 375 | ✅ BUG | kind-base | 2.10 | ✓ | ✅ BUG | 0.17 |
| priority_arbiter | design.sv | safe | 23 | ✅ SAFE | kind | 0.70 | — | ✅ SAFE | 3.30 |
| priority_arbiter | bug1.sv | bug | 23 | ✅ BUG | bmc | 11.91 | ✓ | ✅ BUG | 0.55 |
| round_robin_arbiter | design.sv | safe | 15 | ✅ SAFE | kind | 0.08 | — | ✅ SAFE | 2.44 |
| round_robin_arbiter | bug1.sv | bug | 15 | ✅ BUG | kind-base | 0.13 | ✓ | ✅ BUG | 0.10 |
| round_robin_arbiter | bug2.sv | bug | 15 | ✅ BUG | kind-base | 0.04 | ✓ | ✅ BUG | 0.08 |
| sync_fifo | design.sv | safe | 15 | ✅ SAFE | kind | 0.05 | — | ✅ SAFE | 2.11 |
| sync_fifo | bug1.sv | bug | 15 | ✅ BUG | kind-base | 2.35 | ✓ | ✅ BUG | 0.46 |
| sync_fifo | bug2.sv | bug | 15 | ✅ BUG | kind-base | 0.13 | ✓ | ✅ BUG | 0.11 |
| uart_tx | design.sv | safe | 28 | ✅ SAFE | kind | 0.17 | — | ✅ SAFE | 1.61 |
| uart_tx | bug1.sv | bug | 28 | ✅ BUG | bmc | 17.05 | ✓ | ✅ BUG | 2.12 |
| uart_tx | bug2.sv | bug | 28 | ✅ BUG | kind-base | 1.63 | ✓ | ✅ BUG | 0.18 |
| rv32i_soc | design.sv | safe | 1878 | ✅ SAFE | kind | 4.69 | — | ✅ SAFE | 160.32 |
| rv32i_soc | bug1.sv | bug | 1878 | ✅ BUG | kind-base | 34.10 | ✓ | ✅ BUG | 1.41 |

## Scalability (time vs design size)

| benchmark | state bits | sparkle-fv t(s) | smtbmc t(s) |
|---|---|---|---|
| counter_wrap/design.sv | 10 | 0.03 | 0.95 |
| counter_wrap/bug1.sv | 10 | 1.39 | 0.27 |
| axi_lite_slave/design.sv | 12 | 0.14 | 1.26 |
| axi_lite_slave/bug1.sv | 12 | 0.34 | 0.10 |
| axi_lite_slave/bug2.sv | 12 | 0.17 | 0.09 |
| round_robin_arbiter/design.sv | 15 | 0.08 | 2.44 |
| round_robin_arbiter/bug1.sv | 15 | 0.13 | 0.10 |
| round_robin_arbiter/bug2.sv | 15 | 0.04 | 0.08 |
| sync_fifo/design.sv | 15 | 0.05 | 2.11 |
| sync_fifo/bug1.sv | 15 | 2.35 | 0.46 |
| sync_fifo/bug2.sv | 15 | 0.13 | 0.11 |
| lfsr/design.sv | 18 | 0.03 | 1.07 |
| lfsr/bug1.sv | 18 | 0.07 | 0.10 |
| priority_arbiter/design.sv | 23 | 0.70 | 3.30 |
| priority_arbiter/bug1.sv | 23 | 11.91 | 0.55 |
| uart_tx/design.sv | 28 | 0.17 | 1.61 |
| uart_tx/bug1.sv | 28 | 17.05 | 2.12 |
| uart_tx/bug2.sv | 28 | 1.63 | 0.18 |
| async_handshake/design.sv | 29 | 0.78 | 1.74 |
| async_handshake/bug1.sv | 29 | 1.24 | 0.17 |
| gray_counter/design.sv | 29 | 0.08 | 2.83 |
| gray_counter/bug1.sv | 29 | 18.92 | 1.58 |
| memctrl/design.sv | 34 | 300.03 | 150.98 |
| memctrl/bug1.sv | 34 | 0.21 | 0.13 |
| memctrl/bug2.sv | 34 | 0.21 | 0.14 |
| alu32/design.sv | 85 | 0.14 | 19.03 |
| alu32/bug1.sv | 85 | 0.45 | 0.18 |
| alu32/bug2.sv | 85 | 0.46 | 0.14 |
| pipeline_hazard/design.sv | 375 | 351.87 | 173.83 |
| pipeline_hazard/bug1.sv | 375 | 2.10 | 0.17 |
| rv32i_soc/design.sv | 1878 | 4.69 | 160.32 |
| rv32i_soc/bug1.sv | 1878 | 34.10 | 1.41 |
