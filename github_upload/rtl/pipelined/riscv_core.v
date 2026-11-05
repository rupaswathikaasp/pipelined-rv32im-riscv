//-----------------------------------------------------------------
//        uRISC-V CPU  -  5-STAGE PIPELINED VERSION (RV32IM + Zicsr)
//-----------------------------------------------------------------
// Derived from the multi-cycle uriscv core (ultraembedded/core_uriscv).
// Same ports / parameters, so the original testbench runs unchanged.
// Re-uses the original uriscv_alu, uriscv_branch, uriscv_lsu,
// uriscv_csr and uriscv_muldiv modules without modification.
//
//   IF  : PC -> instruction memory (synchronous, 1-cycle latency;
//         the memory's output register acts as the IF/ID register)
//   ID  : decode, register-file read (with write-back bypass),
//         load-use hazard detection
//   EX  : ALU, forwarding, branch/jump resolve, CSR, mul/div (stalls),
//         data-memory request issued here (address/data from EX)
//   MEM : load data returns from data memory, aligned / sign-extended
//   WB  : register-file write
//
// Hazards : full forwarding (MEM->EX, WB->EX, WB->ID bypass)
//           1-cycle stall on load-use
//           1-cycle bubble on taken branch / jump / trap (resolved in EX)
//           pipeline stall while the multi-cycle MUL/DIV unit works
//
// Assumption (true for the supplied testbench memory):
//   instruction and data memories accept every request and return
//   data exactly one cycle later.
//-----------------------------------------------------------------
module riscv_core
//-----------------------------------------------------------------
// Params
//-----------------------------------------------------------------
#(
     parameter SUPPORT_MUL      = 1
    ,parameter SUPPORT_DIV      = 1
    ,parameter SUPPORT_CSR      = 1
    ,parameter SUPPORT_TRAP_LSU_ALIGN = 1
    ,parameter SUPPORT_MTVEC    = 0
    ,parameter SUPPORT_MTVAL    = 0
    ,parameter SUPPORT_MIP_MIE  = 0
    ,parameter SUPPORT_MSCRATCH = 0
    ,parameter SUPPORT_MCYCLE   = 1
    ,parameter SUPPORT_MTIMECMP = 0
    ,parameter SUPPORT_TRAP_INVALID_OPC = 1
    ,parameter SUPPORT_BRAM_REGFILE = 0     // unused in pipelined core
    ,parameter ISR_VECTOR       = 32'h00000010
)
//-----------------------------------------------------------------
// Ports
//-----------------------------------------------------------------
(
    // Clock
     input           clk_i

    // Reset (active high)
    ,input           rst_i

    // External interrupt (M_EXT)
    ,input           intr_i

    // Initial boot address
    ,input  [ 31:0]  reset_vector_i

    // MHARTID value
    ,input  [ 31:0]  cpu_id_i

    // Instruction Fetch
    ,output          mem_i_rd_o
    ,output [ 31:0]  mem_i_pc_o
    ,input           mem_i_accept_i
    ,input           mem_i_valid_i
    ,input  [ 31:0]  mem_i_inst_i

    // Instruction fetch: Unused on this core
    ,output          mem_i_flush_o
    ,output          mem_i_invalidate_o

    // Instruction fetch: Unused (tie low)
    ,input           mem_i_error_i

    // Data Access
    ,output [ 31:0]  mem_d_addr_o
    ,output [ 31:0]  mem_d_data_wr_o
    ,output          mem_d_rd_o
    ,output [  3:0]  mem_d_wr_o
    ,input  [ 31:0]  mem_d_data_rd_i
    ,input           mem_d_accept_i
    ,input           mem_d_ack_i

    // Unused on this core
    ,output          mem_d_cacheable_o
    ,output [ 10:0]  mem_d_req_tag_o
    ,output          mem_d_invalidate_o
    ,output          mem_d_writeback_o
    ,output          mem_d_flush_o

    // Data Access: Unused (tie low)
    ,input           mem_d_error_i
    ,input  [ 10:0]  mem_d_resp_tag_i
);

