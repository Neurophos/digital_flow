###
### This file contains EDA tool version and path information which is included
### by the makefiles which launch the respective tools. In this way, the specific
### version of any tool which is used for simulation or implementation is tracked
### by revision control along with the source code and any other files needed
### to either simulate or implement the design. 
###
### To add any new tool to the list below, simply copy the structure for one 
### of the existing tools and just update for your tool name. Create a 
### VERSION variable and use that to add to the environment path. It's important
### that your addition to the PATH come first to ensure it overrides any other
### paths which are already defined in your environment. 
###

#########################################################################################
# Base path to vendor tools directories
#########################################################################################
export CDNS_TOOL_PATH       := /tools/cadence/


#########################################################################################
# Point to the license server for all Cadence licenses. Add other similar if necessary
# for other vendor tools
#########################################################################################
export CDS_LIC_FILE     = 27000@fs1


#########################################################################################
# Xcelium setup 
#########################################################################################
# export XCELIUM_VERSION      := 23.09.006
export XCELIUM_VERSION      := 25.09.001
export XCELIUM_BASE_PATH    := $(CDNS_TOOL_PATH)/xcelium/$(XCELIUM_VERSION)/
# NOTE - need both 'bin' paths here for SimVision and XRUN to work. 
export PATH                 := $(XCELIUM_BASE_PATH)bin:$(XCELIUM_BASE_PATH)tools/bin/64bit/:$(PATH)


#########################################################################################
# Genus setup
#########################################################################################
# export GENUS_VERSION    := GENUS211/
export GENUS_VERSION    := GENUS21.19/
export GENUS_BASE_PATH  := $(CDNS_TOOL_PATH)/genus/$(GENUS_VERSION)/
export PATH             := $(GENUS_BASE_PATH)bin/:$(PATH)


#########################################################################################
# Modus setup
#########################################################################################
export MODUS_VERSION    := ???
export MODUS_BASE_PATH  := $(CDNS_TOOL_PATH)/modus/$(MODUS_VERSION)/
# export PATH             := $(MODUS_BASE_PATH)bin/:$(PATH)


#########################################################################################
# Conformal setup
#########################################################################################
export CONFORMAL_VERSION    := ???
export CONFORMAL_BASE_PATH  := $(CDNS_TOOL_PATH)/conformal/$(CONFORMAL_VERSION)/
# export PATH                 := $(CONFORMAL_BASE_PATH)bin/:$(PATH)


#########################################################################################
# Quantus setup
#########################################################################################
export QUANTUS_VERSION      := ???
export QUANTUS_BASE_PATH    := $(CDNS_TOOL_PATH)/quantus/$(QUANTUS_VERSION)/
# export PATH                 := $(QUANTUS_BASE_PATH)tools/bin/64bit/:$(PATH)


#########################################################################################
# Tempus setup 
#########################################################################################
export TEMPUS_VERSION       := ???
export TEMPUS_BASE_PATH     := $(CDNS_TOOL_PATH)/tempus/$(TEMPUS_VERSION)/
# export PATH                 := $(TEMPUS_BASE_PATH)tools/bin/:$(PATH)


#########################################################################################
# Innovus setup
#########################################################################################
export INNOVUS_VERSION      := INNOVUS211
export INNOVUS_BASE_PATH    := $(CDNS_TOOL_PATH)/innovus/$(INNOVUS_VERSION)/
export PATH                 := $(INNOVUS_BASE_PATH)bin/:$(PATH)


#########################################################################################
# Pegasus setup
#########################################################################################
export PEGASUS_VERSION      := ???
export PEGASUS_BASE_PATH    := $(CDNS_TOOL_PATH)/pegasus/$(PEGASUS_VERSION)/
# export PATH                 := $(PEGASUS_BASE_PATH)tools/bin/64bit/:$(PATH)


#########################################################################################
# vManager 
#########################################################################################
export VMANAGER_VERSION	    := 25.09.003
export VMANAGER_BASE_PATH   := $(CDNS_TOOL_PATH)/vmanager/$(VMANAGER_VERSION)/
export PATH                 := $(VMANAGER_BASE_PATH)tools.lnx86/bin/64bit/:$(PATH)


#########################################################################################
# Jasper
#########################################################################################
export JASPER_VERSION       := 25.03.002
export JASPER_BASE_PATH     := $(CDNS_TOOL_PATH)jasper/$(JASPER_VERSION)/bin/
# export PATH                 := $(JASPER_BASE_PATH)bin/:$(PATH)


#########################################################################################
# Verisium (old Indago)
#########################################################################################
export VERISIUM_VERSION     := 24.04.071
# export VERISIUM_VERSION     := 23.09.001
export VERISIUM_DEBUG_ROOT  := $(CDNS_TOOL_PATH)/verisium/$(VERISIUM_VERSION)/
export PATH                 := $(VERISIUM_DEBUG_ROOT)tools/bin/:$(PATH)

