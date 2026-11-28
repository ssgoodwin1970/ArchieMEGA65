// Archimedes keyboard + mouse controller (what the MiSTer HPS used to emulate).
//
// RISC OS talks to the keyboard through IOC's serial port: KBD_OUT_* carries
// bytes from the host, KBD_IN_* bytes back to it. Protocol (Acorn A3000 TRM):
//
//   host -> keyboard                    keyboard -> host
//   HRST 0xFF  reset                    HRST 0xFF
//   RAK1 0xFE  reset ack 1              RAK1 0xFE
//   RAK2 0xFD  reset ack 2              RAK2 0xFD   (keyboard ready)
//   RQID 0x20  request ID               KBID 0x81
//   RQMP 0x22  request mouse position   X, (BACK), Y
//   RQPD 0x4x  request echo             PDAT 0xEx
//   LEDS 0x0x  set LEDs                 -
//   BACK 0x3F  byte ack (1st of a pair)
//   NACK 0x30 / SACK 0x31 / MACK 0x32 / SMAK 0x33:
//              ack of a 2-byte packet; also enables scanning:
//              bit0 = keys, bit1 = mouse
//
//   key down : 0xC0|row, (BACK), 0xC0|col, (xACK)     row/col = key code nibbles
//   key up   : 0xD0|row, (BACK), 0xD0|col, (xACK)
//   mouse    : 0x00|dx[6:0], (BACK), 0x00|dy[6:0], (xACK)
//
// MEGA65 input:
//   - key_num_i/key_pressed_n_i: the M2M scanner (all 80 keys, 1000x per second)
//   - 1351 mouse in port 1 (e.g. mouSTer with type=c1351): pot X/Y bits [6:1]
//     count position. Buttons like a real Acorn mouse:
//       fire = left = Select, down = middle = Menu, up = right = Adjust.
//     MEGA key = Menu as well, for 2-button mice.
//   - Amiga mouse in port 1 (e.g. mouSTer default type=amiga), detected
//     automatically the first time the left/right lines toggle (a 1351 never
//     uses them). Quadrature: H = down, HQ = right (X); V = up, VQ = left (Y).
//     Left button = fire = Select. Right/middle buttons arrive on the pot
//     lines (POTX/POTY): treated as pressed when the pot reading moves far
//     from its idle value. M2M debounces port 1 directions for 20 us only.
//
// Bytes to the host are sent ~320 us apart (a real keyboard at 31.25 kbaud).

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
   output reg       kbd_strobe,     // KBD_IN_STROBE

   input      [6:0] key_num_i,      // MEGA65 key number 0..79 (M2M scanner)
   input            key_pressed_n_i,

   input      [7:0] mouse_x_i,      // 1351: pot X
   input      [7:0] mouse_y_i,      // 1351: pot Y
   input            mouse_left_n_i,  // fire
   input            mouse_middle_n_i,// down
   input            mouse_right_n_i, // up
   input            joy_left_n_i,    // port 1 left  (Amiga VQ)
   input            joy_right_n_i    // port 1 right (Amiga HQ)
);

localparam DELAY = CLK_HZ / 3125;   // ~320 us between bytes

///////////////////////////////////////////////////////////////////////////////
// MEGA65 key number -> Archimedes key code (8'hFF = not mapped)
///////////////////////////////////////////////////////////////////////////////

