/*
 * CP15 control block.
 * (C) 2016 Revanth Kamaraj
 * Released under the MIT License.
 * Verilog-2001
 */

`default_nettype none

module zap_cp15_cb #(
        parameter PHY_REGS = 64
)
(
        // Clock and reset.
        input wire                              i_clk,
        input wire                              i_reset,

        // Coprocessor bus.
        input wire      [31:0]                  i_cp_word,
        input wire                              i_cp_dav,
        output reg                              o_cp_done,
        input  wire     [31:0]                  i_cpsr,
        output reg                              o_reg_en,
        output reg [31:0]                       o_reg_wr_data,
        input wire [31:0]                       i_reg_rd_data,
        output reg [$clog2(PHY_REGS)-1:0]       o_reg_wr_index,
                                                o_reg_rd_index,

        // These come from the memory control unit.
        input wire      [31:0]                  i_fsr,
        input wire      [31:0]                  i_far,

        // These go to the memory control unit.
        output reg      [31:0]                  o_dac,
        output reg      [31:0]                  o_baddr,
        output reg                              o_cache_inv,
        output reg                              o_tlb_inv,
        output reg                              o_cache_en,
        output reg                              o_mmu_en,
        output reg      [1:0]                   o_sr
);

`include "global_functions.vh"
`include "cpsr.vh"
`include "regs.vh"
`include "cc.vh"
`include "modes.vh"

reg [31:0] r [6:0]; // Coprocessor registers. R7 is write-only.
reg [2:0]    state; // State variable.
reg [31:0] fsr_dly;

always @*
begin
        o_cache_en = r[1][2];
        o_mmu_en   = r[1][0];
        o_dac      = r[3];
        o_baddr    = r[2];
        o_sr       = {r[1][8],r[1][9]};
end

// States.
localparam IDLE         = 0;
localparam ACTIVE       = 1;
localparam DONE         = 2;
localparam READ         = 3;
localparam READ_DLY     = 4;

always @ (posedge i_clk)
begin
        if ( i_reset )
                fsr_dly <= 0;
        else
                fsr_dly <= i_fsr;
end

always @ (posedge i_clk)
if ( i_reset )
begin
        state       <= IDLE;
        r[0]        <= 32'hFFFFFFFF;
        o_cache_inv <= 1'd0;
        o_tlb_inv   <= 1'd0;
        o_reg_en    <= 1'd0;
        o_cp_done      <= 1'd0;
        o_reg_wr_data  <= 0;
        o_reg_wr_index <= 0;
        o_reg_rd_index <= 0;
        r[1]        <= 32'd0;
        r[2]        <= 32'd0;
        r[3]        <= 32'd0;
        r[4]        <= 32'd0;
        r[5]        <= 32'd0;
        r[6]        <= 32'd0;
end
else
begin
        r[0]        <= 32'hFFFFFFFF;
        o_tlb_inv   <= 1'd0;
        o_cache_inv <= 1'd0;
        o_reg_en    <= 1'd0;

        case ( state )
        IDLE:
        begin
                o_cp_done <= 1'd0;

                // Keep monitoring FSR and FAR from MMU unit.
                if ( (fsr_dly != i_fsr) && i_fsr[3:0] != 4'd0 )
                begin
                        r[5] <= i_fsr;
                        r[6] <= i_far;
                end

                if ( i_cp_dav && i_cp_word[11:8] == 15 )
                begin
                        if ( i_cpsr[4:0] != USR )
                        begin
                                state     <= ACTIVE;
                                o_cp_done <= 1'd0;
                        end
                        else
                        begin
                                // No permissions in USR land. Pretend to be done.
                                o_cp_done <= 1'd1;
                        end
                end
        end

        DONE:
        begin
                o_cp_done    <= 1'd1;
                state        <= IDLE;
        end

        READ_DLY:
        begin
                state <= READ;
        end

        READ:
        begin
                r [ i_cp_word[19:16] ] <= i_reg_rd_data;

                if ( i_cp_word[19:16] == 4'd5 || i_cp_word[19:16] == 4'd6 )
                begin
                        o_tlb_inv <= 1'd1;
                end
                else if ( i_cp_word[19:16] == 4'd7 )
                begin
                        o_cache_inv <= 1'd1;
                end

                state <= DONE;
        end

        ACTIVE:
        begin
                if ( is_cc_satisfied ( i_cp_word[31:28], i_cpsr[31:28] ) )
                begin
                                if ( i_cp_word[20] ) // It is a load to register.
                                begin
                                        // Generate register write command.                                                                                  
                                        o_reg_en        <= 1'd1;
                                        o_reg_wr_index  <= translate( i_cp_word[15:12], i_cpsr[4:0] ); 
                                        o_reg_wr_data   <= r[ i_cp_word[19:16] ];
                                        state           <= DONE;
                                end
                                else /* Store to CP register */
                                begin
                                        // Generate register read command.
                                        o_reg_en        <= 1'd1;
                                        o_reg_rd_index  <=  translate(i_cp_word[15:12], i_cpsr[4:0]);
                                        state           <= READ_DLY;                                        
                                end
                end
                else
                begin
                        o_cp_done    <= 1'd1;
                        state        <= IDLE;
                end
        end
        endcase
end

endmodule