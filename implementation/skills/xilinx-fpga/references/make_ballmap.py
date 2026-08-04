#!/usr/bin/env python3
"""make_dispatcher_ballmap.py — assign the dispatcher FPGA (XC7S100-2FGGA676I, same part as
the DAC board) I/O to real FGGA676 balls.

INPUT  : xc7s100_fgga676_pkgpins.csv  (ball, pin_func, is_gp, bank, cfg_spi) — copied from the
         DAC board (parsed from the vendor XC7S100-2FGGA676I KiCad symbol).
OUTPUT : dispatcher_fpga_ballmap.csv  (ball, port, net)
           port = RTL / board-top port name (backplane_disp_top)  -> used by the XDC
           net  = board schematic net name                        -> used by gen_backplane_disp.py

Deterministic: `clk` -> a clock-capable (MRCC) ball; all other user I/O -> GP balls in a fixed
signal order, GP balls sorted (row-letter, column). Config-SPI (QSPI boot) balls are reserved;
JTAG/CCLK/PROG_B/DONE/INIT_B/M[2:0]/CFGBVS are on their dedicated balls (handled in the FPGA
symbol build, not here). PROVISIONAL until a Vivado place run on backplane_disp_top is authoritative.
"""
import csv, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "xc7s100_fgga676_pkgpins.csv")
OUT = os.path.join(HERE, "dispatcher_fpga_ballmap.csv")
NSLOT = 11

def port2net(p):
    m = re.match(r'(\w+?)\[(\d+)\]$', p)
    base, idx = (m.group(1), int(m.group(2))) if m else (p, None)
    simple = {"clk":"FT_CLK","rst_n":"RST_N",
              "ft_rxf_n":"FT_RXF_N","ft_txe_n":"FT_TXE_N","ft_rd_n":"FT_RD_N","ft_wr_n":"FT_WR_N",
              "ft_oe_n":"FT_OE_N","ft_siwu_n":"FT_SIWU_N","ft_rst_n":"FT_RST_N",
              "bp_cs_n":"DRV_CS_N","bp_wr_n":"DRV_WR_N","bp_rd_n":"DRV_RD_N","bp_ldac_n":"DRV_LDAC_N",
              "bp_reset_n":"DRV_RESET_N","busclk":"DRV_BUSCLK","bp_int_n":"BP_INT_N",
              "activate_gpio":"ACTIVATE_GPIO","chop_gpio":"CHOP_GPIO","ms_ready":"MS_READY","gpio_spare":"GPIO_SPARE",
              "vcm_phase":"VCM_PHASE","adc_sclk":"ADC_SCLK","adc_sdi":"ADC_SDI","adc_sdo":"ADC_SDO",
              "adc_cs_n":"ADC_CS_N","adc_rst_n":"ADC_RST_N",
              # UART command link (ADR-0001 §8.1): TTL side of the MAX13237E RS-232 xceiver
              "uart_rxd":"UART_RX_TTL","uart_txd":"UART_TX_TTL",
              "uart_cts_n":"UART_CTS_TTL","uart_rts_n":"UART_RTS_TTL"}
    if p in simple: return simple[p]
    return {"ft_data":"FT_D%d","ft_be":"FT_BE%d","bp_d":"DRV_D%d","bp_addr":"DRV_ADDR%d",
            "bp_rd":"BP_RD%d","present_n":"BP_PRESENT_N_%d","pwrgood":"BP_PWRGOOD_%d"}[base] % idx

