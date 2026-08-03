#########################################################################################
# Base path to ARM GNU tool directory
#########################################################################################

# Using an older version of the ARM GCC tool flow as the latest version causes
#   several warnings during the LD step which are un-related to our flow.

# export ARM_GNU_TOOL_VERSION := arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi
export ARM_GNU_TOOL_VERSION := gcc-arm-11.2-2022.02-x86_64-arm-none-eabi
# export ARM_GNU_TOOL_PATH    := /opt/arm_gnu_tools/$(ARM_GNU_TOOL_VERSION)/
export ARM_GNU_TOOL_PATH    := /tools/arm_gnu_tools/$(ARM_GNU_TOOL_VERSION)/

export PATH                 := $(ARM_GNU_TOOL_PATH)bin/:$(PATH)


