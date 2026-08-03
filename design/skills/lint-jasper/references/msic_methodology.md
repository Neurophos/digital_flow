# MSIC_Methodology_and_Flow 
This document details the development processes and structure of the MSIC Development project. 
This includes information about the source code control system (SCCS), develepoment guidelines and information 
on how to run various development processes. 

## Design Tools and Flows 

### Registers
Registers for internally developed modules are auto generated using the OpenTitan regtool program, albeit an older version. 
The register source is an ```<module_name>.hjson``` file kept in the module design directory under ```<module_name>/regs/reg_src``` directory. 

Detailed documentation on the format and construction of the registers can be found in the [Reg Tool Info](./regtool_README.md)  

### Jasper CDC / RDC analysis. 
Jasper CDC/RDC checking is supported by the rtl makefile process, and is run from the rtl directory of the module once setup. 

- To setup flow, copy the *cdc_config.tcl and *cdc_waivers.tcl file from the example_module/config folder into the config folder and rename the prefix with the TOP_MODULE used in the Makefile in the rtl area. 
- Update the *cdc_config.tcl file for details of your design, including the clock names, port clock associations and any special pin handling needed. 
- Run the analysis via the command ```make run jcdc``` for batch mode or ``` make run_jcdc_gui``` for interactive cdc analysis mode 
- Reports and logs are created under the rtl/.jasper directory 



### Lint 
Lint checking is the process of statically analyzing the RTL for syntax errors and other incorrect logic descriptions.  It is a first line of debugging used to find 
many issues and areas of non-conforming RTL.  The RTL is analyzed against a set of rules developed for the project and customized as needed. 
Jasper superlint is used as a the linting tool and invoked through the make flow. 

The analysis is done in the top level RTL directory of the module using the command ``` make slint ```.  The required files needed for this operation is the rtl/Makefile and 
the module unique control file config/\<module_name\>.sl.tcl file.    

The rtl/Makefile can be copied from the design/example/rtl directory and is set to extract the module name from the name of the design directory of the module.  If the directory name
does not match the design name, the DESIGN_NAME definition in the Makefile needs to be modified.  

The module_name.sl.tcl file contains the module specific definition of clocks and resets needed to analyze the RTL.  If there are hard macros that should not be analyzed, these should be 
include in the my_bboxes varaible to prevent the tool from trying to analyze them. 

Once the setup of the module is complete, the lint analysis is done via the command ``` make slint ``` in the rtl directory.  The results are stored in the rtl/.jasper directory, and the log file
can be found at .jasper/jgproject/jg.log 

Waivers can either be placed in-line with the rtl, or in a separate file.  More information on the waiver process will be added to this document later. 

The version of the tool is specified in the \<top\>/utils/tools/cadence_setup.make file, where the path to the specific jasper tool version is specified.   The main jasper binary is called ``` jg ``` 
and supports a variety of analysis operation.   To invoke the superlint function, the tool is called with the -superlint option by the \<top\>/utils/chip_utils/config/Makefile.rtl. 

The Jasper superlint documentation can be found in the jasper documentation area: 
- [Jasper Superlint User Guide]( /tools/cadence/jasper/25.03.002/doc/jasper_superlint_userguide.pdf )
- [Jasper Reference ](/tools/cadence/jasper/25.03.002/doc/jasper_superlint_userguide.pdf)

The rules used for processing superlint are at utils/chip_utils/scripts/lint/lcsuperlint_def file 

### RAM and ROM compilers
- Scripts are generally kept in the shared area /projects/bombur_tc/shared which are used to generate the RAMs and ROM instances. 
- Generated files are copied to a read only area and linked into the 'ext' top level directory. 
- Within the directory, there is generally a script called **gen_inst** which contains the options used to generate the macro. 
This script calls scripts from the shared area, for example at /projects/bombur_tc/shared/arm_mem_scripts/bin.  This script has the path to 
the rom/ram compiler. 


## Synthesis 
The Cadence GENUS tools is used to synthesize the RTL design of the MSIC.  The synthesis process is run in the impl area of the repo, using the 
scripts, constraints and other reference files checked into the repo.   The synthesized data is NOT checked into the repo, but should be managed outside 
the git repo using other methods. 

Synthesis is supported for multiple levels of the hierarchy, to allow for debugging.  It's intended that we will do a single top down synthesis operation for the 
final rtl synthesis.   

To start a synthesis process, follow the steps below: 

1. cd <top of design>/impl 
2. Make a directory with a descriptive name for your run - ``` mkdir synth_cpuss``` 
3. CD to the directory - ``` cd synth_cpuss ``` 
4. Make a copy of the example makefile and copy it into this directory as Makefile- ``` cp ../Makefile.example Makefile ``` 
5. Modify the new Makefile for the module name you are targetting - In this case, you would change the Makefile to contain: 
``` 
DESIGN_NAME         := cpuss
TOP_MODULE          := cpuss
```
6. Populate the synthesis area, which is done via a make command.   NOTE - This will copy all the source RTL into a local syn/src area! The subdirectory for this
ssynthesis is given by the parameter to the BUILD variable. 
``` make populate_syn_build BUILD=cpussV0p1 ``` 
7.  After the area is populated, the systhesis process can be started by running ``` make run_syn_logical BUILD=cpuss_test ``` or whatever build name is used. 

This will start the synthesis process. 

The directories created/used in the synth process are: (using the cpuss_test as the populated build name): 
``` 
cpuss_test/
└── syn
    ├── cons
    ├── db
    ├── include
    ├── intf
    ├── outputs
    ├── physical
    ├── reports
    ├── run
    ├── scripts
    └── src
``` 


### Constraints: 
The constraints for the design are kept in the impl/constraints/<module_name >.sdc files.  There is a single file for each possible synth level target.  This filename 
should match the DESIGN_NAME and TOP_MODULE name above 

## LEC 

## Physical Verification 


## Functional Verification



