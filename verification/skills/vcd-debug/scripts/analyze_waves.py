#!/usr/bin/env python3
"""
analyze_waves.py — parse a UVM testbench VCD and report UART1 behaviour.

Usage:
    python3 analyze_waves.py <waves.vcd>
    python3 analyze_waves.py waves_uvm.vcd waves_legacy.vcd   # side-by-side

The script checks the key signals needed for firmware UART capture:
  - UART1.PRESETn  : does the UART peripheral come out of reset?
  - UART1.PCLK     : does the peripheral clock toggle?
  - UART1.reg_ctrl : is bit 6 set (high-speed test mode)?
  - UART1.tx_state : does the TX state machine run?
  - UART1.TXD      : does the transmit data line transition?
  - u_uart_capture.rx_shift : does the capture shift register advance?
  - u_uart_capture.sim_end  : does the capture fire an EOT?
"""

import sys
import re
from collections import defaultdict

# ---------------------------------------------------------------------------
# Minimal VCD parser
# ---------------------------------------------------------------------------

def parse_vcd(path):
    """Return (timescale_str, signals, changes).

    signals  : dict  alias -> full_name
    changes  : dict  full_name -> list of (time_ps, value_str)
    """
    signals  = {}   # alias -> full_name
    changes  = defaultdict(list)
    scope_stack = []
    timescale = "unknown"

    with open(path) as f:
        content = f.read()

    # --- header ---
    ts_m = re.search(r'\$timescale\s+(.*?)\s*\$end', content, re.DOTALL)
    if ts_m:
        timescale = ts_m.group(1).strip()

    # parse variable declarations
    for m in re.finditer(
            r'\$scope\s+\w+\s+(\S+)\s*\$end|\$upscope\s*\$end|'
            r'\$var\s+\w+\s+\d+\s+(\S+)\s+(\S+)[^$]*\$end',
            content):
        if m.group(0).startswith('$scope'):
            scope_stack.append(m.group(1))
        elif m.group(0).startswith('$upscope'):
            if scope_stack:
                scope_stack.pop()
        else:  # $var
            alias    = m.group(2)
            basename = m.group(3).split('[')[0]
            full     = '.'.join(scope_stack + [basename])
            signals[alias] = full

    # parse value changes
    cur_time = 0
    for line in content.splitlines():
        line = line.strip()
        if line.startswith('#'):
            cur_time = int(line[1:])
        elif line.startswith('b') or line.startswith('B'):
            parts = line.split()
            if len(parts) == 2:
                val, alias = parts[0][1:], parts[1]
                if alias in signals:
                    changes[signals[alias]].append((cur_time, val))
        elif line and line[0] in ('0', '1', 'x', 'z', 'X', 'Z') and len(line) >= 2:
            val, alias = line[0], line[1:]
            if alias in signals:
                changes[signals[alias]].append((cur_time, val))

    return timescale, signals, changes

# ---------------------------------------------------------------------------
# Analysis helpers
# ---------------------------------------------------------------------------

def timescale_to_ps(ts):
    """Convert timescale string like '1ns/1ps' or '1 ns' to ps/unit."""
    m = re.match(r'(\d+)\s*(fs|ps|ns|us|ms|s)', ts.split('/')[0].strip())
    if not m:
        return 1000  # assume 1ns default
    val, unit = int(m.group(1)), m.group(2)
    return val * {'fs': 0.001, 'ps': 1, 'ns': 1000, 'us': 1e6, 'ms': 1e9, 's': 1e12}[unit]

def find_signal(changes, *fragments):
    """Return the first signal key whose path contains all fragments."""
    for key in changes:
        if all(f.lower() in key.lower() for f in fragments):
            return key
    return None

def first_value(changes, sig, value='1'):
    """Return the first time (ps) sig equals value, or None."""
    for t, v in changes.get(sig, []):
        if v == value:
            return t
    return None

def count_transitions(changes, sig):
    return max(0, len(changes.get(sig, [])) - 1)

def value_at(changes, sig, time_ps):
    """Return the signal value just before or at time_ps."""
    last = None
    for t, v in changes.get(sig, []):
        if t > time_ps:
            break
        last = v
    return last

def fmt_time(t_ps, scale_ps):
    """Format a ps timestamp as ns."""
    if t_ps is None:
        return 'never'
    ns = t_ps * scale_ps / 1000
    if ns >= 1e6:
        return f'{ns/1e6:.3f} ms'
    if ns >= 1e3:
        return f'{ns/1e3:.3f} µs'
    return f'{ns:.1f} ns'

# ---------------------------------------------------------------------------
# Report for one VCD
# ---------------------------------------------------------------------------

