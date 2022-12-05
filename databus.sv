module databus (input [15:0] ADDR,
                input        CPU_WR,

                input [7:0]  CPU_DO,
                input [7:0]  SYSRAM_Q,
                input [7:0]  PRGROM_Q,
                input [7:0]  CONTROL1,
                input [7:0]  CONTROL2,
                input [7:0]  VIDEO_BUS,

                input        DMA,
                input [15:0]  DMA_ADDR,

                output [7:0] BUS_OUT,

                output       CONTROL1_EN,
                output       CONTROL2_EN,
                output       SYSRAM_EN);

  // internal ADDR
  logic [15:0]                INT_ADDR;

  always_comb begin
    INT_ADDR = DMA ? DMA_ADDR : ADDR;

    CONTROL1_EN = 0;
    CONTROL2_EN = 0;
    SYSRAM_EN = 0;

    if (INT_ADDR<=16'h1FFF) begin
      SYSRAM_EN = ~CPU_WR;
      BUS_OUT = (CPU_WR) ? SYSRAM_Q : CPU_DO;
    end

    // read-only prgrom
    else if (INT_ADDR>=16'h8000 && ADDR<=16'hFFFF)
      BUS_OUT = PRGROM_Q;

    else if (INT_ADDR==16'h4016) begin
      CONTROL1_EN = 1'b1;
      BUS_OUT = (CPU_WR) ? CONTROL1 : CPU_DO;
    end

    else if (INT_ADDR==16'h4017) begin
      CONTROL2_EN = 1'b1;
      BUS_OUT = (CPU_WR) ? CONTROL2 : CPU_DO;
    end

    else begin
      BUS_OUT = (CPU_WR) ? VIDEO_BUS : CPU_DO;
    end
  end
endmodule // databus
