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

  // CPU inst
  logic                    W_R;
  logic [23:0]             bus_addr;
  logic [7:0]              CPU_DO, bus_data;
  logic [63:0]             internal_regs;

  logic [14:0]             counter;

  always_ff @ (posedge CLK_NES) begin
    if (~KEY[0])
      counter<=0;
    else if (counter < 26530)
      counter <= counter + 1;
  end

  T65 CPU (.Mode('0), .BCD_en('0), .Res_n(KEY[0]), .Enable(counter < 26530),
           .Clk(CLK_NES), .Rdy(1'b1), .IRQ_n(1'b1), .NMI_n(1'b1), .R_W_n(W_R),
           .A(bus_addr), .DI(bus_data), .DO(CPU_DO), .Regs(internal_regs));

  // PC to Hex Driver
  HexDriver PCA (internal_regs[63 -: 4], HEX3);
  HexDriver PCB (internal_regs[59 -: 4], HEX2);
  HexDriver PCC (internal_regs[55 -: 4], HEX1);
  HexDriver PCD (internal_regs[51 -: 4], HEX0);

  logic                    sysram_en;
  logic [7:0]              sysram_out, prgrom_out;

  system_ram SYSRAM (bus_addr[10:0], CLK_NESRAM, bus_data, sysram_en, sysram_out);
  prg_rom PRGROM (bus_addr[14:0], CLK_NESRAM, prgrom_out);

  databus BUS (.ADDR(bus_addr), .CPU_WR(W_R), .CPU_DO,
               .SYSRAM_Q(sysram_out), .PRGROM_Q(prgrom_out),
               .BUS_OUT(bus_data), .SYSRAM_EN(sysram_en));
endmodule // NES