function [7:0] arc_code(input [6:0] k);
   case (k)
      7'd0 : arc_code = 8'h1E;  // INST/DEL   -> Backspace
      7'd1 : arc_code = 8'h47;  // RETURN     -> Return
      7'd2 : arc_code = 8'h64;  // CRSR ->    -> Right
      7'd3 : arc_code = 8'h04;  // F7         -> F4
      7'd4 : arc_code = 8'h01;  // F1         -> F1
      7'd5 : arc_code = 8'h02;  // F3         -> F2
      7'd6 : arc_code = 8'h03;  // F5         -> F3
      7'd7 : arc_code = 8'h63;  // CRSR down  -> Down
      7'd8 : arc_code = 8'h13;  // 3
      7'd9 : arc_code = 8'h28;  // W
      7'd10: arc_code = 8'h3C;  // A
      7'd11: arc_code = 8'h14;  // 4
      7'd12: arc_code = 8'h4E;  // Z
      7'd13: arc_code = 8'h3D;  // S
      7'd14: arc_code = 8'h29;  // E
      7'd15: arc_code = 8'h4C;  // left SHIFT
      7'd16: arc_code = 8'h15;  // 5
      7'd17: arc_code = 8'h2A;  // R
      7'd18: arc_code = 8'h3E;  // D
      7'd19: arc_code = 8'h16;  // 6
      7'd20: arc_code = 8'h50;  // C
      7'd21: arc_code = 8'h3F;  // F
      7'd22: arc_code = 8'h2B;  // T
      7'd23: arc_code = 8'h4F;  // X
      7'd24: arc_code = 8'h17;  // 7
      7'd25: arc_code = 8'h2C;  // Y
      7'd26: arc_code = 8'h40;  // G
      7'd27: arc_code = 8'h18;  // 8
      7'd28: arc_code = 8'h52;  // B
      7'd29: arc_code = 8'h41;  // H
      7'd30: arc_code = 8'h2D;  // U
      7'd31: arc_code = 8'h51;  // V
      7'd32: arc_code = 8'h19;  // 9
      7'd33: arc_code = 8'h2E;  // I
      7'd34: arc_code = 8'h42;  // J
      7'd35: arc_code = 8'h1A;  // 0
      7'd36: arc_code = 8'h54;  // M
      7'd37: arc_code = 8'h43;  // K
      7'd38: arc_code = 8'h2F;  // O
      7'd39: arc_code = 8'h53;  // N
      7'd40: arc_code = 8'h1C;  // +          -> = +
      7'd41: arc_code = 8'h30;  // P
      7'd42: arc_code = 8'h44;  // L
      7'd43: arc_code = 8'h1B;  // -          -> - _
      7'd44: arc_code = 8'h56;  // .
      7'd45: arc_code = 8'h45;  // :          -> ; :
      7'd46: arc_code = 8'h31;  // @          -> [ {
      7'd47: arc_code = 8'h55;  // ,
      7'd48: arc_code = 8'h1D;  // pound      -> pound
      7'd49: arc_code = 8'h32;  // *          -> ] }
      7'd50: arc_code = 8'h46;  // ;          -> ' @
      7'd51: arc_code = 8'h20;  // CLR/HOME   -> Home
      7'd52: arc_code = 8'h58;  // right SHIFT
      7'd53: arc_code = 8'h33;  // =          -> \ |
      7'd54: arc_code = 8'h34;  // up arrow   -> Delete
      7'd55: arc_code = 8'h57;  // /
      7'd56: arc_code = 8'h11;  // 1
      7'd57: arc_code = 8'h10;  // left arrow -> ` ~
      7'd58: arc_code = 8'h3B;  // CTRL
      7'd59: arc_code = 8'h12;  // 2
      7'd60: arc_code = 8'h5F;  // SPACE
      7'd61: arc_code = 8'h71;  // MEGA       -> Menu (middle mouse button)
      7'd62: arc_code = 8'h27;  // Q
      7'd63: arc_code = 8'h0C;  // RUN/STOP   -> F12 (command line)
      7'd64: arc_code = 8'h0E;  // NO SCROLL  -> Scroll Lock
      7'd65: arc_code = 8'h26;  // TAB
      7'd66: arc_code = 8'h5E;  // ALT        -> Alt
      7'd68: arc_code = 8'h05;  // F9         -> F5
      7'd69: arc_code = 8'h06;  // F11        -> F6
      7'd70: arc_code = 8'h07;  // F13        -> F7
      7'd71: arc_code = 8'h00;  // ESC        -> Escape
      7'd72: arc_code = 8'h5D;  // CAPS LOCK
      7'd73: arc_code = 8'h59;  // CRSR up    -> Up
      7'd74: arc_code = 8'h62;  // CRSR left  -> Left
      7'd75: arc_code = 8'h0F;  // RESTORE    -> Break
      default: arc_code = 8'hFF; // HELP (67) is the M2M menu key; 76..79 unused
   endcase
