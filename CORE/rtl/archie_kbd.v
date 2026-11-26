// Archimedes keyboard controller (the part the MiSTer HPS used to emulate).
//
// RISC OS talks to the keyboard through IOC's serial port: KBD_OUT_* carries
// bytes from the host, KBD_IN_* bytes back to it. Protocol (Acorn A3000 TRM):
//   HRST 0xFF -> reply HRST 0xFF      reset handshake, step 1
//   RAK1 0xFE -> reply RAK1 0xFE      step 2
//   RAK2 0xFD -> reply RAK2 0xFD      step 3 (keyboard is now ready)
//   RQID 0x20 -> reply KBID 0x81      keyboard ID
//   RQMP 0x22 -> reply 0x00, 0x00     mouse position (no movement yet)
//   RQPD 0x4x -> reply PDAT 0xEx      echo request
//   LEDS 0x0x, BACK 0x3F, NACK/SACK/MACK/SMAK 0x30-0x33: no reply
// Key presses (KDDA/KUDA) come in phase 3; this module already has the queue.
//
// Replies are sent after a short delay, roughly the time a real keyboard needs
// to clock a byte back at 31.25 kbaud, so RISC OS sees realistic timing.

`timescale 1 ps / 1 ps

module archie_kbd
#(
   parameter CLK_HZ = 42000000
)
(
   input            clk,
   input            reset,

   input      [7:0] host_data,      // KBD_OUT_DATA
   input            host_strobe,    // KBD_OUT_STROBE: IOC holds it high while "transmitting" a byte
   output reg [7:0] kbd_data,       // KBD_IN_DATA
   output reg       kbd_strobe      // KBD_IN_STROBE
);

localparam DELAY = CLK_HZ / 3125;   // ~320 us

// small reply queue (mouse request answers with two bytes)
reg  [7:0] q [0:3];
reg  [1:0] q_wr = 0, q_rd = 0;
wire       q_empty = (q_wr == q_rd);

reg [15:0] wait_cnt = 0;
reg        second_mouse = 0;        // second RQMP byte goes out after the host's BACK
reg        host_strobe_d = 0;
wire       host_byte = host_strobe & ~host_strobe_d;   // new byte: rising edge only

always @(posedge clk) begin
   kbd_strobe    <= 1'b0;
   host_strobe_d <= host_strobe;

   if (reset) begin
      q_wr         <= 0;
      q_rd         <= 0;
      wait_cnt     <= 0;
      second_mouse <= 0;
   end else begin
      // host -> keyboard
      if (host_byte) begin
         casez (host_data)
            8'hFF: begin q[q_wr] <= 8'hFF; q_wr <= q_wr + 1'd1; end           // HRST
            8'hFE: begin q[q_wr] <= 8'hFE; q_wr <= q_wr + 1'd1; end           // RAK1
            8'hFD: begin q[q_wr] <= 8'hFD; q_wr <= q_wr + 1'd1; end           // RAK2
            8'h20: begin q[q_wr] <= 8'h81; q_wr <= q_wr + 1'd1; end           // RQID -> KBID
            8'h22: begin q[q_wr] <= 8'h00; q_wr <= q_wr + 1'd1; second_mouse <= 1'b1; end // RQMP
            8'h4?: begin q[q_wr] <= {4'hE, host_data[3:0]}; q_wr <= q_wr + 1'd1; end // RQPD -> PDAT
            8'h3F: if (second_mouse) begin                                    // BACK
                      q[q_wr] <= 8'h00; q_wr <= q_wr + 1'd1; second_mouse <= 1'b0;
                   end
            default: ;                                                       // LEDS, SACK, ...
         endcase
         wait_cnt <= DELAY[15:0];
      end

      // keyboard -> host, one byte per delay period
      if (wait_cnt != 0)
         wait_cnt <= wait_cnt - 1'd1;
      else if (~q_empty) begin
         kbd_data   <= q[q_rd];
         kbd_strobe <= 1'b1;
         q_rd       <= q_rd + 1'd1;
         wait_cnt   <= DELAY[15:0];
      end
   end
end

endmodule
