module databus (input [23:0] ADDR,
                input        CPU_WR,

                input [7:0]  CPU_DO,
                input [7:0] SYSRAM_Q,
                input [7:0] PRGROM_Q,
                input [7:0] CONTROL1,
                input [7:0] CONTROL2,

                output [7:0] BUS_OUT,

                output CONTROL1_EN,
                output CONTROL2_EN,
                output SYSRAM_EN);
  always_comb begin
    CONTROL1_EN = 0;
    CONTROL2_EN = 0;
    SYSRAM_EN = 0;
    if (ADDR<=24'h1FFF) begin
      SYSRAM_EN = CPU_WR;
      BUS_OUT = (CPU_WR) ? SYSRAM_Q : CPU_DO;
    end

    else if (ADDR>=24'h8000 && ADDR<=24'hFFFF)
      BUS_OUT = PRGROM_Q;

    else if (ADDR==24'h4016) begin
      CONTROL1_EN = 1'b1;
      BUS_OUT = (CPU_WR) ? CONTROL1 : CPU_DO;
    end

    else if (ADDR=24'h4017) begin
      CONTROL2_EN = 1'b1;
      BUS_OUT = (CPU_WR) ? CONTROL2 : CPU_DO;
    end

    else
      BUS_OUT = '0;
  end
endmodule // databus
