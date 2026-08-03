#!/usr/bin/env python3
import yaml
import os

class MsicSysInfo:
    """Class to hold MSIC system information."""
    def __init__(self):
        self.metasurface = self.Metasurface()
        self.memory_map = self.MemoryMap()
        self.dac_ctrl = self.dac_ctrl()

    class Metasurface:
        def __init__(self):
            self.x_pixel_cnt = None
            self.y_pixel_cnt = None
            self.x_pixel_frames = None
            self.y_pixel_frames = None
            self.pixel_frame_cols = None
            self.pixel_frame_rows = None


    class dac_ctrl:
        def __init__(self):
            self.num_dac_ram_macros = None
            self.dac_ram_macro_width = None

    class MemoryMap:
        def __init__(self):
            self.apb_base = None
            self.arm_rom_base = None
            self.arm_ram_base = None
            self.dac_sram_base = None
            self.cs_rom_table_base = None
            self.apb_modules = self.ApbModules()

        class ApbModules:
            def __init__(self):
                self.timer0_base = None
                self.timer1_base = None
                self.dualtimer_base = None
                self.uart0_base = None
                self.uart1_base = None
                self.uart2_base = None
                self.watchdog_base = None
                self.test_slave_base = None
                self.spi_host_base = None
                self.gpio_base = None
                self.fabio_tgt_base = None
                self.chip_ctrl_base = None
                self.clock_ctrl_base = None
                self.dac_ctrl_base = None
                self.c2c_comm_base = None

def read_sysinfo(sys_info_instance, yaml_path=None):
    """
    Reads the yaml file and populates the provided class instance.
    
    Args:
        sys_info_instance (MsicSysInfo): Instance to populate.
        yaml_path (str, optional): Path to the yaml file. Defaults to relative path.
        
    Returns:
        MsicSysInfo: The populated instance.
    """
    if yaml_path is None:
        # Default path relative to this script
        script_dir = os.path.dirname(os.path.abspath(__file__))
        yaml_path = os.path.join(script_dir, '../../common_data/soc_sysinfo/msic_sysinfo.yaml')

    with open(yaml_path, 'r') as f:
        data = yaml.safe_load(f)

    msic = data.get('msic', {})
    
    # Metasurface
    meta = msic.get('metasurface', {})
    sys_info_instance.metasurface.x_pixel_cnt = meta.get('x_pixel_cnt')
    sys_info_instance.metasurface.y_pixel_cnt = meta.get('y_pixel_cnt')
    sys_info_instance.metasurface.x_pixel_frames = meta.get('x_pixel_frames')
    sys_info_instance.metasurface.pixel_frame_cols = meta.get('pixel_frame_cols')
    sys_info_instance.metasurface.pixel_frame_rows = meta.get('pixel_frame_rows')

    dc = msic.get('dac_ctrl', {})
    sys_info_instance.dac_ctrl.num_dac_ram_macros = dc.get('num_dac_ram_macros')
    sys_info_instance.dac_ctrl.dac_ram_macro_width = dc.get('dac_ram_macro_width')
    
    # Memory Map
    mem = msic.get('memory_map', {})
    sys_info_instance.memory_map.apb_base = mem.get('apb_base')
    sys_info_instance.memory_map.arm_rom_base = mem.get('arm_rom_base')
    sys_info_instance.memory_map.arm_ram_base = mem.get('arm_ram_base')
    sys_info_instance.memory_map.dac_sram_base = mem.get('dac_sram_base')
    sys_info_instance.memory_map.cs_rom_table_base = mem.get('cs_rom_table_base')
    
    # APB Modules
    apb_mod_data = mem.get('apb_modules', {})
    for key, value in apb_mod_data.items():
        if hasattr(sys_info_instance.memory_map.apb_modules, key):
            setattr(sys_info_instance.memory_map.apb_modules, key, value)
    
    return sys_info_instance