endfunction

///////////////////////////////////////////////////////////////////////////////
// Mouse movement: 1351 (pot lines) or Amiga (quadrature on the direction lines)
///////////////////////////////////////////////////////////////////////////////

reg  [5:0] mx_old = 0, my_old = 0;
reg signed [9:0] mx_acc = 0, my_acc = 0;
wire signed [5:0] mx_d = $signed(mouse_x_i[6:1] - mx_old);
wire signed [5:0] my_d = $signed(mouse_y_i[6:1] - my_old);
reg [15:0] mdiv = 0;
reg        mouse_take;              // mouse packet sent: clear what was reported
reg signed [6:0] m_dx, m_dy;        // values being sent

// Amiga detection and quadrature decoding
reg        amiga = 1'b0;
reg  [1:0] lr_old = 2'b11;
reg  [1:0] qx_old = 2'b11, qy_old = 2'b11;      // {H, HQ}, {V, VQ}
wire [1:0] qx = {mouse_middle_n_i, joy_right_n_i}; // down = H,  right = HQ
wire [1:0] qy = {mouse_right_n_i,  joy_left_n_i};  // up   = V,  left  = VQ

// one quadrature step: +1 / -1 / 0 (no change or invalid double change)
function signed [1:0] qstep(input [1:0] o, input [1:0] n);
   case ({o, n})
      4'b00_01, 4'b01_11, 4'b11_10, 4'b10_00: qstep =  2'sd1;
      4'b00_10, 4'b10_11, 4'b11_01, 4'b01_00: qstep = -2'sd1;
      default:                                qstep =  2'sd0;
   endcase
endfunction
wire signed [1:0] qdx = qstep(qx_old, qx);
wire signed [1:0] qdy = qstep(qy_old, qy);

function signed [6:0] clamp7(input signed [9:0] v);
   clamp7 = (v > 63) ? 7'sd63 : (v < -64) ? -7'sd64 : v[6:0];
endfunction

