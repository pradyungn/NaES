module KBcontroller (
                     input              clk,
                     input              WR,
                     input              ENABLE,
                     input [7:0]        keycode, keycode2, keycode3,
                                        keycode4, keycode5, keycode6,
                     input [7:0]        bus,
                     output logic [7:0] DATA,
                     output [7:0]       COMP);

  logic [7:0]                           active1, active2, active3, composite;
  logic [7:0]                           active4, active5, active6;

  logic                                 SRP;

  adapter key1 (keycode, active1);
  adapter key2 (keycode2, active2);
  adapter key3 (keycode3, active3);
  adapter key4 (keycode4, active4);
  adapter key5 (keycode5, active5);
  adapter key6 (keycode6, active6);

  assign composite = active1 | active2 | active3 |
                     active4 | active5 | active6;
  assign COMP = composite;

  logic [7:0]                           internal='0;
  logic                                 shift_en;

  assign shift_en = ENABLE && WR;

  always @ (posedge clk) begin
    SRP <= shift_en;

    if(shift_en && ~SRP) begin
      DATA <= {7'd0, internal[7]};
      internal <= {internal[6:0], 1'b1};
    end else if (~WR && ENABLE)
      internal <= composite;
  end
endmodule // KBcontroller

module adapter(input [7:0] keycode,
               output logic [7:0] active);
  //  GH (A/B) + TY (SEL/START) + WSAD
  assign active[7] = keycode==8'd10; //G
  assign active[6] = keycode==8'd11; //H
  assign active[5] = keycode==8'd23; //T
  assign active[4] = keycode==8'd28; //Y
  assign active[3] = keycode==8'd26; //W
  assign active[2] = keycode==8'd22; //S
  assign active[1] = keycode==8'd4;  //A
  assign active[0] = keycode==8'd7;  //D
endmodule
