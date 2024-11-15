`timescale 1ns / 1ps

`define FPGA

`define range(i,COLUMN_WIDTH)                   ((i) + 1) * (COLUMN_WIDTH) - 1                  : (i) * (COLUMN_WIDTH)
`define range_n(i,COLUMN_WIDTH,n)               (i) * (COLUMN_WIDTH) + (n) - 1                  : (i) * (COLUMN_WIDTH)
`define range_x(i,COLUMN_WIDTH,x)               (i + x) * (COLUMN_WIDTH)   - 1                  : (i) * (COLUMN_WIDTH)
`define range_2d(i,COLUMN_WIDTH,x,DATA_WIDTH)   (i) * (COLUMN_WIDTH) + (x + 1) * DATA_WIDTH - 1 : (i) * (COLUMN_WIDTH) + (x) * DATA_WIDTH

