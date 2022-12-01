module ppu(input        ppu_clk,
           input        cpu_clk,
           input        nes_clk,
           input        vga_clk,

           input [15:0] bus_addr,
           input [7:0]  bus_din,
           input        bus_wr,

           input        odd_or_even,
           input        reset,

           output       dma_hijack,
           output       dma_addr,
           output [7:0] bus_out,

           input        mirror_cfg,

           output       nmi);

  // internal bus VRAM addr - you need to assign this in two
  // different writes to VRAM_ADDR i/o register

  logic [15:0]          VRAM_ADDR, scroll;
  logic [7:0]           OAM_ADDR, mask, status, control;

  logic                 ADDR_W, scoll_w; // tracks 1st vs second write to vram addr

  logic                 VRAM_ADDR_EN, OAM_ADDR_EN;
  logic                 scroll_en, mask_en, ctrl_en;
  logic                 STAT_EN;

  // register update logic
  always_ff @ (ppu_clk) begin
    if (reset) begin
      VRAM_ADDR <= '0;
      ADDR_W <= '0;
      OAM_ADDR <= '0;
      scroll <= '0;
      mask <= '0;
      status <= '0;
      control <= '0;
    end

    else begin
      if (STAT_EN) begin
        ADDR_W <= '0;
        VRAM_ADDR <= '0;
        scroll <= '0;
        scroll_w <= '0;
      end else begin
        if (VRAM_ADDR_EN) begin
          if (ADDR_W)
            VRAM_ADDR <= {VRAM_ADDR[7:0], bus_din};
          else
            VRAM_ADDR <= {8'd0, bus_din};

          ADDR_W <= ~ADDR_W;
        end

        if (scroll_en) begin
          if (scroll_w)
            scroll <= {scroll[7:0], bus_din};
          else
            scroll <= {8'd0, bus_din};

          scroll_w <= ~scroll_w;
        end
      end

      if (OAM_ADDR_EN)
        OAM_ADDR <= bus_din;

      if ctrl_en
        control <= bus_din;

      if mask_en
        mask <= bus_din;

      // add block for updating status register here
      if (STAT_EN)
        status[7] <= 1'b0;

    end
  end


  // write-enable signals for RAM i/o interface
  logic                NMTA_EN, NMTB_EN, SPR_EN, palette_en;
  logic [4:0]          palette_addr;
  logic [7:0]          ROM_OUT, NMTA_OUT, NMTB_OUT, SPR_OUT, palette_out;

  always_comb begin
    if(VRAM_ADDR[4:0]==5'h10 || VRAM_ADDR[4:0]==5'h14 || VRAM_ADDR[4:0]==5'h18 || VRAM_ADDR[4:0]==5'h1C)
      palette_addr = {1'b0,VRAM_ADDR[3:0]};
    else
      palette_addr = VRAM_ADDR[4:0];
  end

  // ram declarations
  chr_rom pattern (.address_a(INT_BUS_ADDR[12:0]), .clock_a(cpu_clk),
                   .data_a(bus_din), .wren_a(1'b0), .q_a(ROM_OUT));

  nametable nmt_a (.address_a(INT_BUS_ADDR[9:0]), .clock_a(cpu_clk),
                   .data_a(bus_din), .wren_a(NMTA_EN), .q_a(NMTA_OUT));

  nametable nmt_b (.address_a(INT_BUS_ADDR[9:0]), .clock_a(cpu_clk),
                   .data_a(bus_din), .wren_a(NMTB_EN), .q_a(NMTB_OUT));

  spr_ram OAM (.address_a(INT_BUS_ADDR[7:0]), .clock_a(cpu_clk),
               .data_a(bus_din), .wren_a(SPR_EN), .q_a(SPR_OUT));

  palette_ram palette (.address_a(palette_addr), .clock_a(cpu_clk),
               .data_a(bus_din), .wren_a(palette_en), .q_a(palette_out));

  // containerize the bus
  // REMEMBER TO CONNECT STATUS REGISTER
  ppu_databus gfxbus (.ADDR(bus_addr), .WR(bus_wr), .CPU_DO(bus_din), .CHRROM_Q(ROM_OUT),
                      .NMTA_Q(NMTA_OUT), .NMTB_Q(NMTB_OUT), .SPR_Q(SPR_OUT), .STAT_Q(__STAT__),
                      .PALETTE(palette_out), .VRAM_PREFIX(VRAM_ADDR[15:8]), .MIRROR(mirror_cfg),
                      .NMTA_EN(NMTA_EN), .NMTB_EN(NMTB_EN), .SPR_EN(SPR_EN), .MSK_EN(__MSK_EN__),
                      .STAT_EN(STAT_EN), .SCRLL_EN(__SCRLL_EN__), .OAM_ADDR_EN(OAM_ADDR_EN),
                      .VRAM_ADDR_EN(VRAM_ADDR_EN), .PALETTE_EN(palette_en));
endmodule
