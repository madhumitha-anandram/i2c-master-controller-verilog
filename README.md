## What this project does

Implements a complete I2C (Inter-Integrated Circuit) master controller at 100 kHz standard mode, capable of both writing data to a slave and reading data from a slave. I2C uses only 2 wires — SCL (clock) and SDA (data) — to communicate with multiple devices on the same bus.

How I2C works

Every I2C transaction follows this sequence:

For a WRITE:

START → [7-bit ADDRESS + W(0)] → ACK from slave → [8-bit DATA] → ACK from slave → STOP

For a READ:

START → [7-bit ADDRESS + R(1)] → ACK from slave → [8-bit DATA from slave] → NACK from master → STOP

START condition: SDA falls while SCL is HIGH. STOP condition: SDA rises while SCL is HIGH. Data bits: SDA must be stable while SCL is HIGH. SDA can only change when SCL is LOW.

The 4× clock trick — why it matters

The system clock runs at 50 MHz. I2C SCL is 100 kHz. Naively you could just divide by 500, but then you'd have no way to control the sub-cycle timing needed for setup and hold times.

Instead, the design generates a scl_tick at 4× the I2C frequency (400 kHz). This divides each SCL period into 4 phases (0, 1, 2, 3):

Phase:  0         1         2         3

SCL:    LOW       LOW→HIGH  HIGH      HIGH→LOW

SDA:    (change)  (stable)  (sample)  (stable)

Phase 0: SCL is LOW → safe to change SDA

Phase 1: SCL rises → SDA must be stable

Phase 2: SCL HIGH → slave samples SDA (receiver reads here)

Phase 3: SCL falls → move to next bit

CLK_DIV = 50_000_000 / (100_000 × 4) = 125 — so scl_tick fires every 125 system clock cycles.

SDA tri-state control

SDA is a bidirectional open-drain bus. The master controls it via two signals:

sda_oe = 1 → master drives SDA (pulls it to sda_out)

sda_oe = 0 → master releases SDA to high-Z, allowing slave to drive it (for ACK, or for read data)

assign sda = sda_oe ? sda_out : 1'bz;

Write master FSM — 7 states

| State | Action |
| --- | --- |
| IDLE | Wait for start. Load addr_reg = {addr, 1'b0} (R/W=0 for write) |
| START | Generate START condition: SDA falls while SCL HIGH (4 phases) |
| ADDR | Shift out 8 bits (7-bit address + 0) MSB first, one bit per 4 phases |
| ACK1 | Release SDA (High-Z), raise SCL, sample SDA at phase 2 (ack = ~sda) |
| DATA | Shift out 8 data bits MSB first |
| ACK2 | Release SDA, sample slave ACK |
| STOP | SDA rises while SCL HIGH — STOP condition |

Read master FSM — 7 states

Same as write but with a READ state instead of DATA:

| State | Action |
| --- | --- |
| READ | Release SDA (High-Z), raise SCL, sample sda at phase 2 and shift into data_reg |
| NACK | After 8 bits received, master drives SDA HIGH (NACK = "I have enough data") |

Address byte uses {addr, 1'b1} (R/W=1 for read).

## File structure

master_write.v      — I2C master write: 7-state FSM, 4-phase SCL, tri-state SDA

master_read.v       — I2C master read: 7-state FSM, same timing, samples incoming SDA

tb_master_write.v   — Testbench: drives start, address, data; verifies SCL/SDA waveforms

tb_master_read.v    — Testbench: drives start, address; simulates slave driving SDA for read data