`include "uriscv_defs.v"

//-----------------------------------------------------------------
// Forward declarations (control wires used before their driver)
//-----------------------------------------------------------------
wire        redirect_w;          // EX stage redirects the PC
wire [31:0] redirect_pc_w;
wire        ex_stall_w;          // EX busy (mul/div)  -> hold IF, ID, EX
wire        load_use_w;          // load-use hazard    -> hold IF, ID, bubble EX

// Write-back stage registers (declared here: used by ID bypass / EX forward)
reg         w_wen_q;
reg  [4:0]  w_rd_q;
reg  [31:0] w_data_q;

// MEM stage registers
reg         m_wen_q;
reg  [4:0]  m_rd_q;
reg  [31:0] m_result_q;
reg         m_load_q;
reg         m_lsigned_q;
reg         m_lbyte_q;
reg         m_lhalf_q;
reg  [1:0]  m_loff_q;

//=================================================================
// STAGE 1 : INSTRUCTION FETCH
//=================================================================
reg  [31:0] pc_f_q;      // next sequential fetch address
reg  [31:0] id_pc_q;     // PC of the instruction now appearing on mem_i_inst_i

wire        hold_id_w   = ex_stall_w | load_use_w;

// Address presented to the instruction memory this cycle
wire [31:0] fetch_addr_w = redirect_w ? redirect_pc_w :
                           hold_id_w  ? id_pc_q       : pc_f_q;

// Fetching starts one cycle after reset is released (as in the original
// core's RESET state), so memory contents are valid before the first fetch.
reg started_q;
always @ (posedge clk_i)
if (rst_i)
    started_q <= 1'b0;
else
    started_q <= 1'b1;

assign mem_i_rd_o = started_q;
assign mem_i_pc_o = fetch_addr_w;

wire        fetch_acc_w = mem_i_rd_o & mem_i_accept_i;

always @ (posedge clk_i)
if (rst_i)
begin
    pc_f_q  <= reset_vector_i;
    id_pc_q <= reset_vector_i;
end
else
begin
    id_pc_q <= fetch_addr_w;
    pc_f_q  <= fetch_acc_w ? (fetch_addr_w + 32'd4) : fetch_addr_w;
end

//=================================================================
// STAGE 2 : DECODE / REGISTER READ
//=================================================================
wire [31:0] id_inst_w  = mem_i_inst_i;
wire        id_valid_w = mem_i_valid_i;

wire [4:0]  id_rs1_w   = id_inst_w[19:15];
wire [4:0]  id_rs2_w   = id_inst_w[24:20];
wire [4:0]  id_op_w    = id_inst_w[6:2];

// Which source registers does this instruction really read? (loose = safe)
wire id_uses_rs1_w = !(id_op_w == 5'b01101 ||   // LUI
                       id_op_w == 5'b00101 ||   // AUIPC
                       id_op_w == 5'b11011);    // JAL
wire id_uses_rs2_w =  (id_op_w == 5'b01100 ||   // OP
                       id_op_w == 5'b11000 ||   // BRANCH
                       id_op_w == 5'b01000);    // STORE

// Register file (no reset: x0 is forced to zero on read)
reg [31:0] reg_file[0:31];

always @ (posedge clk_i)
if (w_wen_q)
    reg_file[w_rd_q] <= w_data_q;

// Read with write-back bypass (WB writes at end of this cycle)
wire [31:0] id_rs1_val_w = (id_rs1_w == 5'b0)                    ? 32'b0 :
                           (w_wen_q && (w_rd_q == id_rs1_w))     ? w_data_q :
                                                                   reg_file[id_rs1_w];
wire [31:0] id_rs2_val_w = (id_rs2_w == 5'b0)                    ? 32'b0 :
                           (w_wen_q && (w_rd_q == id_rs2_w))     ? w_data_q :
                                                                   reg_file[id_rs2_w];

//=================================================================
// ID / EX PIPELINE REGISTER
//=================================================================
reg         ex_valid_q;
reg  [31:0] ex_pc_q;
reg  [31:0] ex_opcode_q;
reg  [31:0] ex_rs1v_q;
reg  [31:0] ex_rs2v_q;

always @ (posedge clk_i)
if (rst_i)
begin
    ex_valid_q  <= 1'b0;
    ex_pc_q     <= 32'b0;
    ex_opcode_q <= 32'b0;
    ex_rs1v_q   <= 32'b0;
    ex_rs2v_q   <= 32'b0;
end
else if (ex_stall_w)
    ;                                   // hold
else if (redirect_w || load_use_w)
    ex_valid_q  <= 1'b0;                // bubble
else
begin
    ex_valid_q  <= id_valid_w;
    ex_pc_q     <= id_pc_q;
    ex_opcode_q <= id_inst_w;
    ex_rs1v_q   <= id_rs1_val_w;
    ex_rs2v_q   <= id_rs2_val_w;
end

//=================================================================
// STAGE 3 : EXECUTE
//=================================================================
wire [31:0] opcode_w = ex_opcode_q;
wire [4:0]  ex_rs1_w = opcode_w[19:15];
wire [4:0]  ex_rs2_w = opcode_w[24:20];
wire [4:0]  ex_rd_w  = opcode_w[11:7];

// ------------------- forwarding ----------------------------------
wire fwd_a_mem_w = m_wen_q && !m_load_q && (m_rd_q == ex_rs1_w);
wire fwd_a_wb_w  = w_wen_q &&              (w_rd_q == ex_rs1_w);
wire fwd_b_mem_w = m_wen_q && !m_load_q && (m_rd_q == ex_rs2_w);
wire fwd_b_wb_w  = w_wen_q &&              (w_rd_q == ex_rs2_w);

wire [31:0] rs1_val_w = fwd_a_mem_w ? m_result_q :
                        fwd_a_wb_w  ? w_data_q   : ex_rs1v_q;
wire [31:0] rs2_val_w = fwd_b_mem_w ? m_result_q :
                        fwd_b_wb_w  ? w_data_q   : ex_rs2v_q;

// ------------------- decode (same as original core) -------------
wire type_rvc_w     = (opcode_w[1:0] != 2'b11);

wire type_load_w    = (opcode_w[6:2] == 5'b00000);
wire type_opimm_w   = (opcode_w[6:2] == 5'b00100);
wire type_auipc_w   = (opcode_w[6:2] == 5'b00101);
wire type_store_w   = (opcode_w[6:2] == 5'b01000);
wire type_op_w      = (opcode_w[6:2] == 5'b01100);
wire type_lui_w     = (opcode_w[6:2] == 5'b01101);
wire type_branch_w  = (opcode_w[6:2] == 5'b11000);
wire type_jalr_w    = (opcode_w[6:2] == 5'b11001);
wire type_jal_w     = (opcode_w[6:2] == 5'b11011);
wire type_system_w  = (opcode_w[6:2] == 5'b11100);
wire type_miscm_w   = (opcode_w[6:2] == 5'b00011);

wire [2:0] func3_w  = opcode_w[14:12];
wire [6:0] func7_w  = opcode_w[31:25];

wire type_alu_op_w  = (type_op_w && (func7_w == 7'b0000000)) ||
                      (type_op_w && (func7_w == 7'b0100000));

wire inst_lb_w       = type_load_w && (func3_w == 3'b000);
wire inst_lh_w       = type_load_w && (func3_w == 3'b001);
wire inst_lbu_w      = type_load_w && (func3_w == 3'b100);
wire inst_lhu_w      = type_load_w && (func3_w == 3'b101);

wire inst_ecall_w    = SUPPORT_CSR && type_system_w && (opcode_w[31:7] == 25'h000000);
wire inst_ebreak_w   = SUPPORT_CSR && type_system_w && (opcode_w[31:7] == 25'h002000);
wire inst_mret_w     = SUPPORT_CSR && type_system_w && (opcode_w[31:7] == 25'h604000);
wire inst_csr_w      = SUPPORT_CSR && type_system_w && (func3_w != 3'b000 && func3_w != 3'b100);

wire mul_inst_w      = SUPPORT_MUL && type_op_w && (func7_w == 7'b0000001) && ~func3_w[2];
wire div_inst_w      = SUPPORT_DIV && type_op_w && (func7_w == 7'b0000001) &&  func3_w[2];
wire inst_mul_w      = mul_inst_w && (func3_w == 3'b000);
wire inst_mulh_w     = mul_inst_w && (func3_w == 3'b001);
wire inst_mulhsu_w   = mul_inst_w && (func3_w == 3'b010);
wire inst_mulhu_w    = mul_inst_w && (func3_w == 3'b011);
wire inst_div_w      = div_inst_w && (func3_w == 3'b100);
wire inst_divu_w     = div_inst_w && (func3_w == 3'b101);
wire inst_rem_w      = div_inst_w && (func3_w == 3'b110);
wire inst_remu_w     = div_inst_w && (func3_w == 3'b111);
wire inst_nop_w      = (type_miscm_w && (func3_w == 3'b000)) |
                       (type_miscm_w && (func3_w == 3'b001));

wire muldiv_inst_w   = mul_inst_w | div_inst_w;

wire [31:0] imm20_w  = {opcode_w[31:12], 12'b0};
wire [31:0] imm12_w  = {{20{opcode_w[31]}}, opcode_w[31:20]};

// ------------------- ALU operand select --------------------------
wire [31:0] csr_data_w;

reg [3:0]  alu_func_r;
reg [31:0] alu_input_a_r;
reg [31:0] alu_input_b_r;
reg        write_rd_r;

always @ *
begin
    alu_func_r     = `RV_ALU_NONE;
    alu_input_a_r  = rs1_val_w;
    alu_input_b_r  = rs2_val_w;
    write_rd_r     = 1'b0;

    case (1'b1)
    type_alu_op_w:
    begin
        alu_input_a_r  = rs1_val_w;
        alu_input_b_r  = rs2_val_w;
    end
    type_opimm_w:
    begin
        alu_input_a_r  = rs1_val_w;
        alu_input_b_r  = imm12_w;
    end
    type_lui_w:
    begin
        alu_input_a_r  = 32'b0;
        alu_input_b_r  = imm20_w;
    end
    type_auipc_w:
    begin
        alu_input_a_r  = ex_pc_q;
        alu_input_b_r  = imm20_w;
    end
    type_jal_w,
    type_jalr_w:
    begin
        alu_input_a_r  = ex_pc_q;
        alu_input_b_r  = 32'd4;
    end
    default : ;
    endcase

    if (muldiv_inst_w)
        write_rd_r     = 1'b1;
    else if (type_opimm_w || type_alu_op_w)
    begin
        case (func3_w)
        3'b000:  alu_func_r =  (type_op_w & opcode_w[30]) ?
                              `RV_ALU_SUB : `RV_ALU_ADD;
        3'b001:  alu_func_r = `RV_ALU_SHIFTL;
        3'b010:  alu_func_r = `RV_ALU_LESS_THAN_SIGNED;
        3'b011:  alu_func_r = `RV_ALU_LESS_THAN;
        3'b100:  alu_func_r = `RV_ALU_XOR;
        3'b101:  alu_func_r = opcode_w[30] ? `RV_ALU_SHIFTR_ARITH : `RV_ALU_SHIFTR;
        3'b110:  alu_func_r = `RV_ALU_OR;
        3'b111:  alu_func_r = `RV_ALU_AND;
        endcase

        write_rd_r = 1'b1;
    end
    else if (inst_csr_w)
    begin
        alu_func_r     = `RV_ALU_ADD;
        alu_input_a_r  = 32'b0;
        alu_input_b_r  = csr_data_w;
        write_rd_r     = 1'b1;
    end
    else if (type_auipc_w || type_lui_w || type_jalr_w || type_jal_w)
    begin
        write_rd_r     = 1'b1;
        alu_func_r     = `RV_ALU_ADD;
    end
    else if (type_load_w)
        write_rd_r     = 1'b1;
end

wire [31:0] alu_result_w;

uriscv_alu u_alu
(
     .op_i(alu_func_r)
    ,.a_i(alu_input_a_r)
    ,.b_i(alu_input_b_r)
    ,.p_o(alu_result_w)
);

// ------------------- branch / jump -------------------------------
wire        branch_w;
wire [31:0] branch_target_w;

uriscv_branch u_branch
(
     .pc_i(ex_pc_q)
    ,.opcode_i(opcode_w)
    ,.rs1_val_i(rs1_val_w)
    ,.rs2_val_i(rs2_val_w)
    ,.branch_o(branch_w)
    ,.branch_target_o(branch_target_w)
);

// ------------------- invalid instruction -------------------------
reg invalid_inst_r;
always @ *
begin
    invalid_inst_r = SUPPORT_TRAP_INVALID_OPC;

    if (   type_load_w
         | type_opimm_w
         | type_auipc_w
         | type_store_w
         | type_alu_op_w
         | type_lui_w
         | type_branch_w
         | type_jalr_w
         | type_jal_w
         | inst_ecall_w
         | inst_ebreak_w
         | inst_mret_w
         | inst_csr_w
         | inst_nop_w
         | muldiv_inst_w)
        invalid_inst_r = SUPPORT_TRAP_INVALID_OPC && type_rvc_w;
end

// ------------------- load / store unit ---------------------------
wire         mem_rd_w;
wire [3:0]   mem_wr_w;
wire [31:0]  mem_addr_w;
wire [31:0]  mem_data_w;
wire         mem_misaligned_w;

uriscv_lsu
#( .SUPPORT_TRAP_LSU_ALIGN(SUPPORT_TRAP_LSU_ALIGN) )
u_lsu
(
     .opcode_i(opcode_w)
    ,.rs1_val_i(rs1_val_w)
    ,.rs2_val_i(rs2_val_w)

    ,.mem_rd_o(mem_rd_w)
    ,.mem_wr_o(mem_wr_w)
    ,.mem_addr_o(mem_addr_w)
    ,.mem_data_o(mem_data_w)
    ,.mem_misaligned_o(mem_misaligned_w)
);

// ------------------- CSR / exceptions ----------------------------
wire        exception_w;
wire [5:0]  exception_type_w;
wire [31:0] exception_target_w;
wire [31:0] csr_mepc_w;

// CSR unit sees each instruction exactly once (when it leaves EX)
wire        csr_valid_w = ex_valid_q & ~ex_stall_w;

uriscv_csr
#(
     .SUPPORT_CSR(SUPPORT_CSR)
    ,.SUPPORT_MCYCLE(SUPPORT_MCYCLE)
    ,.SUPPORT_MTIMECMP(SUPPORT_MTIMECMP)
    ,.SUPPORT_MSCRATCH(SUPPORT_MSCRATCH)
    ,.SUPPORT_MIP_MIE(SUPPORT_MIP_MIE)
    ,.SUPPORT_MTVEC(SUPPORT_MTVEC)
    ,.SUPPORT_MTVAL(SUPPORT_MTVAL)
    ,.SUPPORT_MULDIV(SUPPORT_MUL || SUPPORT_DIV)
)
u_csr
(
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.isr_vector_i(reset_vector_i + ISR_VECTOR)
    ,.cpu_id_i(cpu_id_i)
    ,.intr_i(intr_i)

    ,.valid_i(csr_valid_w)
    ,.opcode_i(opcode_w)
    ,.pc_i(ex_pc_q)
    ,.rs1_val_i(rs1_val_w)
    ,.rs2_val_i(rs2_val_w)

    ,.csr_rdata_o(csr_data_w)

    ,.excpn_invalid_inst_i(invalid_inst_r)
    ,.excpn_lsu_align_i(mem_misaligned_w)
    ,.mem_addr_i(mem_addr_w)

    ,.csr_mepc_o(csr_mepc_w)

    ,.exception_o(exception_w)
    ,.exception_type_o(exception_type_w)
    ,.exception_pc_o(exception_target_w)
);

