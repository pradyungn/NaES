module ppu_databus (
                    input              cpu_clk,

                    input [15:0]       ADDR,
                    input              WR,

                    input [7:0]        CPU_DO,
                                       CHRROM_Q,
                                       NMTA_Q,
                                       NMTB_Q,
                                       SPR_Q,
                                       STAT_Q,
                                       PALETTE,
                                       VRAM_PREFIX,

                    input              MIRROR,

                    output             NMTA_EN, NMTB_EN, SPR_EN, PALETTE_EN,
                    output             CTRL_EN, STAT_EN, MSK_EN, SCRLL_EN, OAM_ADDR_EN, VRAM_ADDR_EN,
                    output             DMA_TRIG, VRAM_ACTIVE,

                    output logic [7:0] out
                    );

  // NAME SCHEME
  // SPR - Sprite RAM (OAM)
  // NMTA - Nametable A
  // NMTB - Nametable B
  // STAT - Status Register
  // PALETTE - pre-indexed palette ram
  // MIRROR - locally configured bit to indicate mirroring config
  // 0 is for horizontal, 1 is for vertical
  // VRAM prefix is first 8 bits.

  // Assigning bus_out properly
  logic [7:0]                    VRAM_BUS, BUS_OUT;
  logic                          WRITE_VRAM;

  always_ff @ (posedge cpu_clk)
    out <= BUS_OUT;

  always_comb begin
    SPR_EN = 0;
    STAT_EN = 0;
    MSK_EN = 0;
    SCRLL_EN = 0;
    OAM_ADDR_EN = 0;
    VRAM_ADDR_EN = 0;
    DMA_TRIG = 0;
    CTRL_EN = 0;
    WRITE_VRAM = 0;
    VRAM_ACTIVE = 0;

    BUS_OUT = '0;

  if (ADDR>=16'h2000 && ADDR<=16'h3FFF) begin
      if (ADDR[2:0]==3'd0) begin
        // write-only - do not modify bus
        CTRL_EN = ~WR;
      end else if (ADDR[2:0]==3'd1) begin
        // write-only
        MSK_EN = ~WR;
      end else if (ADDR[2:0]==3'd2) begin
        // this is a read op, but we need to clear the address latches
        BUS_OUT = STAT_Q;
        STAT_EN = WR;
      end

      // oamaddr
      else if (ADDR[2:0]==3'd3)
        OAM_ADDR_EN = 1'b1;


      // OAM interaction
      else if (ADDR[2:0]==3'd4) begin
        SPR_EN = ~WR;
        BUS_OUT = SPR_Q;
      end

      // PPU Scroll
      else if (ADDR[2:0]==3'd5)
        SCRLL_EN = 1'b1;

      // VRAM Address
      else if (ADDR[2:0]==3'd6)
        VRAM_ADDR_EN = 1'b1;

      // VRAM interaction
      else if (ADDR[2:0]==3'd7) begin
        WRITE_VRAM = ~WR;
        BUS_OUT = VRAM_BUS;
        VRAM_ACTIVE = 1'b1;
      end
    end

    // DMA trigger
    else if (ADDR==16'h4014)
      DMA_TRIG = 1'b1;
  end

  // VRAM bus
  always_comb begin
    NMTA_EN = 1'b0;
    NMTB_EN = 1'b0;
    VRAM_BUS = '0;
    PALETTE_EN = '0;

    if (VRAM_PREFIX<=8'h1F)
      VRAM_BUS = CHRROM_Q;

    else if (VRAM_PREFIX<=8'h3E) begin
      if(VRAM_PREFIX[3:0]<=3) begin
        NMTA_EN = WRITE_VRAM;
        VRAM_BUS = NMTA_Q;
      end

      else if (VRAM_PREFIX[3:0]<=7) begin
        if (MIRROR) begin
          NMTB_EN = WRITE_VRAM;
          VRAM_BUS = NMTB_Q;
        end else begin
          NMTA_EN = WRITE_VRAM;
          VRAM_BUS = NMTA_Q;
        end
      end

      else if (VRAM_PREFIX[3:0]<=4'hb) begin
        if (MIRROR) begin
          NMTA_EN = WRITE_VRAM;
          VRAM_BUS = NMTA_Q;
        end else begin
          NMTB_EN = WRITE_VRAM;
          VRAM_BUS = NMTB_Q;
        end
      end

      else begin
        NMTB_EN = WRITE_VRAM;
        VRAM_BUS = NMTB_Q;
      end // else: !if(VRAM_PREFIX[3:0]<=4'hb)
    end // if (VRAM_PREFIX<=8'h3E)

    else if (VRAM_PREFIX<=16'h3F) begin
      VRAM_BUS = PALETTE;
      PALETTE_EN = WRITE_VRAM;
    end
  end
endmodule
