module KBcontroller (
                     input              CLK,
                     input              WR,
                     input              ENABLE,
                     input [7:0]        keycode, keycode2,
                     input [7:0]        bus,
                     output logic [7:0] DATA);

  logic [7:0]                           active1, active2, composite;

  adapter key1 (keycode, active1);
  adapter key2 (keycode, active2);

  assign composite = active1 | active2;

  logic [7:0]                           internal_data, internal_cmd;

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
