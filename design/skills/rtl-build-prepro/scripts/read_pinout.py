#!/usr/bin/env python3
"""
Read the MSIC pin list from an ODS spreadsheet and populate a class structure.
Data is on the second sheet of the ODS file.

This routine is intended to be called from Python code embedded in .pysv files
(e.g. for gpio and pad Verilog generation), similar to read_sysinfo.py usage
in dac_ctrl.pysv. The prepro script runs the embedded Python and emits
generated Verilog.

Source spreadsheet: common_data/soc_sysinfo/msic_pin_list.ods
"""

import os
import zipfile
import xml.etree.ElementTree as ET
from typing import List, Optional, Any


# ODS/OpenDocument namespaces
_TABLE_NS = "urn:oasis:names:tc:opendocument:xmlns:table:1.0"
_TEXT_NS = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"


def _tag(uri: str, local: str) -> str:
    return "{%s}%s" % (uri, local)


def _get_text(elem: ET.Element) -> str:
    """Extract text content from a cell or element (handles <text:p> and direct text)."""
    for e in elem.iter():
        if e.text and e.text.strip():
            return e.text.strip()
        if e.tail and e.tail.strip():
            return e.tail.strip()
    return ""


def _iter_cells(row: ET.Element) -> List[str]:
    """Yield cell text for each column, respecting number-columns-repeated."""
    result = []
    for cell in row:
        if "table-cell" not in str(cell.tag):
            continue
        repeat = int(cell.get(_tag(_TABLE_NS, "number-columns-repeated"), 1))
        text = _get_text(cell)
        for _ in range(repeat):
            result.append(text)
    return result


class PinEntry:
    """
    One row from the pin list spreadsheet.
    Attributes match column names: PAD_ORDER, SIDE, X_LOC, Y_LOC, PAD_NAME, CORE_NONGPIO_NAME, 
    SIGNAL_NAME, BITWIDTH BUS_BIT_POS, PAD_DEVICE, GROUP, DIR, GPIONUM,
    ALT_PU_VAL, ALT_PD_VAL, ALT_IE_VAL,ALT_OE_N_VAL, ALT_DS_VAL, DESCRIPTION, 
    CLK_FREQ_MHZ, CLK_SRC, input_setup, input_hold, output_clk, output_setup, output_hodl
    """

    __slots__ = (
        "pad_order",
        "side",
        "x_loc",
        "y_loc",
        "pad_name",
        "core_nonpio_name", 
        "signal_name",
        "bitwidth",
        "bus_bitpos", 
        "pad_device",
        "group",
        "dir",
        "gpionum",
        "alt_pu_val",
        "alt_pd_val",
        "alt_ie_val",
        "alt_oe_n_val",
        "alt_ds_val",
        "description",
        "clk_freq",
        "clk_src", 
        "input_clk", 
        "input_setup", 
        "input_hold", 
        "output_clk", 
        "output_setup",
        "output_hold",
    )

    def __init__(
        self,
        pad_order: str = "",
        side: str = "",
        x_loc: str = "",
        y_loc: str = "",
        pad_name: str = "",
        core_nonpio_name: str = "", 
        signal_name: str = "",
        bitwidth: str = "",
        bus_bitpos: str = "", 
        pad_device: str = "",
        group: str = "",
        dir: str = "",
        gpionum: str = "",
        alt_pu_val: str = "",
        alt_pd_val: str = "",
        alt_ie_val: str = "",
        alt_oe_n_val: str = "",
        alt_ds_val: str = "",
        description: str = "",
        clk_freq: str = "",
        clk_src: str = "", 
        input_clk: str = "",
        input_setup: str = "",
        input_hold: str = "",
        output_clk: str = "",
        output_setup: str = "",
        output_hold: str = "",
    ):
        self.pad_order = pad_order
        self.side = side
        self.x_loc = x_loc
        self.y_loc = y_loc
        self.pad_name = pad_name
        self.core_nonpio_name = core_nonpio_name
        self.signal_name = signal_name
        self.bitwidth = bitwidth
        self.bus_bitpos = bus_bitpos
        self.pad_device = pad_device
        self.group = group
        self.dir = dir
        self.gpionum = gpionum
        self.alt_pu_val = alt_pu_val
        self.alt_pd_val = alt_pd_val
        self.alt_ie_val = alt_ie_val
        self.alt_oe_n_val = alt_oe_n_val
        self.alt_ds_val = alt_ds_val
        self.description = description
        self.clk_freq = clk_freq
        self.clk_src = clk_src
        self.input_clk = input_clk
        self.input_setup = input_setup
        self.input_hold = input_hold
        self.output_clk = output_clk
        self.output_setup = output_setup
        self.output_hold = output_hold

    def __getitem__(self, key: str) -> Any:
        """Allow dict-like access by column name (case-insensitive)."""
        k = key.lower().replace(" ", "_")
        if k == "dir":
            return self.dir
        return getattr(self, k, "")

    def __repr__(self) -> str:
        return "PinEntry(pad_name=%r, signal_name=%r, group=%r)" % (
            self.pad_name,
            self.signal_name,
            self.group,
        )


