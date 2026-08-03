# Register Flow 

to be expanded. 

Registers are defined in the hjson file according to the process described in regtool_info.md 
The registers are created by the script in utils/chip_utils/scripts/regtool, which is an older version of the OpenTitan register tool generation process. 

The register source is contained in the module under  {module}/regs/reg_src/{module}_regs.hjson 

The Makefile in the regs directory will process the regs and generate the following directories: 

- dv : RAL package (not currently used) 
- html : HTML description of the registers 
- inc : C header includes and defines 
- pdf : PDF version of the registers, used for top level documentation compilatgion 
- rtl : RTL implementation of the registers, package file and interface logic (APB) 

# Hardware implementation 
The regtool generation process will generate 3 files in the regs/rtl directory.  
- {modname}_pkg.sv 
- {modname}_top.sv 
- {modname}_apb_adapter_reg.sv 

## Package File 
The pkg file contains the system verilog definitions of the registers defined in typedefs packed structures of 32b.  The elements in the typedef are 
the bit fields defined in the hjson file. _

## top file
The _rtl file contains the actual RTL code for the register implementation.  
The top level ports of the module are: 
- reg2hw : all the data inputs into the register block, grouped into a single packed structure.
- hw2reg : all the data outputs from the register block, grouped into a single packed structure. 

Depending on the hjson register defition, the registers may have register write and read enable signals defined in the structure also. 


# Software Usage
The regtool generation process generates an include file for software use.  This needs to be 
included into the C code along with the top level address map header file (memio.h). 

The C headers are generated in the inc directory and have the form <module>_regs.h 

The headers define typedefs for unions and hte bitfields. 
Unions used to combine bit fields and whole registers to allow access to either. 

The code should create an object of the type def, and use these for read and write functions. 

A short example of this is shown below: 

```
typedef union {
    uint32_t ui32;
    struct {
         uint32_t daca : 8;
         uint32_t dacb : 8;
         uint32_t rsvd_1 : 16;
    } bf;
} reg_dac_ctrl_dacwdata_t;
```
Enums used to encode the bit field functions that are in the hjson documentation 

Example: 
```
typedef enum {
        reg_dac_ctrl_obssel_value_off = 0,
        reg_dac_ctrl_obssel_value_ctrl = 1,
        reg_dac_ctrl_obssel_value_dac_ctr = 2,
        reg_dac_ctrl_obssel_value_lfsr = 3,
        reg_dac_ctrl_obssel_value_rowen0 = 4,
        reg_dac_ctrl_obssel_value_rowen1 = 5,
        reg_dac_ctrl_obssel_value_daddr = 6,
        reg_dac_ctrl_obssel_value_daca_03_00 = 7,
        reg_dac_ctrl_obssel_value_daca_07_04 = 8,
        reg_dac_ctrl_obssel_value_daca_11_08 = 9,
        reg_dac_ctrl_obssel_value_daca_15_12 = 10,
        reg_dac_ctrl_obssel_value_daca_19_16 = 11,
        reg_dac_ctrl_obssel_value_daca_23_20 = 12,
        reg_dac_ctrl_obssel_value_daca_27_24 = 13,
        reg_dac_ctrl_obssel_value_daca_31_28 = 14,
        reg_dac_ctrl_obssel_value_daca_35_32 = 15,
        reg_dac_ctrl_obssel_value_daca_39_36 = 16,
        reg_dac_ctrl_obssel_value_daca_43_40 = 17,
        reg_dac_ctrl_obssel_value_daca_47_44 = 18,
        reg_dac_ctrl_obssel_value_daca_51_48 = 19,
        reg_dac_ctrl_obssel_value_daca_55_52 = 20,
        reg_dac_ctrl_obssel_value_daca_59_56 = 21,
        reg_dac_ctrl_obssel_value_daca_63_60 = 22,
        reg_dac_ctrl_obssel_value_dacb_03_00 = 23,
        reg_dac_ctrl_obssel_value_dacb_07_04 = 24,
        reg_dac_ctrl_obssel_value_dacb_11_08 = 25,
        reg_dac_ctrl_obssel_value_dacb_15_12 = 26,
        reg_dac_ctrl_obssel_value_dacb_19_16 = 27,
        reg_dac_ctrl_obssel_value_dacb_23_20 = 28,
        reg_dac_ctrl_obssel_value_dacb_27_24 = 29,
        reg_dac_ctrl_obssel_value_dacb_31_28 = 30,
        reg_dac_ctrl_obssel_value_dacb_35_32 = 31,
        reg_dac_ctrl_obssel_value_dacb_39_36 = 32,
        reg_dac_ctrl_obssel_value_dacb_43_40 = 33,
        reg_dac_ctrl_obssel_value_dacb_47_44 = 34,
        reg_dac_ctrl_obssel_value_dacb_51_48 = 35,
        reg_dac_ctrl_obssel_value_dacb_55_52 = 36,
        reg_dac_ctrl_obssel_value_dacb_59_56 = 37,
        reg_dac_ctrl_obssel_value_dacb_63_60 = 38,
} reg_dac_ctrl_obssel_value_enum_t;
```

Testcases are written to use these fields as follows: 

```
#include <stdio.h>
// THIS IS THE TOP LEVEL ADDRESS MAP: 
#include "memio.h"

// THIS IS THE REGTOOL GENERATED HEADER 
#include "gpio.h"

int main (void) {

    int32_t  rc ;

    // Vars for the registers
    gpio_reg_def_t gpio_regs;

    // Write a 32b register 
    MEMUI32(CHIP_CTRL_GPIO_DAC_OBSEN(0)) = 0x1;

    // RMW of a register bitfield 
    gpio_regs.m0_gpio0.ui32 = MEMUI32(GPIO_M0_GPIO0(0));
    gpio_regs.m0_gpio0.bf.hw_mode = 1;
    MEMUI32(GPIO_M0_GPIO0(0)) = gpio_regs.m0_gpio0.ui32;

}
```



