`timescale 1ns/1ps
module tb;
reg clk=0; always #11.9 clk=~clk;
reg rst=1, st=0; reg [7:0] d=0; wire [7:0] kd; wire ks;
archie_kbd #(.CLK_HZ(42000000)) u(.clk(clk),.reset(rst),.host_data(d),.host_strobe(st),.kbd_data(kd),.kbd_strobe(ks));
always @(posedge clk) if (ks) $display("%0t us: keyboard -> host %h", $time/1000, kd);
task send(input [7:0] b); begin d=b; st=1; repeat(500) @(posedge clk); st=0; repeat(20000) @(posedge clk); end endtask
initial begin repeat(10) @(posedge clk); rst=0;
  $display("host HRST FF"); send(8'hFF);
  $display("host RAK1 FE"); send(8'hFE);
  $display("host RAK2 FD"); send(8'hFD);
  $display("host RQID 20"); send(8'h20);
  $display("host RQMP 22"); send(8'h22);
  $display("host BACK 3F"); send(8'h3F);
  $display("host SMAK 33 (no reply expected)"); send(8'h33);
  $finish; end
endmodule
