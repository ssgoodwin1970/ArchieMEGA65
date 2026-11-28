`timescale 1ns/1ps
// Unit test for archie_kbd.v: reset handshake, a key press/release, mouse movement.
module tb;
reg clk=0; always #11.9 clk=~clk;
reg rst=1, st=0; reg [7:0] d=0; wire [7:0] kd; wire ks;
reg [6:0] knum=0; reg kpress_a=0; reg [7:0] mx=8'd100, my=8'd100; reg ml=1, mr=1;
// emulate the M2M scanner: cycle through 80 keys, key 10 (A) pressed when kpress_a
always @(posedge clk) knum <= (knum==79) ? 0 : knum+1;
archie_kbd #(.CLK_HZ(42000000)) u(.clk(clk),.reset(rst),.host_data(d),.host_strobe(st),.kbd_data(kd),.kbd_strobe(ks),
  .key_num_i(knum),.key_pressed_n_i(!(kpress_a && knum==10)),.mouse_x_i(mx),.mouse_y_i(my),.mouse_left_n_i(ml),.mouse_middle_n_i(1'b1),.mouse_right_n_i(mr));
reg [7:0] last; reg got=0;
always @(posedge clk) if (ks) begin $display("  keyboard -> host %h", kd); last=kd; got=1; end
task send(input [7:0] b); begin $display("host -> keyboard %h", b); d=b; st=1; repeat(500) @(posedge clk); st=0; end endtask
task waitbyte; begin got=0; while(!got) @(posedge clk); repeat(100) @(posedge clk); end endtask
initial begin repeat(10) @(posedge clk); rst=0;
  send(8'hFF); waitbyte; send(8'hFE); waitbyte; send(8'hFD); waitbyte;
  send(8'h33);                      // SMAK: enable keys + mouse
  repeat(20000) @(posedge clk);
  $display("-- press A (expect C3, CC)"); kpress_a=1;
  waitbyte; send(8'h3F); waitbyte; send(8'h33);
  $display("-- release A (expect D3, DC)"); kpress_a=0;
  waitbyte; send(8'h3F); waitbyte; send(8'h33);
  $display("-- move mouse right by 5 counts (expect 05, 00)"); mx = mx + 10;
  waitbyte; send(8'h3F); waitbyte; send(8'h33);
  repeat(200000) @(posedge clk);
  $display("done"); $finish; end
endmodule
