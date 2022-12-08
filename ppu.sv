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
           output [15:0]      dma_addr,
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

  // TESTING
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
  logic [7:0]  render_oam_addr, render_oam_out;
  logic [7:0]  render_pattern_data, render_nmta_data, render_nmtb_data;

  // write-enable/data signals for RAM i/o interface
  logic        nmta_en, nmtb_en, oam_en;
  logic [7:0]  nmta_out, nmtb_out, oam_out, pattern_out;

  // DMA submodule
  logic [7:0]  dma_oam_addr;
  logic        dma_oam_en;

  dma DIRMA (.clk(cpu_clk), .bus_addr, .bus_data(bus_din), .bus_wr,
             .hijack(dma_hijack), .out_bus_addr(dma_addr), .oam_addr(dma_oam_addr),
             .oam_en(dma_oam_en));

  // ram declarations
  chr_rom pattern_mem (.address_a(vram_addr[12:0]), .clock_a(ram_clk),
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
               .address_b(render_oam_addr), .clock_b(vga_clk), .wren_b(1'b0), .q_b(render_oam_out));

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
      else if(dry==480)
        status[7] <= 1'b1;
      else if (dry == 10'd524)
        status[7] <= 1'b0;

      status[6] <= sprite_hit;

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
                  (vram_addr[11:10]==2'd1 && ~mirror_cfg) ||
                  (vram_addr[11:10]==2'd2 && mirror_cfg)) begin
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
                (vram_addr[11:10]==2'd1 && ~mirror_cfg) ||
                (vram_addr[11:10]==2'd2 && mirror_cfg))
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
  logic [1:0]             actual_nt;

  logic                   nt_en, altpat1_en, altpat2_en, alt_attr_en;
  logic [7:0]             nt_data;

  // next tile coords
  logic [4:0]             ndrx;
  logic [7:0]             ndry;

  logic [9:0]             transl_coord;
  logic                   ovr_x;

  //
  // Filling sprite_data
  //

  logic [4:0]             backshift; // makes it easier to make our "32 cycle" logic
  logic [2:0]             sprite_fetch_y;

  // Memory fetching during rendering
  always_comb begin
    // address computation for current tile
    if (drx>>4 >= 31) begin
      ovr_x = 1'b0;
      ndrx = scroll[15:11];

      if (dry >= 479)
        ndry = '0;
      else
        ndry = (dry + 10'd1)>>1;
    end else begin
      {ovr_x, ndrx} = transl_coord[9:4] + 5'd1;
      ndry = dry[8:1];
    end // else: !if(drx >= 496)

    // record in either nametable as offset from 0
    nt_addr = {ndry[7:3], ndrx};
    actual_nt = {control[1], control[0]^ovr_x};
    attr_addr = 10'h3C0 + {ndry[7:5], ndrx[4:2]};

    nt_en = 0;
    altpat1_en = 0;
    altpat2_en = 0;
    alt_attr_en = 0;

    render_nmt_addr = '0;
    render_pattern_addr = '0;
    nt_data = '0;

    transl_coord = drx[8:0] + scroll[15:8]*2;

    // defaults for sprite fetch vars
    sprite_fetch_y = '0;
    backshift = drx - 522;

    // BG tile fetching - only happens during vision/trail of visible lines, and trail of pre-render line
    // TODO: Adapt to work w/ scrolling. Basically change the case statement & latching to work w scolling
    // need to change indexing statements slightly as well

    if (((drx>>1 < 256 || drx >= 768) && (dry>>1) < 240) || (drx >= 768 && dry==524)) begin
      unique case (transl_coord[3:0])
        4'd0, 4'd1: begin
          nt_en = 1'b1;
          render_nmt_addr = nt_addr;

          // nt_data = sprite_data[ndrx];

          if(actual_nt==2'd0 || (actual_nt==2'd1 && ~mirror_cfg)
            || (actual_nt==2'd2 && mirror_cfg))
            nt_data = render_nmta_data;
          else
            nt_data = render_nmtb_data;
        end

        4'd2, 4'd3: begin
          alt_attr_en = 1'b1;
          render_nmt_addr = attr_addr;

          if(actual_nt==2'd0 || (actual_nt==2'd1 && ~mirror_cfg)
             || (actual_nt==2'd2 && mirror_cfg))
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

    else if (dry<480 && drx>=522 && drx<=553) begin
      sprite_fetch_y = fetched_data[{backshift[4:2], 2'd2}][7] ?
                       8'd7 - ((dry>>1) - fetched_data[{backshift[4:2], 2'd0}]) :
                       (dry>>1) - fetched_data[{backshift[4:2], 2'd0}];

      case(backshift[1:0])
        2'd0, 2'd1: render_pattern_addr = {control[3],
                                           fetched_data[{backshift[4:2], 2'd1}],
                                           1'b0, sprite_fetch_y};

        2'd2, 2'd3: render_pattern_addr = {control[3],
                                           fetched_data[{backshift[4:2], 2'd1}],
                                           1'b1, sprite_fetch_y};
      endcase // case (backshift[1:0])
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
          && transl_coord[3:0]=='1) begin

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

  // main storage
  byte sprite_data [31:0];
  logic [3:0] sprite_ct; // 0-8
  logic       s0;

  // scan storage
  byte        fetched_data [31:0];
  logic [1:0] batch_ct;
  logic [3:0] fetched_ct; // 0-8
  logic       alt_s0;

  // render_oam_addr/out higher up in file.
  // use oam_addr as a form of state - set it when transitioning TO read

  enum        logic [2:0]
              {IDL, MAINRD, EVAL, LATCH, INCR_RD}
              state, next;

  logic [7:0] rel_addr;

  assign rel_addr = dry>>1;

  always_comb begin
    case (state)
      IDL: next = (drx==0) ? MAINRD : IDL;

      MAINRD: next = (render_oam_addr < 253 && dry!=479) ? EVAL : IDL;

      EVAL: begin
        if (render_oam_out <= rel_addr && render_oam_out+3'd7>=rel_addr)
          next = LATCH;
        else
          next = (render_oam_addr < 249) ? MAINRD : IDL;
      end

      LATCH: begin
        if (batch_ct<3)
          next = INCR_RD;
        else
          next = (fetched_ct==4'd8 || render_oam_addr>252) ? IDL : MAINRD;
      end

      INCR_RD: next = LATCH;

      default: next = IDL;
    endcase // case (state)
  end

  // used in iterators
  integer i;
  logic [2:0] fetchidx;

  always_ff @ (posedge vga_clk) begin
    if (reset) begin
      batch_ct <= '0;
      fetched_ct <= '0;
      sprite_ct <= '0;

      s0 <= 1'b0;
      alt_s0 <= 1'b0;

      render_oam_addr <= '0;

      for(i=0; i<32; i++)
        sprite_data[i] <= '0;

      for(i=0; i<32; i++)
        fetched_data[i] <= '0;
    end

    else if (dry<480 && drx<512) begin
      state <= next;

      case (state)
        IDL: begin
          if (next==MAINRD) begin
            for(i=0; i<32; i++)
              fetched_data[i] <= '0;

            fetched_ct <= '0;
            batch_ct <= '0;
            render_oam_addr <= oam_addr;
            alt_s0 <= 1'b0;
          end
        end

        EVAL: begin
          if (next==LATCH) begin
            batch_ct <= '0;
            fetched_ct <= fetched_ct + 1'd1;
          end

          else if (next==MAINRD)
            render_oam_addr <= render_oam_addr + 4;
        end

        LATCH: begin
          render_oam_addr <= render_oam_addr + 1'd1;
          fetched_data[(fetched_ct-1'd1)*4 + batch_ct] <= render_oam_out;
          batch_ct <= batch_ct + 1'd1;

          if(render_oam_addr=='0)
            alt_s0 <= 1'b1;
        end
      endcase
    end

    else if (dry<480 && dry[0] && drx>=522 && drx<=553) begin
      if(drx==522) begin
        for(i=0; i<8; i++) begin
          sprite_data[i*4] <= fetched_data[i*4 + 2];
          sprite_data[i*4 + 1] <= fetched_data[i*4 + 3];
        end

        s0 <= alt_s0;
        sprite_ct <= fetched_ct;
      end

      case (backshift[1:0])
        2'd1: sprite_data[{backshift[4:2], 2'd2}] <= (backshift[4:2] < sprite_ct) ? render_pattern_data : '0;
        2'd3: sprite_data[{backshift[4:2], 2'd3}] <= (backshift[4:2] < sprite_ct) ? render_pattern_data : '0;
      endcase // case (backshift[1:0])
    end
  end

  // color output
  wire [11:0] bgcolor;
  logic [7:0] my_color;
  logic [1:0] bg_px;
  logic       bg_en;

  // sprite rendering logic
  logic [1:0] sprite_pattern;
  logic [7:0] palette_color;
  logic [2:0] diff;
  logic valid_sprite, spr_priority;
  integer     iter;

  // "hit condition" of sprite hit flag
  logic       hit0, sprite_hit, wasit0;

  // unsynchronized outputs
  logic [3:0] vga_r, vga_g, vga_b;

  always_comb begin
    // defaults
    my_color = '0;
    palette_color = '0;

    bg_px = {pat2[transl_coord[3:1]], pat1[transl_coord[3:1]]};
    bg_en = mask[3] && ((drx>>1)>8 || mask[1]) && (|bg_px);

    // generating pattern and validity for each sprite
    sprite_pattern = '0;
    valid_sprite = '0;
    diff = '0;
    wasit0 = 1'b0;
    spr_priority = 1'b1;
    iter = '0;

    // fetches priority sprite's pixel i guess
    if ((mask[4]) && (mask[2] || (drx>>1)>8)) begin
      for(iter=0; iter<8; iter++) begin
        if((iter<sprite_ct) &&
          (drx>>1) >= sprite_data[(iter*4)+1] &&
          (drx>>1) <= sprite_data[(iter*4)+1] + 7) begin

          diff = (drx>>1) - sprite_data[(iter*4)+1];

          if(sprite_data[iter*4][6])
            sprite_pattern = {sprite_data[(iter*4)+3][diff],
                            sprite_data[(iter*4)+2][diff]};
          else
            sprite_pattern = {sprite_data[(iter*4)+3][3'd7-diff],
                       sprite_data[(iter*4)+2][3'd7-diff]};

          valid_sprite = |(sprite_pattern);
          wasit0 = (iter==0) && valid_sprite;

          if(valid_sprite) begin
            if (mask[0])
              palette_color = {sprite_pattern, 6'd0};
            else
              palette_color = palette[{1'b1, sprite_data[iter*4][1:0], sprite_pattern}];
            spr_priority = sprite_data[iter*4][5];
            break;
          end
        end
      end
    end // if ((mask[4]) && (mask[2] || (drx>>1)>8))

    // "hardcode" hit condition
    hit0 = wasit0 && bg_en && valid_sprite;

    if (mask[0]) begin
      bgcolor = vga[{bg_px, 6'd0}];
    end

    else begin
      my_color = palette[{1'b0, attr[{dry[5], transl_coord[5], 1'b0} +: 2], bg_px}];
      bgcolor = vga[my_color];
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
      if(~valid_sprite && ~bg_en) begin
        vga_r = vga[palette[0]][11:8];
        vga_g = vga[palette[0]][7:4];
        vga_b = vga[palette[0]][3:0];
      end else if (bg_en && ~valid_sprite) begin
        vga_r = bgcolor[11:8];
        vga_g = bgcolor[7:4];
        vga_b = bgcolor[3:0];
      end else if (~bg_en && valid_sprite) begin
        vga_r = vga[palette_color][11:8];
        vga_g = vga[palette_color][7:4];
        vga_b = vga[palette_color][3:0];
      end else if (bg_en && valid_sprite) begin
        if(spr_priority) begin
          vga_r = bgcolor[11:8];
          vga_g = bgcolor[7:4];
          vga_b = bgcolor[3:0];
        end else begin
          vga_r = vga[palette_color][11:8];
          vga_g = vga[palette_color][7:4];
          vga_b = vga[palette_color][3:0];
        end
      end
    end
  end

  always_ff @ (vga_clk) begin
    VGA_R <= vga_r;
    VGA_B <= vga_b;
    VGA_G <= vga_g;


    if (reset || dry==524)
      sprite_hit <= 1'b0;
    else
      sprite_hit <= sprite_hit || (s0 && hit0);
  end

endmodule