// ------------------- multiplier / divider ------------------------
wire [31:0] muldiv_result_w;
wire        muldiv_ready_w;
reg         md_issued_q;

// one-cycle start pulse, then wait for ready
wire        md_valid_w = ex_valid_q & muldiv_inst_w & ~md_issued_q;

always @ (posedge clk_i)
if (rst_i)
    md_issued_q <= 1'b0;
else if (muldiv_ready_w)
    md_issued_q <= 1'b0;
else if (md_valid_w)
    md_issued_q <= 1'b1;

generate
if (SUPPORT_MUL != 0 || SUPPORT_DIV != 0)
begin
    uriscv_muldiv u_muldiv
    (
         .clk_i(clk_i)
        ,.rst_i(rst_i)

        ,.valid_i(md_valid_w)
        ,.inst_mul_i(inst_mul_w)
        ,.inst_mulh_i(inst_mulh_w)
        ,.inst_mulhsu_i(inst_mulhsu_w)
        ,.inst_mulhu_i(inst_mulhu_w)
        ,.inst_div_i(inst_div_w)
        ,.inst_divu_i(inst_divu_w)
        ,.inst_rem_i(inst_rem_w)
        ,.inst_remu_i(inst_remu_w)

        ,.operand_ra_i(rs1_val_w)
        ,.operand_rb_i(rs2_val_w)

        ,.stall_o()
        ,.ready_o(muldiv_ready_w)
        ,.result_o(muldiv_result_w)
    );
