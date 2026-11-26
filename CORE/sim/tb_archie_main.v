`timescale 1ns/1ps
module tb;
reg clk_sys=0, clk_vid=0; always #11.9 clk_sys=~clk_sys; always #5.2 clk_vid=~clk_vid;
reg reset=1, loading=0, rom_wr=0; reg [20:0] rom_addr=0; reg [7:0] rom_data=0; wire rom_busy;
wire wr, rd; wire [19:0] addr; wire [31:0] wdata; wire [3:0] be; wire [7:0] bc;
reg [31:0] rdata; reg rvalid=0; reg wait_r=0;
reg [31:0] mem [0:1048575];
// program at ROM start: MOV r0,#0x1000 ; STR r0,[r0] ; LDR r1,[r0] ; ADD r1,r1,#1 ; B -8 (loop str/ldr)
reg [31:0] prog [0:7];
initial begin prog[0]=32'hE3A00402; prog[1]=32'hE5800000; prog[2]=32'hE5901000; prog[3]=32'hE2811001; prog[4]=32'hE5801000; prog[5]=32'hEAFFFFFB; end
archie_main #(.ROM_QUIET_BITS(6)) dut(.clk_sys(clk_sys),.clk_vid(clk_vid),.reset_i(reset),.rom_loading_i(loading),.rom_wr_i(rom_wr),.rom_addr_i(rom_addr),.rom_data_i(rom_data),.rom_busy_o(rom_busy),
 .avm_write_o(wr),.avm_read_o(rd),.avm_address_o(addr),.avm_writedata_o(wdata),.avm_byteenable_o(be),.avm_burstcount_o(bc),.avm_readdata_i(rdata),.avm_readdatavalid_i(rvalid),.avm_waitrequest_i(wait_r),
 .joy0_n_i(5'h1f),.joy1_n_i(5'h1f));
// avalon slave with ~10 cycle latency, bursts
integer pend=0, lat=0; reg [19:0] raddr; integer nwr=0, nrd=0;
always @(posedge clk_sys) begin
  rvalid<=0;
  if (wr & ~wait_r) begin
     if(be[0]) mem[addr][7:0]<=wdata[7:0]; if(be[1]) mem[addr][15:8]<=wdata[15:8]; if(be[2]) mem[addr][23:16]<=wdata[23:16]; if(be[3]) mem[addr][31:24]<=wdata[31:24];
     nwr=nwr+1; if(!addr[19]) $display("%t RAM write [%h]=%h be=%b", $time, addr, wdata, be); end
  if (rd & ~wait_r) begin pend=bc; raddr=addr; lat=10; nrd=nrd+1; end
  else if (pend>0) begin if(lat>0) lat=lat-1; else begin rdata<=mem[raddr]; rvalid<=1; raddr=raddr+1; pend=pend-1; end end
end
integer i;
initial begin
  for(i=0;i<1048576;i=i+1) mem[i]=0;
  #500 loading=1; reset=0;
  for(i=0;i<24;i=i+1) begin @(posedge clk_sys); while(rom_busy) @(posedge clk_sys); rom_wr<=1; rom_addr<=i; rom_data<=prog[i/4][(i%4)*8+:8]; @(posedge clk_sys); rom_wr<=0; @(posedge clk_sys); end
  repeat(20) @(posedge clk_sys);
  $display("ROM word0=%h word5=%h (expect E3A00402, EAFFFFFB)", mem[20'h80000], mem[20'h80005]);
  loading=0;
  repeat(6000) @(posedge clk_sys);
  $display("HyperRAM reads=%0d writes=%0d  block RAM word0=%h (expect 020000xx, counting up)", nrd, nwr, dut.lowram[0]);
  $finish;
end
endmodule
