//  ____  _   _
// |  _ \| \ | | Pradyun Narkadamilli
// | |_) |  \| | https://pradyun.tech
// |  __/| |\  | MIT License
// |_|   |_| \_| Copyright 2022 Pradyun Narkadamilli

module ppu(input        ppu_clk,
           input              cpu_clk,
           input              ram_clk,
           input              vga_clk,

           input [15:0]       bus_addr,
           input [7:0]        bus_din,
           input              bus_wr,

           input              odd_or_even,
           input              reset,

           output             dma_hijack,
           output      [15:0] dma_addr,
           output logic [7:0] bus_out,

           input              mirror_cfg,

           output             nmi,
           output             VGA_HS, VGA_VS,
           output [3:0]       VGA_R, VGA_G, VGA_B,
           output [7:0]       feedback);

  // internal bus VRAM addr - you need to assign this in two
  // different writes to VRAM_ADDR i/o register

  logic [15:0]                vram_addr, scroll;
  logic [7:0]                 oam_addr, mask, status, control;

  logic                       addr_w, scroll_w; // tracks 1st vs second write to vram addr
  logic                       incr, oam_incr; // pipelined incrementation signal for vram/oam

  logic [7:0]                 palette [31:0];
  logic [4:0]                 palette_addr;

  // mirrored indices for palette RAM
  always_comb begin
    if(vram_addr[4:0]==5'h10 || vram_addr[4:0]==5'h14 || vram_addr[4:0]==5'h18 || vram_addr[4:0]==5'h1C)
      palette_addr = {1'b0,vram_addr[3:0]};
    else
      palette_addr = vram_addr[4:0];
  end

  // Vars for rendering
  logic [12:0] render_pattern_addr;
  logic [9:0]  render_nmt_addr;
  logic [7:0] fetch_addr, fetch_out;
  logic [7:0]  render_pattern_data, render_nmta_data, render_nmtb_data;

  // write-enable/data signals for RAM i/o interface
  logic        nmta_en, nmtb_en, oam_en;
  logic [7:0]  nmta_out, nmtb_out, oam_out, pattern_out;

  // DMA submodule
  logic [7:0]  dma_oam_addr;
  logic dma_oam_en;

  dma DIRMA (.clk(cpu_clk), .bus_addr, .bus_data(bus_din), .bus_wr,
             .hijack(dma_hijack), .out_bus_addr(dma_addr), .oam_addr(dma_oam_addr),
             .oam_en(dma_oam_en));

  // ram declarations
  chr_rom pattern (.address_a(vram_addr[12:0]), .clock_a(ram_clk),
                   .wren_a(1'b0), .q_a(pattern_out),
                   .address_b(render_pattern_addr), .clock_b(vga_clk),
                   .wren_b(1'b0), .q_b(render_pattern_data));

  nametable nmt_a (.address_a(vram_addr[9:0]), .clock_a(ram_clk),
                   .data_a(bus_din), .wren_a(nmta_en), .q_a(nmta_out),
                   .address_b(render_nmt_addr), .clock_b(vga_clk),
                   .wren_b(1'b0), .q_b(render_nmta_data));

  nametable nmt_b (.address_a(vram_addr[9:0]), .clock_a(ram_clk),
                   .data_a(bus_din), .wren_a(nmtb_en), .q_a(nmtb_out),
                   .address_b(render_nmt_addr), .clock_b(vga_clk),
                   .wren_b(1'b0), .q_b(render_nmtb_data));

  spr_ram OAM (.address_a((dma_hijack ? dma_oam_addr : oam_addr)), .clock_a(ram_clk), .data_a(bus_din),
               .wren_a(((oam_en && ~dma_hijack) || (dma_oam_en && dma_hijack))), .q_a(oam_out),
               .address_b(render_nmt_addr), .clock_b(vga_clk), .wren_b(1'b0), .q_b(fetch_out));

  always_ff @ (posedge cpu_clk) begin
    // Don't increment by default
    incr <= 0;
    oam_incr <= 0;

    if (incr)
      vram_addr <= vram_addr + (control[2] ? 8'd32 : 8'd1);

    if ((drx>=514 && drx <= 641) && (dry<480 || dry==524))
      oam_addr <= '0;
    else if (oam_incr)
      oam_addr <= oam_addr + 1'b1;

    if (reset) begin
      mask <= '0;
      control <= '0;
      status <= '0;
      oam_addr <= '0;

      scroll <= '0;
      vram_addr <= '0;

      addr_w <= 0;
      scroll_w <= 0;

      bus_out <= 0;
    end else begin
      // separate event control for VBL flag - we need explicit
      // event control. This backshifts priority handling
      // and avoids the (VBL flag only set when bus-not-in-use)
      // issue. This could be why I'm dropping frames here and there.
      if (bus_addr >= 16'h2000 && bus_addr <= 16'h3FFF && bus_addr[2:0]==3'd2 && bus_wr)
        status[7] <= 0;
      else if(dry[8:1]==9'd240 && drx[9:4]=='0)
        status[7] <= 1'b1;
      else if (dry == 10'd520)
        status[7] <= 1'b0;

      // case statement for isolated behaviors
      if (bus_addr >= 16'h2000 && bus_addr <= 16'h3FFF) begin
        case (bus_addr[2:0])
          3'd0: if (~bus_wr)
            control <= bus_din;
          3'd1: if (~bus_wr)
            mask <= bus_din;
          3'd2: if(bus_wr) begin
            bus_out <= status;

            vram_addr <= '0;
            scroll <= '0;

            addr_w <= 0;
            scroll_w <= 0;
          end
          3'd4: begin
            if (bus_wr)
              bus_out <= oam_out;
            else
              oam_incr <= 1'b1;
          end

          3'd5: if (~bus_wr)
            begin
              scroll_w <= ~scroll_w;

              if(~scroll_w)
                scroll[15:8] <= bus_din;
              else
                scroll[7:0] <= bus_din;
            end
          3'd6: if (~bus_wr)
            begin
              addr_w <= ~addr_w;

              if(~addr_w)
                vram_addr[15:8] <= bus_din;
              else
                vram_addr[7:0] <= bus_din;
            end
          3'd7: begin
            incr <= 1;

            if (vram_addr <= 16'h1FFF) begin
              if(bus_wr)
                bus_out <= pattern_out;
            end else if (vram_addr >= 16'h2000 && vram_addr <= 16'h3EFF) begin
              if (vram_addr[11:10] == 2'd0 ||
                  (vram_addr[11:10]>=2'd1 && ~mirror_cfg) ||
                  (vram_addr[11:10]==4'h2 && mirror_cfg)) begin
                bus_out <= nmta_out;
              end else begin
                bus_out <= nmtb_out;
              end
            end else if (vram_addr>=16'h3F00 && vram_addr <= 16'h3FFF) begin
              if (bus_wr)
                bus_out <= palette[palette_addr];
              else
                palette[palette_addr] <= bus_din;
            end else
              bus_out <= '0;
          end // case: 3'd7
        endcase
      end // if (bus_addr >= 16'h2000 && bus_addr <= 16'h3FFF)

    end // else: !if(reset)
  end

  // Combination RAM Write signals (doing in FF causes pipeline effect)
  always_comb begin
    nmta_en = 0;
    nmtb_en = 0;
    oam_en = 0;

    if (bus_addr >= 16'h2000 && bus_addr <= 16'h3FFF) begin
      unique case (bus_addr[2:0])
        3'd4: oam_en = ~bus_wr;

        3'd7: begin
          if (vram_addr >=16'h2000 && vram_addr <= 16'h3EFF) begin
            if (vram_addr[11:10] == 2'd0 ||
                (vram_addr[11:10]>=2'd1 && ~mirror_cfg) ||
                (vram_addr[11:10]==4'h2 && mirror_cfg))
              nmta_en = ~bus_wr;
            else
              nmtb_en = ~bus_wr;
          end
        end

        default: begin
          nmta_en = 0;
          nmtb_en = 0;
          oam_en = 0;
        end
      endcase
    end
  end


  ////////////////////////////////////////////////////////////
  //               RENDERING LOGIC                          //
  ////////////////////////////////////////////////////////////

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
  logic [9:0]             nt_addr, attr_addr;

  logic                   nt_en, altpat1_en, altpat2_en, alt_attr_en;
  logic [7:0]             nt_data;

  // next tile coords
  logic [4:0]             ndrx;
  logic [7:0]             ndry;

  //
  // SPRITE FETCHING VARS
  // (Backshifted for autocomplete stuff)
  //

  // render/patternfetch information
  logic spr_latch_en;
  logic [3:0] fetch_ct;
  byte        oam_fetched [31:0];
  byte        sprite_data [31:0];
  logic [3:0] sprite_ct;

  // sprite 0 flag
  logic       alt_s0, s0;

  // translated coords
  logic [4:0] backshift;
  logic [2:0] yc, diff;

  //
  // END OF SPRITE FETCH VARS
  //

  // use always_comb to figure out memory stuff. use ff to latch data
  // Kinda FSM, but you don't actually need state - the pixel counter is in of itself
  // sufficient state.
  always_comb begin
    // address computation
    if (drx>>4 >= 31) begin
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
    nt_addr = {ndry[7:3], ndrx};
    attr_addr = 10'h3C0 + {ndry[7:5], ndrx[4:2]};

    nt_en = 0;
    altpat1_en = 0;
    altpat2_en = 0;
    alt_attr_en = 0;

    render_nmt_addr = '0;
    render_pattern_addr = '0;
    nt_data = '0;

    backshift = '0;
    yc = '0;
    diff = '0;

    // BG tile fetching - only happens during vision/trail of visible lines, and trail of pre-render line
    // TODO: Adapt to work w/ scrolling. Basically change the case statement & latching to work w scolling
    // need to change indexing statements slightly as well

    if (((drx>>1 < 256 || drx >= 768) && (dry>>1) < 240) || (drx >= 768 && dry==524)) begin
      unique case (drx[3:0])
        4'd0, 4'd1: begin
          nt_en = 1'b1;
          render_nmt_addr = nt_addr;

          // Good for hex viewing
          // render_nmt_addr = nt_addr>>1;
          // nt_data = fetch_out[{nt_addr[0], 2'd0} +: 4];

          if(control[1:0]==2'b0 || control[1]^mirror_cfg)
            nt_data = render_nmta_data;
          else
            nt_data = render_nmtb_data;
        end

        4'd2, 4'd3: begin
          alt_attr_en = 1'b1;
          render_nmt_addr = attr_addr;

          if(control[1:0]==2'b0 || control[1]^mirror_cfg)
            nt_data = render_nmta_data;
          else
            nt_data = render_nmtb_data;
        end

        4'd4, 4'd5: begin
          altpat1_en = 1'b1;
          render_pattern_addr = {control[4], nt, 1'b0, ndry[2:0]};
        end

        4'd6, 4'd7: begin
          altpat2_en = 1'b1;
          render_pattern_addr = {control[4], nt, 1'b1, ndry[2:0]};
        end

        // can't be too safe after the memory fiasco
        default: begin
          nt_en = 0;
          altpat1_en = 0;
          altpat2_en = 0;
          alt_attr_en = 0;

          render_nmt_addr = '0;
          render_pattern_addr = '0;
          nt_data = '0;
        end
      endcase
    end // if(drx>>1 <= 255)

    else if ((dry<480) && (drx>=522 && drx<=553)) begin
      backshift = drx-10'd522;
      diff = ndry - 1 - oam_fetched[{backshift[4:2], 2'd0}];
      yc = oam_fetched[{backshift[4:2], 2'd2}][7] ? 3'd7 - diff : diff;

      render_pattern_addr = {control[3], (oam_fetched[{backshift[4:2], 2'd1}]),
                             backshift[1], yc};
    end
  end

  // Background Rendering
  logic [0:7]             pat1, pat2;
  logic [7:0]             attr;

  // Registers
  logic [0:7]             altpat1, altpat2;
  logic [7:0]             nt, alt_attr;

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
      // BG tile fetching - only happens during vision/trail of visible lines, and trail of pre-render line
      if ((((drx>>1 < 256 || drx>=768) && (dry>>1) < 240) || (drx >= 768 && dry==524))
        && drx[3:0]=='1) begin

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
    end // else: !if(reset)

  end

  //
  // SPRITE FETCHING
  //

  // LINEAR SCAN

  always_ff @ (posedge vga_clk) begin
    if (reset) begin
      spr_latch_en <= 1'b0;

      fetch_ct <= '0;
      sprite_ct <= '0;

      for(int i=0; i<32; i++)
        oam_fetched[i] <= '0;

      for(int i=0; i<32; i++)
        oam_fetched[i] <= '0;

      s0 <= 1'b0;
      alt_s0 <= 1'b0;
    end else begin
      if(drx==0) begin
        for(int i=0; i<32; i++)
          oam_fetched[i] <= '0;

        fetch_ct <= 0;
        fetch_addr <= oam_addr;
        alt_s0 <= 0;
      end

      if (drx<=511 && dry<480)
        case (drx[2:0])
          3'd0:
            spr_latch_en <= 1'b0;

          3'd1: begin
            if(fetch_addr < 253)
              fetch_addr <= fetch_addr + 1'd1;

            if (fetch_out<=(dry>>1-~dry[0])
                && fetch_out+8'd7>=(dry>>1 - ~dry[0])
                && fetch_addr<253 && fetch_ct<8) begin
              fetch_ct <= fetch_ct + 1'd1;
              spr_latch_en <= 1;
              oam_fetched[{fetch_ct, 2'd0}] <= fetch_out;

              if (fetch_addr=='0)
                alt_s0 <= 1'b1;
            end
          end

          3'd3, 3'd5, 3'd7: begin
            if(fetch_addr < 255)
              fetch_addr <= fetch_addr + 1'd1;

            if (spr_latch_en)
              oam_fetched[{fetch_ct-1'd1, drx[2:1]}] <= fetch_out;
          end
        endcase // case (drx[2:0])

      else if (dry<480 && drx>=522 && drx<=553) begin
        if(drx==522) begin
          s0 <= alt_s0;
          sprite_ct <= fetch_ct;
        end

        case(backshift[1:0])
          2'd0: begin
            // direct copy of attribute & x position
            sprite_data[{backshift[4:2], 2'd0}] <= oam_fetched[{backshift[4:2], 2'd2}];
            sprite_data[{backshift[4:2], 2'd1}] <= oam_fetched[{backshift[4:2], 2'd3}];
          end

          2'd1, 2'd3: begin
            if(backshift[4:2] < sprite_ct)
              sprite_data[{backshift[4:2], 1'b0, backshift[1]}] <= render_pattern_data;
            else
              sprite_data[{backshift[4:2], 1'b0, backshift[1]}] <= '0;
          end
        endcase // case (backshift[1:0])
      end
    end
  end

  // color output
  wire [11:0] color;
  logic [7:0] my_color;

  logic [3:0] vga_r, vga_g, vga_b;

  always_comb begin
    my_color = '0;

    if (mask[0])
      color = vga[{pat2[drx[3:1]], pat1[drx[3:1]], 6'd0}];
    else begin
      my_color = palette[{2'b0, attr[{dry[5], drx[5], 1'b0} +: 2],
                          pat2[drx[3:1]], pat1[drx[3:1]]}];
      color = vga[my_color];
    end

    vga_r = '0;
    vga_g = '0;
    vga_b = '0;

    if(~blank || ((drx>>1) > 255) || ((dry>>1) > 239)) begin
      vga_r = '0;
      vga_g = '0;
      vga_b = '0;
    end

    else begin
      if (mask[3] && ((drx>>1)>8 || mask[1])) begin
        vga_r = color[11:8];
        vga_g = color[7:4];
        vga_b = color[3:0];
      end
    end
  end

  always_ff @ (vga_clk) begin
    VGA_R <= vga_r;
    VGA_B <= vga_b;
    VGA_G <= vga_g;
  end

endmodule
