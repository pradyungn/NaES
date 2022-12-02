module ppu(input        ppu_clk,
           input        cpu_clk,
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

           output       nmi,
           output       VGA_HS, VGA_VS,
           output [3:0] VGA_R, VGA_G, VGA_B);

  // internal bus VRAM addr - you need to assign this in two
  // different writes to VRAM_ADDR i/o register

  logic [15:0]          VRAM_ADDR, scroll;
  logic [7:0]           OAM_ADDR, mask, status, control;

  logic                 ADDR_W, scroll_w; // tracks 1st vs second write to vram addr

  // pipelined and current versions of vram activity
  logic                 vram_active, vram_active_p;

  logic                 VRAM_ADDR_EN, OAM_ADDR_EN;
  logic                 scroll_en, mask_en, ctrl_en;
  logic                 STAT_EN;

  // register update logic
  always_ff @ (posedge ppu_clk) begin
    if (reset) begin
      VRAM_ADDR <= '0;
      ADDR_W <= '0;
      OAM_ADDR <= '0;
      scroll <= '0;
      mask <= '0;
      status <= '0;
      control <= '0;
      vram_active_p <= '0;

    end

    else begin
      vram_active_p <= vram_active;

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
        end else if (ADDR_W==1'b0 && ~vram_active && vram_active_p)
          VRAM_ADDR <= VRAM_ADDR + (control[2] ? 16'd32 : 16'd1);

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

      if (ctrl_en)
        control <= bus_din;

      if (mask_en)
        mask <= bus_din;

      if (STAT_EN)
        status[7] <= 1'b0;
      else if (dry[9:1]==8'd241 && drx[9:1]==8'd0)
        status[7] <= 1'b1;
      else if (dry==10'd524)
        status[7] <= 1'b0;
    end
  end


  // write-enable signals for RAM i/o interface
  logic                NMTA_EN, NMTB_EN, SPR_EN, palette_en;
  logic [4:0]          palette_addr;
  logic [7:0]          ROM_OUT, NMTA_OUT, NMTB_OUT, SPR_OUT;

  logic [7:0]          palette [31:0];

  // mirrored indices for palette RAM
  always_comb begin
    if(VRAM_ADDR[4:0]==5'h10 || VRAM_ADDR[4:0]==5'h14 || VRAM_ADDR[4:0]==5'h18 || VRAM_ADDR[4:0]==5'h1C)
      palette_addr = {1'b0,VRAM_ADDR[3:0]};
    else
      palette_addr = VRAM_ADDR[4:0];
  end

  // palette write logic
  always_ff @ (posedge ppu_clk)
    if (palette_en)
      palette[palette_addr] <= bus_din;

  // Vars for rendering
  logic [12:0] render_pattern_addr;
  logic [9:0]  render_nmt_addr;
  logic [7:0]  render_pattern_data, render_nmta_data, render_nmtb_data;

  // ram declarations
  chr_rom pattern (.address_a(VRAM_ADDR[12:0]), .clock_a(cpu_clk),
                   .wren_a(1'b0), .q_a(ROM_OUT),
                   .address_b(render_pattern_addr), .clock_b(vga_clk),
                   .wren_b(1'b0), .q_b(render_pattern_data));

  nametable nmt_a (.address_a(VRAM_ADDR[9:0]), .clock_a(cpu_clk),
                   .data_a(bus_din), .wren_a(NMTA_EN), .q_a(NMTA_OUT),
                   .address_b(render_nmt_addr), .clock_b(vga_clk),
                   .wren_b(1'b0), .q_b(render_nmta_data));

  nametable nmt_b (.address_a(VRAM_ADDR[9:0]), .clock_a(cpu_clk),
                   .data_a(bus_din), .wren_a(NMTB_EN), .q_a(NMTB_OUT),
                   .address_b(render_nmt_addr), .clock_b(vga_clk),
                   .wren_b(1'b0), .q_b(render_nmtb_data));

  spr_ram OAM (.address_a(OAM_ADDR), .clock_a(cpu_clk),
               .data_a(bus_din), .wren_a(SPR_EN), .q_a(SPR_OUT));

  // containerize the bus
  ppu_databus gfxbus (.ADDR(bus_addr), .WR(bus_wr), .CPU_DO(bus_din), .CHRROM_Q(ROM_OUT),
                      .NMTA_Q(NMTA_OUT), .NMTB_Q(NMTB_OUT), .SPR_Q(SPR_OUT), .STAT_Q(status),
                      .PALETTE(palette[palette_addr]), .VRAM_PREFIX(VRAM_ADDR[15:8]), .MIRROR(mirror_cfg),
                      .NMTA_EN(NMTA_EN), .NMTB_EN(NMTB_EN), .SPR_EN(SPR_EN), .MSK_EN(mask_en),
                      .STAT_EN(STAT_EN), .SCRLL_EN(scroll_en), .OAM_ADDR_EN(OAM_ADDR_EN), .CTRL_EN(ctrl_en),
                      .VRAM_ADDR_EN(VRAM_ADDR_EN), .PALETTE_EN(palette_en), .BUS_OUT(bus_out), .VRAM_ACTIVE(vram_active));

  logic hs, vs, blank;
  logic [9:0] drx, dry;

  vga_controller ITERATOR (.Clk(vga_clk), .Reset(reset),
                           .blank, .hs, .vs, .DrawX(drx), .DrawY(dry));
// NMI generation - pulls low based on VBL status flag and Control configuration
  assign nmi = ~(status[7] & control[7]);

  assign VGA_HS = hs;
  assign VGA_VS = vs;

  // color palette (colors)
  localparam logic [11:0] vga [0:63] = '{12'h777, 12'h00F, 12'h00B, 12'h42B,
                                       12'h908, 12'hA02, 12'hA10, 12'h810,
                                       12'h530, 12'h070, 12'h060, 12'h050,
                                       12'h045, 12'h000, 12'h000, 12'h000,
                                       12'hBBB, 12'h07F, 12'h05F, 12'h64F,
                                       12'hD0C, 12'hE05, 12'hF30, 12'hE51,
                                       12'hA70, 12'h0B0, 12'h0A0, 12'h0A4,
                                       12'h088, 12'h000, 12'h000, 12'h000,
                                       12'hFFF, 12'h3BF, 12'h68F, 12'h97F,
                                       12'hF7F, 12'hF59, 12'hF75, 12'hFA4,
                                       12'hFB0, 12'hBF1, 12'h5D5, 12'h5F9,
                                       12'h0ED, 12'h777, 12'h000, 12'h000,
                                       12'hFFF, 12'hAEF, 12'hBBF, 12'hDBF,
                                       12'hFBF, 12'hFAC, 12'hFDB, 12'hFEA,
                                       12'hFD7, 12'hDF7, 12'hBFB, 12'hBFD,
                                       12'h0FF, 12'hFDF, 12'h000, 12'h000};

  // intermediary to convert nametable/attribute address to nmta vs nmtb
  logic [9:0]            nt_addr, attr_addr;

  logic                   nt_en, altpat1_en, altpat2_en, alt_attr_en;
  logic [7:0]             nt_data;

  // next tile coords
  logic [4:0]             ndrx;
  logic [7:0]             ndry;

  // use always_comb to figure out memory stuff. use ff to latch data
  // Kinda FSM, but you don't actually need state - the pixel counter is in of itself
  // sufficient state.
  always_comb begin
    // address computation
    if (drx >= 496) begin
      ndrx = '0;

      if (dry >= 479)
        ndry = '0;
      else
        ndry = (dry + 10'd1)>>1;
    end else begin
      ndrx = drx[8:4] + 5'd1;
      ndry = dry[8:1];
    end // else: !if(drx >= 496)

    // record in either nametable as offset from 0
    nt_addr = ndry[7:3]*32 + ndrx;

    nt_en = 0;
    altpat1_en = 0;
    altpat2_en = 0;
    alt_attr_en = 0;

    render_nmt_addr = '0;
    render_pattern_addr = '0;
    nt_data = '0;

    unique case (drx[3:0])
      4'd0, 4'd1: begin
        nt_en = 1'b1;
        render_nmt_addr = nt_addr;

        if(control[1:0]==2'b0 || control[1]^mirror_cfg)
          nt_data = render_nmta_data;
        else
          nt_data = render_nmtb_data;
      end

      4'd4, 4'd5: begin
        altpat1_en = 1'b1;
        render_pattern_addr = {1'b0, nt, 1'b0, ndry[2:0]};
      end

      4'd6, 4'd7: begin
        altpat2_en = 1'b1;
        render_pattern_addr = {1'b1, nt, 1'b0, ndry[2:0]};
      end
    endcase
  end

  // Background Rendering
  logic [0:7]             pat1, pat2, attr;

  // Registers
  logic [0:7]             nt, altpat1, altpat2, alt_attr;

  // Latching Registers
  always_ff @ (posedge vga_clk) begin
    if(reset) begin
      nt <= '0;
      alt_attr <= '0;
      altpat1 <= '0;
      altpat2 <= '0;

      pat1 <= '0;
      pat2 <= '0;
      attr <= '0;
    end else begin
      if (drx[3:0]=='1) begin
        pat1 <= altpat1;
        pat2 <= altpat2;
        attr <= alt_attr;
      end

      if (altpat1_en)
        altpat1 <= render_pattern_data;

      if (altpat2_en)
        altpat2 <= render_pattern_data;

      if (alt_attr_en)
        alt_attr <= nt_data;

      if (nt_en)
        nt <= nt_data;
    end
  end

  // color output
  wire [11:0] color;
  always_comb begin
    color = vga[{pat1[drx[3:1]], pat2[drx[3:1]], 4'd0}];

    VGA_R = '0;
    VGA_G = '0;
    VGA_B = '0;

    if(~blank || (drx>511) || dry>(479)) begin
      VGA_R = '0;
      VGA_G = '0;
      VGA_B = '0;
    end

    else begin
      if (mask[3] && ((drx>>1)>8 || mask[1])) begin
        VGA_R = color[11:8];
        VGA_G = color[7:4];
        VGA_B = color[3:0];
      end
    end
  end

endmodule