end
else
begin
    assign muldiv_ready_w  = 1'b0;
    assign muldiv_result_w = 32'b0;
end
endgenerate

// ------------------- EX control ----------------------------------
assign ex_stall_w = ex_valid_q & muldiv_inst_w & ~muldiv_ready_w;

wire ex_commit_w  = ex_valid_q & ~ex_stall_w & ~exception_w;

wire ex_trap_w    = exception_w | inst_ebreak_w | inst_ecall_w;

assign redirect_w    = ex_valid_q & ~ex_stall_w &
                       (ex_trap_w | inst_mret_w | branch_w);
assign redirect_pc_w = ex_trap_w   ? exception_target_w :
                       inst_mret_w ? csr_mepc_w         : branch_target_w;

// Load-use hazard: instruction in ID needs the result of a load now in EX
assign load_use_w = id_valid_w & ex_valid_q & type_load_w & (ex_rd_w != 5'b0) &
                    ((id_uses_rs1_w && (ex_rd_w == id_rs1_w)) ||
                     (id_uses_rs2_w && (ex_rd_w == id_rs2_w)));

wire [31:0] ex_result_w = muldiv_inst_w ? muldiv_result_w : alu_result_w;

// ------------------- data memory request (issued from EX) --------
assign mem_d_addr_o    = {mem_addr_w[31:2], 2'b0};
assign mem_d_data_wr_o = mem_data_w;
assign mem_d_wr_o      = ex_commit_w ? mem_wr_w : 4'b0000;
assign mem_d_rd_o      = ex_commit_w & mem_rd_w;

//=================================================================
// EX / MEM PIPELINE REGISTER
//=================================================================
always @ (posedge clk_i)
if (rst_i)
begin
    m_wen_q     <= 1'b0;
    m_rd_q      <= 5'b0;
    m_result_q  <= 32'b0;
    m_load_q    <= 1'b0;
    m_lsigned_q <= 1'b0;
    m_lbyte_q   <= 1'b0;
    m_lhalf_q   <= 1'b0;
    m_loff_q    <= 2'b0;
end
else if (ex_stall_w)
begin
    // bubble while mul/div is busy
    m_wen_q     <= 1'b0;
    m_load_q    <= 1'b0;
end
else
begin
    m_wen_q     <= ex_commit_w & write_rd_r & (ex_rd_w != 5'b0);
    m_rd_q      <= ex_rd_w;
    m_result_q  <= ex_result_w;
    m_load_q    <= ex_commit_w & type_load_w;
    m_lsigned_q <= inst_lh_w | inst_lb_w;
    m_lbyte_q   <= inst_lb_w | inst_lbu_w;
    m_lhalf_q   <= inst_lh_w | inst_lhu_w;
    m_loff_q    <= mem_addr_w[1:0];
end

//=================================================================
// STAGE 4 : MEMORY  (load data returns, aligned / extended)
//=================================================================
reg [31:0] load_result_r;
always @ *
begin
    load_result_r = 32'b0;

    if (m_lbyte_q)
    begin
        case (m_loff_q[1:0])
            2'h3: load_result_r = {24'b0, mem_d_data_rd_i[31:24]};
            2'h2: load_result_r = {24'b0, mem_d_data_rd_i[23:16]};
            2'h1: load_result_r = {24'b0, mem_d_data_rd_i[15:8]};
            2'h0: load_result_r = {24'b0, mem_d_data_rd_i[7:0]};
        endcase

        if (m_lsigned_q && load_result_r[7])
            load_result_r = {24'hFFFFFF, load_result_r[7:0]};
    end
    else if (m_lhalf_q)
    begin
        if (m_loff_q[1])
            load_result_r = {16'b0, mem_d_data_rd_i[31:16]};
        else
            load_result_r = {16'b0, mem_d_data_rd_i[15:0]};

        if (m_lsigned_q && load_result_r[15])
            load_result_r = {16'hFFFF, load_result_r[15:0]};
    end
    else
        load_result_r = mem_d_data_rd_i;
end

//=================================================================
// MEM / WB PIPELINE REGISTER  ->  STAGE 5 : WRITE BACK
//=================================================================
always @ (posedge clk_i)
if (rst_i)
begin
    w_wen_q  <= 1'b0;
    w_rd_q   <= 5'b0;
    w_data_q <= 32'b0;
end
else
begin
    w_wen_q  <= m_wen_q;
    w_rd_q   <= m_rd_q;
    w_data_q <= m_load_q ? load_result_r : m_result_q;
end

//-----------------------------------------------------------------
// Unused
//-----------------------------------------------------------------
assign mem_i_flush_o      = 1'b0;
assign mem_i_invalidate_o = 1'b0;

assign mem_d_flush_o      = 1'b0;
assign mem_d_cacheable_o  = 1'b0;
assign mem_d_req_tag_o    = 11'b0;
assign mem_d_invalidate_o = 1'b0;
assign mem_d_writeback_o  = 1'b0;

endmodule
