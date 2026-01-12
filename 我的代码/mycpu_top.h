`ifndef MYCPU_TOP_H
    `define MYCPU_TOP_H
    `define IF_TO_ID_BUS_WIDTH 65
    `define ID_TO_EXE_BUS_WIDTH 156 // 154 + 2(Data Size)
    `define EXE_TO_MEM_BUS_WIDTH 110 // 108 + 2(Data Size)
    `define EXE_TO_ID_BUS_WIDTH 40
    `define MEM_TO_ID_BUS_WIDTH 40
    `define MEM_TO_WB_BUS_WIDTH 70
    `define WB_TO_ID_BUS_WIDTH 39
    `define ID_TO_IF_BUS_WIDTH 33
    `define BYPASS_BUS_WIDTH 38
`endif