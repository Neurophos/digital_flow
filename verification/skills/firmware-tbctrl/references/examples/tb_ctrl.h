/*/////////////////////////////////////////////////////////////////////////////
Copyright (C) Neurophos, Inc - All Rights Reserved
Proprietary and confidential
-------------------------------------------------------------------------------
TITLE : Testbench control header file
FILE  : tb_ctrl.h
DESCRIPTION : Register offsets for reading TB registers through the XMR-ed APB interface.
STANDARD    : C99
REVISIONS   :
VERSION     :
*//////////////////////////////////////////////////////////////////////////////

#ifndef TB_CTRL_H
#define TB_CTRL_H

//#bring in stdint.h here
#include <stdio.h>
#include <stdint.h>
#include "uart_stdout.h"
#include "memio.h"

//TODO: We need to generate this based on an IPXACT or hjson/pysv file that also generates the tb_ctrl SV module.
#define TB_REGS_BASE_ADDR 0x40007000
#define TB_CTRL_MODULE_ID_OFFSET    0x0
#define TB_CTRL_CTRL_OFFSET         0x4
#define TB_CTRL_ADDR_OFFSET         0x8
#define TB_CTRL_DATA_OUT_OFFSET     0xC
#define TB_CTRL_DATA_IN_OFFSET      0x10
#define TB_CTRL_STATUS_OFFSET       0x14
#define TB_CTRL_DEBUG0_OFFSET       0x18
#define TB_CTRL_DEBUG1_OFFSET       0x1C
#define TB_CTRL_DEBUG2_OFFSET       0x20
#define TB_CTRL_DEBUG3_OFFSET       0x24
#define BURST_WRITE_BUFFER(i)       (0x28 + (i)*4)
#define GPIO_BFM_DATA_OFFSET        0x68
#define FABIO_T2C_VIO_DATA_OFFSET   0x6C
#define FABIO_T2C_VIO_VALID_OFFSET  0x70
#define FABIO_SEQ_ID_PORT_OFFSET    0x100
#define FABIO_SEQ_DATA_PORT_OFFSET  0x104
#define FABIO_SEQ_SAVE_ADDR_OFFSET  0x108
#define FABIO_SEQ_GO_ADDR_OFFSET    0x10C
#define FABIO_SEQ_GOLD_RD_BUF       0x110
#define FABIO_SEQ_GOLD_RD_BUF_SAVE  0x114
#define ERROR_COUNT_OFFSET          0xF00
#define RANDOM_NUM_REG_OFFSET       0xF04

uint32_t read_tb_error_count();

#endif //TB_CTRL_H