def user_ports():
    p = []
    p += ["ft_data[%d]" % i for i in range(32)] + ["ft_be[%d]" % i for i in range(4)]
    p += ["ft_rxf_n","ft_txe_n","ft_rd_n","ft_wr_n","ft_oe_n","ft_siwu_n","ft_rst_n"]
    p += ["bp_d[%d]" % i for i in range(32)] + ["bp_addr[%d]" % i for i in range(5)]
    p += ["bp_cs_n","bp_wr_n","bp_rd_n","bp_ldac_n","bp_reset_n","busclk"]
    p += ["bp_rd[%d]" % i for i in range(8)] + ["bp_int_n"]
    p += ["present_n[%d]" % s for s in range(NSLOT)] + ["pwrgood[%d]" % s for s in range(NSLOT)]
    p += ["activate_gpio","chop_gpio","ms_ready","gpio_spare","vcm_phase"]
    p += ["adc_sclk","adc_sdi","adc_sdo","adc_cs_n","adc_rst_n"]
    p += ["rst_n"]
    # appended last so existing ball assignments are unchanged (UART is additive)
    p += ["uart_rxd","uart_txd","uart_cts_n","uart_rts_n"]   # UART command link (ADR-0001 §8.1)
    return p

# Timing-critical FT601 datapath I/O — clustered into the clock's bank so the FT601
# logic floorplans next to it (short FF<->pad routes; closes source-sync timing).
FT_GROUP = (["ft_data[%d]" % i for i in range(32)] + ["ft_be[%d]" % i for i in range(4)]
            + ["ft_rxf_n","ft_txe_n","ft_rd_n","ft_wr_n","ft_oe_n","ft_siwu_n","ft_rst_n"])

def main():
    pk = list(csv.DictReader(open(PKG)))
    yes = ("1","True","true")
    def bkey(b):
        m = re.match(r'([A-Z]+)(\d+)', b); return (m.group(1), int(m.group(2))) if m else (b,0)
    bank_of = {r["ball"]: str(r.get("bank","")).strip() for r in pk}
    spi = {r["ball"] for r in pk if str(r.get("cfg_spi","0")).strip() in yes}
    gp  = [r for r in pk if str(r.get("is_gp","0")).strip() in yes and r["ball"] not in spi]
    mrcc = sorted((r["ball"] for r in gp if "MRCC" in r["pin_func"]), key=bkey)
    plain = sorted((r["ball"] for r in gp if "MRCC" not in r["pin_func"]), key=bkey)
    if not mrcc: sys.exit("no MRCC ball found")
    clk_ball = mrcc[0]
    clk_bank = bank_of[clk_ball]

    # available GP balls (excluding clk): the FT601 group takes the clock's bank first
    # (then spills to the nearest banks); everything else takes the remaining banks.
    avail = [b for b in (plain + mrcc[1:]) if b != clk_ball]
    ft_pool   = sorted([b for b in avail if bank_of[b] == clk_bank], key=bkey) \
              + sorted([b for b in avail if bank_of[b] != clk_bank], key=bkey)

    ports = user_ports()
    ft_ports    = [p for p in ports if p in FT_GROUP]
    other_ports = [p for p in ports if p != "clk" and p not in FT_GROUP]
    if len(ft_ports) > len(ft_pool): sys.exit("not enough GP balls for the FT601 group")
    ft_assign  = list(zip(ft_ports, ft_pool[:len(ft_ports)]))
    rest_pool  = ft_pool[len(ft_ports):]                       # balls left after the FT601 cluster
    if len(other_ports) > len(rest_pool): sys.exit("not enough GP balls for the remaining I/O")
    other_assign = list(zip(other_ports, rest_pool[:len(other_ports)]))

    rows = [("clk", clk_ball)] + ft_assign + other_assign
    rows_out = sorted(([b, p, port2net(p)] for p, b in rows), key=lambda r: bkey(r[0]))
    with open(OUT, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["ball","port","net"]); w.writerows(rows_out)
    ft_banks = sorted({bank_of[b] for _, b in ft_assign})
    print("dispatcher ballmap: %d user I/O (clk->%s MRCC, bank %s); FT601 group (%d) -> bank(s) %s; "
          "%d QSPI reserved -> %s"
          % (len(rows), clk_ball, clk_bank, len(ft_ports), ",".join(ft_banks), len(spi), os.path.basename(OUT)))

if __name__ == "__main__":
    main()
