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

            ///////// VGA /////////
            output             VGA_HS,
            output             VGA_VS,
            output   [ 3: 0]   VGA_R,
            output   [ 3: 0]   VGA_G,
            output   [ 3: 0]   VGA_B,

            ///////// ARDUINO /////////
            inout [15: 0]  ARDUINO_IO,
            inout          ARDUINO_RESET_N
            );

  // Clocks for different components
  logic                    CLK_NES, CLK_NESRAM, CLK_PPU, CLK_VGA;

  logic                    SPI0_CS_N, SPI0_SCLK, SPI0_MISO, SPI0_MOSI, USB_GPX, USB_IRQ, USB_RST;
  logic [23:0]             nios_hex;
  logic [7:0]             nios_keycode, keycode2, keycode3;

  //=======================================================
  //  Structural coding
  //=======================================================
  assign ARDUINO_IO[10] = SPI0_CS_N;
  assign ARDUINO_IO[13] = SPI0_SCLK;
  assign ARDUINO_IO[11] = SPI0_MOSI;
  assign ARDUINO_IO[12] = 1'bZ;
  assign SPI0_MISO = ARDUINO_IO[12];

  assign ARDUINO_IO[9] = 1'bZ;
  assign USB_IRQ = ARDUINO_IO[9];

  //Assignments specific to Circuits At Home UHS_20
  assign ARDUINO_RESET_N = USB_RST;
  assign ARDUINO_IO[7] = USB_RST;//USB reset
  assign ARDUINO_IO[8] = 1'bZ; //this is GPX (set to input)
  assign USB_GPX = 1'b0;//GPX is not needed for standard USB host - set to 0 to prevent interrupt
  //Assign uSD CS to '1' to prevent uSD card from interfering with USB Host (if uSD card is plugged in)
  assign ARDUINO_IO[6] = 1'b1;

  nios ian_soc (.clk_clk(MAX10_CLK1_50), .cpu_clk(CLK_NES), .hex_wire_export(nios_hex),
                .key_wire_export(KEY), .keycode_export(nios_keycode),
                .led_wire_export(LEDR), .nes_clk(CLK_NESRAM), .ppu_clk(CLK_PPU),
                .reset_reset_n(KEY[0]), .sdram_clk_clk(DRAM_CLK), .sdram_wire_addr(DRAM_ADDR),
                .sdram_wire_ba(DRAM_BA), .sdram_wire_cas_n(DRAM_CAS_N), .sdram_wire_cke(DRAM_CKE),
                .sdram_wire_cs_n(DRAM_CS_N), .sdram_wire_dq(DRAM_DQ), .sdram_wire_ras_n(DRAM_RAS_N),
                .sdram_wire_we_n(DRAM_WE_N), .spi0_SS_n(SPI0_CS_N), .spi0_MOSI(SPI0_MOSI),
                .spi0_MISO(SPI0_MISO), .spi0_SCLK(SPI0_SCLK), .sw_wire_export(SW),
                .usb_gpx_export(USB_GPX), .usb_irq_export(USB_IRQ), .usb_rst_export(USB_RST),
                .vga_clk(CLK_VGA), .sdram_wire_dqm({DRAM_UDQM, DRAM_LDQM}),
                .keycode2_export(keycode2), .keycode3_export(keycode3));

  // 0 for horiz
  localparam logic         MIRRORING = 1'b1;

  // CPU inst
  logic                    W_R;
  logic [23:0]             bus_addr;
  logic [7:0]              CPU_DO, bus_data;
  logic [63:0]             internal_regs;

  // cycle tracking
  logic odd_or_even = 1'b1;

  logic                    NMI, DMA;
  T65 CPU (.Mode('0), .BCD_en('0), .Res_n(KEY[0]), .Enable(~DMA),
           .Clk(CLK_NES), .Rdy(1'b1), .IRQ_n(1'b1), .NMI_n(NMI), .R_W_n(W_R),
           .A(bus_addr), .DI(bus_data), .DO(CPU_DO), .Regs(internal_regs));

  // PC to Hex Driver
  HexDriver PCA (internal_regs[63 -: 4], HEX3);
  HexDriver PCB (internal_regs[59 -: 4], HEX2);
  HexDriver PCC (internal_regs[55 -: 4], HEX1);
  HexDriver PCD (internal_regs[51 -: 4], HEX0);

  HexDriver PCE (c1_c[7 -: 4], HEX5);
  HexDriver PCF (c1_c[3 -: 4], HEX4);

  logic                    sysram_en, c1_en;
  logic [7:0]              sysram_out, prgrom_out, c1_o, c1_c;
  logic [7:0]              PPU_BUS=0;
  logic [15:0]              DMA_ADDR, INT_ADDR;

  KBcontroller control1 (.clk(CLK_NESRAM), .WR(W_R), .ENABLE(c1_en),
                         .keycode(nios_keycode), .keycode2, .keycode3,
                         .bus(bus_data), .DATA(c1_o), .COMP(c1_c));

  system_ram SYSRAM (INT_ADDR[10:0], CLK_NESRAM, bus_data, sysram_en, sysram_out);
  prg_rom PRGROM (INT_ADDR[14:0], CLK_NESRAM, prgrom_out);

  ppu RICOH (.ppu_clk(CLK_PPU), .cpu_clk(CLK_NES), .vga_clk(CLK_VGA),
             .bus_addr(bus_addr), .bus_din(bus_data), .bus_wr(W_R),
             .odd_or_even(odd_or_even), .reset(~KEY[0]), .bus_out(PPU_BUS),
             .mirror_cfg(MIRRORING), .VGA_HS, .VGA_VS, .VGA_R, .VGA_G, .VGA_B,
             .nmi(NMI), .ram_clk(CLK_NESRAM), .dma_hijack(DMA), .dma_addr(DMA_ADDR));

  databus BUS (.ADDR(bus_addr), .CPU_WR(W_R), .CPU_DO,
               .SYSRAM_Q(sysram_out), .PRGROM_Q(prgrom_out),
               .BUS_OUT(bus_data), .SYSRAM_EN(sysram_en),
               .VIDEO_BUS(PPU_BUS), .DMA, .DMA_ADDR, .INT_ADDR,
               .CONTROL1(c1_o), .CONTROL1_EN(c1_en));
endmodule // NES
