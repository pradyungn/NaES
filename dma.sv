module dma (
            input         clk,
            input [15:0]  bus_addr,
            input [7:0]   bus_data,
            input         bus_wr,

            output        hijack,
            output [15:0] out_bus_addr,
            output [7:0]  oam_addr,

            output        oam_en
            );
  logic [7:0]             ctr, prefix;
  enum                    logic [1:0] {IDL, DLY, RD, WR} state, next;

  // use two-always method
  always_comb begin
    next = IDL;

    case (state)
      IDL:
        next = (bus_addr==16'h4014 && ~bus_wr) ? DLY : IDL;

      DLY: next = RD;
      RD: next = WR;

      WR:
        next = (ctr == '1) ? IDL : RD;

      default:
        next = IDL;
    endcase // case (state)
  end

  always_ff @ (posedge clk) begin
    state <= next;

    // latch prefix on activation
    if (next==DLY)
      prefix <= bus_data;

    // reset counter if going to RD from state, else
    // increment
    if (next == RD)
      ctr <= (state==DLY) ? '0 : ctr+8'd1;
  end

  assign out_bus_addr = {prefix, ctr};
  assign oam_addr = ctr;

  assign oam_en = (state==WR);

  assign hijack = (state == WR || state == RD);
 endmodule
