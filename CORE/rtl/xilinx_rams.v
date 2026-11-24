// Xilinx (inferred block RAM) replacements for the Intel altsyncram wrappers
// used by Archie_MiSTer. Same module names and ports, so the original core
// files stay untouched; the Intel versions are simply left out of the Vivado
// project.
//
// Latencies match the Intel originals:
//   sram_byte_en / sram_line_en : outdata_reg_a = "CLOCK0" -> 2-cycle read
//   dpram (bram.vhd)            : unregistered output       -> 1-cycle read
// Read-during-write returns the new data (write-first), as the originals do.

`timescale 1 ps / 1 ps

// Amber CPU cache data RAM (single port, byte enables, registered output)
module sram_byte_en
#(
   parameter DATA_WIDTH    = 128,
   parameter ADDRESS_WIDTH = 7
)
(
   input                          i_clk,
   input      [DATA_WIDTH-1:0]    i_write_data,
   input                          i_write_enable,
   input      [ADDRESS_WIDTH-1:0] i_address,
   input      [DATA_WIDTH/8-1:0]  i_byte_enable,
   output reg [DATA_WIDTH-1:0]    o_read_data
);

(* ram_style = "block" *)
reg [DATA_WIDTH-1:0] mem [0:2**ADDRESS_WIDTH-1];
reg [DATA_WIDTH-1:0] rd;

integer i;
always @(posedge i_clk) begin
   if (i_write_enable)
      for (i = 0; i < DATA_WIDTH/8; i = i + 1)
         if (i_byte_enable[i]) mem[i_address][i*8 +: 8] <= i_write_data[i*8 +: 8];
   rd          <= mem[i_address];
   o_read_data <= rd;
end

endmodule


// Amber CPU cache tag RAM (single port, whole-word write, registered output)
module sram_line_en
#(
   parameter DATA_WIDTH         = 128,
   parameter ADDRESS_WIDTH      = 7,
   parameter INITIALIZE_TO_ZERO = 0
)
(
   input                          i_clk,
   input      [ADDRESS_WIDTH-1:0] i_address,
   input      [DATA_WIDTH-1:0]    i_write_data,
   input                          i_write_enable,
   output reg [DATA_WIDTH-1:0]    o_read_data
);

(* ram_style = "block" *)
reg [DATA_WIDTH-1:0] mem [0:2**ADDRESS_WIDTH-1];
reg [DATA_WIDTH-1:0] rd;

integer j;
initial for (j = 0; j < 2**ADDRESS_WIDTH; j = j + 1) mem[j] = {DATA_WIDTH{1'b0}};

always @(posedge i_clk) begin
   if (i_write_enable) begin
      mem[i_address] <= i_write_data;
      rd             <= i_write_data;
   end else
      rd             <= mem[i_address];
   o_read_data <= rd;
end

endmodule


// True dual port RAM, one clock, unregistered (1-cycle) read.
// Replaces the VHDL "dpram" entity in Archie_MiSTer rtl/bram.vhd (used by ide.v).
module dpram
#(
   parameter addr_width    = 8,
   parameter data_width    = 8,
   parameter mem_init_file = "UNUSED"
)
(
   input                       clock,

   input      [addr_width-1:0] address_a,
   input      [data_width-1:0] data_a,
   input                       enable_a,
   input                       wren_a,
   output reg [data_width-1:0] q_a,
   input                       cs_a,

   input      [addr_width-1:0] address_b,
   input      [data_width-1:0] data_b,
   input                       enable_b,
   input                       wren_b,
   output reg [data_width-1:0] q_b,
   input                       cs_b
);

(* ram_style = "block" *)
reg [data_width-1:0] mem [0:2**addr_width-1];

always @(posedge clock) begin
   if (wren_a) begin
      mem[address_a] <= data_a;
      q_a            <= data_a;
   end else
      q_a            <= mem[address_a];
end

always @(posedge clock) begin
   if (wren_b) begin
      mem[address_b] <= data_b;
      q_b            <= data_b;
   end else
      q_b            <= mem[address_b];
end

endmodule