class MsicPinList:
    """
    Container for the full pin list from msic_pin_list.ods.

    - pins: list of PinEntry (one per data row, header row excluded)
    - sheet_name: name of the spreadsheet table (e.g. 'msic_pin_list')
    - column_names: list of column headers in order
    """

    def __init__(self) -> None:
        self.pins: List[PinEntry] = []
        self.sheet_name: str = ""
        self.column_names: List[str] = []

    def __len__(self) -> int:
        return len(self.pins)

    def __iter__(self):
        return iter(self.pins)


# Column header to PinEntry attribute (order must match spreadsheet columns)
_PIN_ENTRY_ATTRS = [
    "pad_order",
    "side",
    "x_loc",
    "y_loc",
    "pad_name",
    "core_nonpio_name",
    "signal_name",
    "bitwidth",
    "bus_bitpos",
    "pad_device",
    "group",
    "dir",
    "gpionum",
    "alt_pu_val",
    "alt_pd_val",
    "alt_ie_val",
    "alt_oe_n_val",
    "alt_ds_val",
    "description",
    "clk_freq",
    "clk_src", 
    "input_clk", 
    "input_setup", 
    "input_hold", 
    "output_clk", 
    "output_setup",
    "output_hold"
]


def read_pin_list(pin_list_instance: Optional[MsicPinList] = None, ods_path: Optional[str] = None) -> MsicPinList:
    """
    Read the pin list ODS file and populate the provided MsicPinList instance.

    Uses only the Python standard library (zipfile + xml.etree) so it runs
    in prepro and other environments without extra dependencies.

    Args:
        pin_list_instance: Instance to populate. If None, a new MsicPinList is created.
        ods_path: Path to the .ods file. If None, uses the default path relative
                  to this script: common_data/soc_sysinfo/msic_pin_list.ods from
                  the repository root (resolved from this file's location).

    Returns:
        The populated MsicPinList instance.

    Example (from .pysv or other Python code):
        import soc_pylib.read_pinout as rpo
        pinlist = rpo.MsicPinList()
        rpo.read_pin_list(pinlist)
        for pin in pinlist.pins:
            if pin.group == 'GPIO':
                print(pin.pad_name, pin.signal_name)
    """
    if pin_list_instance is None:
        pin_list_instance = MsicPinList()

    if ods_path is None:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        # soc_pylib is under scripts/soc_pylib; repo root is scripts/..
        repo_root = os.path.normpath(os.path.join(script_dir, "..", ".."))
        ods_path = os.path.join(repo_root, "common_data", "soc_sysinfo", "msic_pin_list.ods")

    ods_path = os.path.normpath(os.path.abspath(ods_path))
    if not os.path.isfile(ods_path):
        raise FileNotFoundError("Pin list ODS not found: %s" % ods_path)

    with zipfile.ZipFile(ods_path, "r") as z:
        with z.open("content.xml") as f:
            tree = ET.parse(f)

    root = tree.getroot()
    pin_list_instance.pins = []
    pin_list_instance.sheet_name = "msic_pin_list"
    pin_list_instance.column_names = []

    sheet_index = 0
    for elem in root.iter():
        tag = elem.tag
        if "table" in tag and "table-column" not in tag and "table-row" not in tag and "table-cell" not in tag:
            name = elem.get(_tag(_TABLE_NS, "name"))
            if name:
                sheet_index += 1
                if sheet_index < 2:
                    continue
                rows = [r for r in elem if "table-row" in str(r.tag)]
                if not rows:
                    break
                header_cells = _iter_cells(rows[0])
                # Normalize column names: strip, and drop trailing empty
                col_names = [str(h).strip() for h in header_cells]
                while col_names and not col_names[-1]:
                    col_names.pop()
                pin_list_instance.sheet_name = name
                pin_list_instance.column_names = col_names

                for row_el in rows[1:]:
                    cells = _iter_cells(row_el)
                    # Pad to match attrs length
                    while len(cells) < len(_PIN_ENTRY_ATTRS):
                        cells.append("")
                    values = cells[: len(_PIN_ENTRY_ATTRS)]
                    kwargs = dict(zip(_PIN_ENTRY_ATTRS, values))
                    pin_list_instance.pins.append(PinEntry(**kwargs))
                break

    return pin_list_instance