def analyse(path):
    print(f"\n{'='*70}")
    print(f"  {path}")
    print(f"{'='*70}")

    timescale, signals, changes = parse_vcd(path)
    scale_ps = timescale_to_ps(timescale)
    print(f"  Timescale : {timescale}  ({scale_ps} ps/unit)")
    print(f"  Signals   : {len(signals)} aliases, {len(changes)} unique names")
    print()

    def find(*frags):
        return find_signal(changes, *frags)

    # Locate key signals (fuzzy match)
    rst_n      = find('sys_rst_n')      or find('reset_n')
    uart_rstn  = find('apb_uart', 'PRESETn') or find('uart', 'PRESETn')
    uart_pclk  = find('apb_uart', 'PCLK')    or find('uart', 'PCLK')
    uart_txd   = find('apb_uart', 'TXD')     or find('uart', 'TXD')
    uart_ctrl  = find('apb_uart', 'reg_ctrl') or find('uart', 'reg_ctrl')
    uart_tx_st = find('apb_uart', 'tx_state') or find('uart', 'tx_state')
    cap_shift  = find('uart_capture', 'rx_shift')
    cap_end    = find('uart_capture', 'sim_end')

    sigs = {
        'sys_rst_n'       : rst_n,
        'UART1.PRESETn'   : uart_rstn,
        'UART1.PCLK'      : uart_pclk,
        'UART1.TXD'       : uart_txd,
        'UART1.reg_ctrl'  : uart_ctrl,
        'UART1.tx_state'  : uart_tx_st,
        'capture.rx_shift': cap_shift,
        'capture.sim_end' : cap_end,
    }

    print("  Signal mapping:")
    for label, key in sigs.items():
        print(f"    {label:22s} -> {key or '(not found)'}")
    print()

    print("  Key events:")

    # Reset
    t_rst = first_value(changes, rst_n, '1') if rst_n else None
    print(f"    sys_rst_n deasserts      : {fmt_time(t_rst, scale_ps)}")

    t_uart_rst = first_value(changes, uart_rstn, '1') if uart_rstn else None
    print(f"    UART1.PRESETn deasserts  : {fmt_time(t_uart_rst, scale_ps)}")

    # PCLK transitions
    n_pclk = count_transitions(changes, uart_pclk)
    print(f"    UART1.PCLK transitions   : {n_pclk:,}")
    if n_pclk == 0:
        print("    *** PCLK NEVER TOGGLES — capture module sees no clock ***")

    # TXD transitions
    n_txd = count_transitions(changes, uart_txd)
    print(f"    UART1.TXD transitions    : {n_txd:,}")
    if n_txd == 0:
        print("    *** TXD NEVER CHANGES — UART never transmits ***")

    # reg_ctrl bit 6 (test mode enable)
    if uart_ctrl:
        test_mode_events = [(t, v) for t, v in changes.get(uart_ctrl, [])
                            if len(v) >= 7 and v[-(6+1)] == '1']
        if test_mode_events:
            t_tm = test_mode_events[0][0]
            print(f"    UART1 test-mode (ctrl[6]): enabled at {fmt_time(t_tm, scale_ps)}")
        else:
            print("    UART1 test-mode (ctrl[6]): never enabled")

    # tx_state — count non-idle transitions
    if uart_tx_st:
        active = [(t, v) for t, v in changes.get(uart_tx_st, [])
                  if v not in ('0000', '0', 'x', 'X', 'z', 'Z')]
        print(f"    UART1.tx_state active cyc: {len(active)}")

    # Capture shift register
    n_shift = count_transitions(changes, cap_shift)
    print(f"    capture.rx_shift changes : {n_shift:,}")

    # sim_end
    t_end = first_value(changes, cap_end, '1') if cap_end else None
    print(f"    capture.sim_end asserts  : {fmt_time(t_end, scale_ps)}")
    if t_end:
        print(f"    *** UART capture fired EOT at {fmt_time(t_end, scale_ps)} ***")

    # TXD transitions timeline (first 20 edges)
    if uart_txd and n_txd > 0:
        print()
        print("  UART1.TXD first 20 transitions:")
        for i, (t, v) in enumerate(changes[uart_txd][:21]):
            if i == 0:
                continue  # skip initial X
            print(f"    {fmt_time(t, scale_ps):>12s}  -> {v}")
            if i >= 20:
                print(f"    ... ({n_txd} total)")
                break

    print()

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    for path in sys.argv[1:]:
        try:
            analyse(path)
        except FileNotFoundError:
            print(f"ERROR: file not found: {path}")
        except Exception as e:
            print(f"ERROR parsing {path}: {e}")
            raise

if __name__ == '__main__':
    main()