always @(posedge clk) begin
   mdiv   <= mdiv + 1'd1;
   lr_old <= {joy_left_n_i, joy_right_n_i};
   qx_old <= qx;
   qy_old <= qy;
   if (reset) begin
      mx_acc <= 0; my_acc <= 0;
      mx_old <= mouse_x_i[6:1]; my_old <= mouse_y_i[6:1];
   end else begin
      // a 1351 never toggles left/right: if they toggle, it is an Amiga mouse
      if (lr_old != {joy_left_n_i, joy_right_n_i}) amiga <= 1'b1;

      if (amiga) begin
         // Amiga: every quadrature edge is one count (Y: up is positive on the Archimedes)
         mx_acc <= mx_acc + qdx - (mouse_take ? m_dx : 7'sd0);
         my_acc <= my_acc - qdy - (mouse_take ? m_dy : 7'sd0);
      end else if (mdiv == 0) begin
         // 1351: sample the pots about every 1.5 ms; ignore jumps (noise / no mouse)
         if (mx_d > -6'sd16 && mx_d < 6'sd16) mx_acc <= mx_acc + mx_d - (mouse_take ? m_dx : 7'sd0);
         else                                  mx_acc <= mx_acc - (mouse_take ? m_dx : 7'sd0);
         if (my_d > -6'sd16 && my_d < 6'sd16) my_acc <= my_acc + my_d - (mouse_take ? m_dy : 7'sd0);
         else                                  my_acc <= my_acc - (mouse_take ? m_dy : 7'sd0);
         mx_old <= mouse_x_i[6:1];
         my_old <= mouse_y_i[6:1];
      end else if (mouse_take) begin
         mx_acc <= mx_acc - m_dx;
         my_acc <= my_acc - m_dy;
      end
   end
end

// Amiga right/middle buttons on the pot lines: pressed = reading far from idle
reg  [7:0] potx_idle = 8'h00, poty_idle = 8'h00;
reg        pot_learned = 1'b0;
reg [21:0] pot_wait = 0;
function [7:0] absdiff(input [7:0] a, input [7:0] b);
   absdiff = (a > b) ? a - b : b - a;
endfunction
always @(posedge clk) begin
   if (reset) begin
      pot_learned <= 1'b0;
      pot_wait    <= 0;
   end else if (!pot_learned) begin
      pot_wait <= pot_wait + 1'd1;
      if (&pot_wait) begin                       // ~0.1 s after reset: learn idle readings
         potx_idle   <= mouse_x_i;
         poty_idle   <= mouse_y_i;
         pot_learned <= 1'b1;
      end
   end
end
wire amiga_right  = amiga && pot_learned && (absdiff(mouse_x_i, potx_idle) > 8'd64);
wire amiga_middle = amiga && pot_learned && (absdiff(mouse_y_i, poty_idle) > 8'd64);

// buttons as seen by the Archimedes (low active)
wire btn_menu_n   = amiga ? ~amiga_middle : mouse_middle_n_i;
wire btn_adjust_n = amiga ? ~amiga_right  : mouse_right_n_i;

///////////////////////////////////////////////////////////////////////////////
// Key events: compare the scanner with the last state we reported
///////////////////////////////////////////////////////////////////////////////

reg  [79:0] reported = 80'd0;       // 1 = Archimedes was told "down"
reg  [8:0]  evq [0:15];             // {up, code}
reg  [3:0]  evq_wr = 0, evq_rd = 0;
wire        evq_empty = (evq_wr == evq_rd);
wire        evq_full  = (evq_wr + 1'd1 == evq_rd);

wire        key_down  = ~key_pressed_n_i;
wire [7:0]  key_code  = arc_code(key_num_i);
reg         evq_pop;

// mouse buttons are reported like keys
reg         ml_rep = 0, mm_rep = 0, mr_rep = 0;

always @(posedge clk) begin
   if (reset) begin
      reported <= 80'd0;
      evq_wr   <= 0;
      evq_rd   <= 0;
      ml_rep   <= 0;
      mm_rep   <= 0;
      mr_rep   <= 0;
   end else begin
      if (evq_pop) evq_rd <= evq_rd + 1'd1;

      if (!evq_full && key_num_i < 7'd80 && key_code != 8'hFF && key_down != reported[key_num_i]) begin
         evq[evq_wr]          <= {~key_down, key_code};
         evq_wr               <= evq_wr + 1'd1;
         reported[key_num_i]  <= key_down;
      end else if (!evq_full && ~mouse_left_n_i != ml_rep) begin
         evq[evq_wr] <= {mouse_left_n_i, 8'h70};        // Select
         evq_wr      <= evq_wr + 1'd1;
         ml_rep      <= ~mouse_left_n_i;
      end else if (!evq_full && ~btn_menu_n != mm_rep) begin
         evq[evq_wr] <= {btn_menu_n, 8'h71};            // Menu
         evq_wr      <= evq_wr + 1'd1;
         mm_rep      <= ~btn_menu_n;
      end else if (!evq_full && ~btn_adjust_n != mr_rep) begin
         evq[evq_wr] <= {btn_adjust_n, 8'h72};          // Adjust
         evq_wr      <= evq_wr + 1'd1;
         mr_rep      <= ~btn_adjust_n;
      end
   end
end

///////////////////////////////////////////////////////////////////////////////
// Protocol
///////////////////////////////////////////////////////////////////////////////

reg        host_strobe_d = 0;
wire       host_byte = host_strobe & ~host_strobe_d;   // new byte: rising edge only

// replies to host commands (highest priority)
reg  [7:0] rq [0:3];
reg  [1:0] rq_wr = 0, rq_rd = 0;
wire       rq_empty = (rq_wr == rq_rd);

reg        keys_en  = 0;            // SACK/SMAK
reg        mouse_en = 0;            // MACK/SMAK
reg        rqmp_second = 0;         // RQMP: second byte goes out after BACK

// data packet state: a packet is 2 bytes, BACK between them, xACK after
localparam P_IDLE = 2'd0, P_WAIT_BACK = 2'd1, P_SEND2 = 2'd2, P_WAIT_ACK = 2'd3;
reg  [1:0] pstate = P_IDLE;
reg  [7:0] pbyte2;
reg        pkt_is_mouse;

reg [15:0] wait_cnt = 0;

always @(posedge clk) begin
   kbd_strobe    <= 1'b0;
   host_strobe_d <= host_strobe;
   evq_pop       <= 1'b0;
   mouse_take    <= 1'b0;

   if (reset) begin
      rq_wr <= 0; rq_rd <= 0;
      keys_en <= 0; mouse_en <= 0; rqmp_second <= 0;
      pstate <= P_IDLE;
      wait_cnt <= 0;
   end else begin
      // ---------------- host -> keyboard ----------------
      if (host_byte) begin
         casez (host_data)
            8'hFF: begin                                                     // HRST
                      rq[rq_wr] <= 8'hFF; rq_wr <= rq_wr + 1'd1;
                      keys_en <= 0; mouse_en <= 0; pstate <= P_IDLE;
                   end
            8'hFE: begin rq[rq_wr] <= 8'hFE; rq_wr <= rq_wr + 1'd1; end      // RAK1
            8'hFD: begin rq[rq_wr] <= 8'hFD; rq_wr <= rq_wr + 1'd1; end      // RAK2
            8'h20: begin rq[rq_wr] <= 8'h81; rq_wr <= rq_wr + 1'd1; end      // RQID -> KBID
            8'h22: begin                                                     // RQMP
                      rq[rq_wr] <= {1'b0, clamp7(mx_acc)}; rq_wr <= rq_wr + 1'd1;
                      rqmp_second <= 1'b1;
                   end
            8'h4?: begin rq[rq_wr] <= {4'hE, host_data[3:0]}; rq_wr <= rq_wr + 1'd1; end
            8'h3F: begin                                                     // BACK
                      if (rqmp_second) begin
                         rq[rq_wr] <= {1'b0, clamp7(my_acc)}; rq_wr <= rq_wr + 1'd1;
                         rqmp_second <= 1'b0;
                      end else if (pstate == P_WAIT_BACK)
                         pstate <= P_SEND2;
                   end
            8'b0011_00??: begin                                              // NACK/SACK/MACK/SMAK
                      keys_en  <= host_data[0];
                      mouse_en <= host_data[1];
                      if (pstate == P_WAIT_ACK) pstate <= P_IDLE;
                   end
            default: ;                                                       // LEDS etc.
         endcase
         wait_cnt <= DELAY[15:0];
      end

      // ---------------- keyboard -> host ----------------
      if (wait_cnt != 0)
         wait_cnt <= wait_cnt - 1'd1;
      else if (!rq_empty) begin
         kbd_data   <= rq[rq_rd];
         kbd_strobe <= 1'b1;
         rq_rd      <= rq_rd + 1'd1;
         wait_cnt   <= DELAY[15:0];
      end else if (pstate == P_SEND2) begin
         kbd_data   <= pbyte2;
         kbd_strobe <= 1'b1;
         pstate     <= P_WAIT_ACK;
         wait_cnt   <= DELAY[15:0];
      end else if (pstate == P_IDLE && keys_en && !evq_empty) begin
         // key packet: {D/U, row} then {D/U, col}
         kbd_data     <= {3'b110, evq[evq_rd][8], evq[evq_rd][7:4]};
         pbyte2       <= {3'b110, evq[evq_rd][8], evq[evq_rd][3:0]};
         kbd_strobe   <= 1'b1;
         evq_pop      <= 1'b1;
         pkt_is_mouse <= 1'b0;
         pstate       <= P_WAIT_BACK;
         wait_cnt     <= DELAY[15:0];
      end else if (pstate == P_IDLE && mouse_en && (clamp7(mx_acc) != 0 || clamp7(my_acc) != 0)) begin
         m_dx         <= clamp7(mx_acc);
         m_dy         <= clamp7(my_acc);
         kbd_data     <= {1'b0, clamp7(mx_acc)};
         pbyte2       <= {1'b0, clamp7(my_acc)};
         mouse_take   <= 1'b1;
         kbd_strobe   <= 1'b1;
         pkt_is_mouse <= 1'b1;
         pstate       <= P_WAIT_BACK;
         wait_cnt     <= DELAY[15:0];
      end
   end
end

endmodule
