// TOP LEVEL MODULE

module NES (
            input          MAX10_CLK1_50,

            ///////// KEY /////////
            input [ 1: 0]  KEY,

            ///////// SW /////////
            input [ 9: 0]  SW,

            ///////// LEDR /////////
            output [ 9: 0] LEDR,

            ///////// HEX /////////
            output [ 7: 0] HEX0,
            output [ 7: 0] HEX1,
            output [ 7: 0] HEX2,
            output [ 7: 0] HEX3,
            output [ 7: 0] HEX4,
            output [ 7: 0] HEX5,

            ///////// SDRAM /////////
            output         DRAM_CLK,
            output         DRAM_CKE,
            output [12: 0] DRAM_ADDR,
            output [ 1: 0] DRAM_BA,
            inout [15: 0]  DRAM_DQ,
            output         DRAM_LDQM,
            output         DRAM_UDQM,
            output         DRAM_CS_N,
            output         DRAM_WE_N,
            output         DRAM_CAS_N,
            output         DRAM_RAS_N,

            ///////// ARDUINO /////////
            inout [15: 0]  ARDUINO_IO,
            inout          ARDUINO_RESET_N
            );

  // Clocks for different components
  logic                    CLK_NES, CLK_NESRAM, CLK_PPU, CLK_VGA;

  main_pll PLL (.inclk0(MAX10_CLK1_50), .c0(CLK_NESRAM), .c1(CLK_NES),
                .c2(CLK_PPU), .c3(CLK_VGA));

  logic                    W_R;
  logic [23:0]             bus_addr;
  logic [7:0]              CPU_DI, CPU_DO;
  logic [63:0]             internal_regs;

  T65 CPU (.Mode('0), .BCD_en('0'), .Res_n(KEY[0]), .Enable(1'b1),
           .Clk(CLK_NES), .Rdy(1'b1), .IRQ_n(1'b1), .NMI_n(1'b1), .R_W_n(W_R),
           .A(bus_addr), .DI(CPU_DI), .DO(CPU_DO), .Regs(internal_regs));

endmodule // NES
