# Python pre-processing of modules 
The utils/chip_utils/script/prepro python code allows for integrating python code into the file and expanding this 
before generating the base file.  

The prepro python program needs to be invoked using the virtual env in {ROOT}/scripts/venv, which is easily done via the command
'source activate_venv.sh'.  This script is located in the top level directory of the project. 

This venv contains a library to allow for reading of the SoC specification YAML file located in common_data/soc_sysinfo. 
This yaml file allows a central location to specify a variety of SoC specifications that need to be used by mulitple 
groups.  

To embed python code into a file so that 'prepro' will recognize this, there are specific headers and footers used. 
This is "/* py-begin" for the start, and "py-end \*/" to finish; 

The python library in {ROOT}/scripts/soc_pylib contain python code to read the yaml data so that the embedded code 
can generate based on this. 


An example of code is: 
/* py-begin
import sys, string, yaml, os
print("//  Modifed by prepro from memio.pyh")
# Read the msic sysinfo yaml file, which specs the base address of the modules
import soc_pylib.read_sysinfo as rsi
info = rsi.MsicSysInfo()
rsi.read_sysinfo(info)
print(f"#define ROM_BASE_ADDR                 0x{info.memory_map.arm_rom_base:08x}")
print(f"#define ARM_SRAM_BASE_ADDR            0x{info.memory_map.arm_ram_base:08x}")
print(f"#define DAC_SRAM_BASE_ADDR            0x{info.memory_map.dac_sram_base:08x}")
print(f"#define CS_ROM_TABLE_BASE_ADDR        0x{info.memory_map.cs_rom_table_base:08x}")
print("// Peripherals within the CPUSS ")
print(f"#define TIMER0_BASE_ADDR              0x{info.memory_map.apb_base + info.memory_map.apb_modules.timer0_base:08x}")
print(f"#define TIMER1_BASE_ADDR              0x{info.memory_map.apb_base + info.memory_map.apb_modules.timer1_base:08x}")
print(f"#define DUALTIMER_BASE_ADDR           0x{info.memory_map.apb_base + info.memory_map.apb_modules.dualtimer_base:08x}")
print(f"#define UART0_BASE_ADDR               0x{info.memory_map.apb_base + info.memory_map.apb_modules.uart0_base:08x}")
print(f"#define UART1_BASE_ADDR               0x{info.memory_map.apb_base + info.memory_map.apb_modules.uart1_base:08x}")
print(f"#define UART2_BASE_ADDR               0x{info.memory_map.apb_base + info.memory_map.apb_modules.uart2_base:08x}")
print(f"#define WATCHDOG_BASE_ADDR            0x{info.memory_map.apb_base + info.memory_map.apb_modules.watchdog_base:08x}")
print(f"#define SPI_HOST0_BASE_ADDR           0x{info.memory_map.apb_base + info.memory_map.apb_modules.spi_host_base:08x}")
print(f"#define GPIO_BASE_ADDR                0x{info.memory_map.apb_base + info.memory_map.apb_modules.gpio_base:08x}")
print(f"#define CHIP_CTRL_BASE_ADDR           0x{info.memory_map.apb_base + info.memory_map.apb_modules.chip_ctrl_base:08x}")
print(f"#define CLOCK_CTRL_BASE_ADDR          0x{info.memory_map.apb_base + info.memory_map.apb_modules.clock_ctrl_base:08x}")
print(f"#define DAC_CTRL_BASE_ADDR            0x{info.memory_map.apb_base + info.memory_map.apb_modules.dac_ctrl_base:08x}")
print(f"#define C2C_COMM_BASE_ADDR            0x{info.memory_map.apb_base + info.memory_map.apb_modules.c2c_comm_base:08x}")
print("// end python operation ")

py-end */

The above example is in the file {ROOT}/firmware/msic_tests/common/include/memio.pyh.  The make process will run prepro 
on this source file to generate a memio.h file used in the firmware compilation process.  

