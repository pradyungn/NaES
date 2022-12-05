module KBcontroller (
                     input              clk,
                     input              WR,
                     input              ENABLE,
                     input [7:0]        keycode, keycode2, keycode3,
                                        keycode4, keycode5, keycode6,
                     input [7:0]        bus,
                     output logic [7:0] DATA);

  logic [7:0]                           active1, active2, , active3, composite;
  logic [7:0]                           active4, active5, , active6;

  adapter key1 (keycode, active1);
  adapter key2 (keycode2, active2);
  adapter key3 (keycode3, active3);
  adapter key4 (keycode4, active4);
  adapter key5 (keycode5, active5);
  adapter key6 (keycode6, active6);

  assign composite = active1 | active2 | active3
                     active4 | active5 | active6;

  logic [7:0]                           internal='0;

  always @ (posedge clk) begin
    if (ENABLE) begin
      if(WR) begin
        DATA <= {7'd0, internal[0]};
        internal <= internal>>1;
      end else
        internal <= composite;
    end
  end
endmodule // KBcontroller

module adapter(input [7:0] keycode,
               output logic [7:0] active);
  //  GH (A/B) + TY (SEL/START) + WSAD
  active[7] = keycode==8'd10; //G
  active[6] = keycode==8'd11; //H
  active[5] = keycode==8'd23; //T
  active[4] = keycode==8'd28; //Y
  active[3] = keycode==8'd26; //W
  active[2] = keycode==8'd22; //S
  active[1] = keycode==8'd4;  //A
  active[0] = keycode==8'd7;  //D
endmodule
