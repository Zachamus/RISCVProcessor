// ucsbece154b_datapath.v
// ECE 154B, RISC-V pipelined processor 
// All Rights Reserved
// Copyright (c) 2024 UCSB ECE
// Distribution Prohibited

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
// TO DO: MODIFY FETCH AND EXECUTE STAGE BELOW TO IMPLEMENT BRANCH PREDICTOR
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module ucsbece154b_datapath (
    input                clk, reset,
    input                PCSrcE_i,
    input                StallF_i,
    input                StallD_i,
    input                FlushD_i,
    output wire    [6:0] op_o,
    output wire    [2:0] funct3_o,
    output wire          funct7b5_o,
    input                RegWriteW_i,
    input          [2:0] ImmSrcD_i,
    output wire    [4:0] Rs1D_o,
    output wire    [4:0] Rs2D_o,
    input  wire          FlushE_i,
    output reg     [4:0] Rs1E_o,
    output reg     [4:0] Rs2E_o, 
    output reg     [4:0] RdE_o, 
    input                ALUSrcE_i,
    input          [2:0] ALUControlE_i,
    input          [1:0] ForwardAE_i,
    input          [1:0] ForwardBE_i,
    output               ZeroE_o,
    output reg     [4:0] RdM_o, 
    output reg    [31:0] ALUResultM_o,
    output reg    [31:0] WriteDataM_o,
    input         [31:0] ReadDataM_i,
    input          [1:0] ResultSrcW_i,
    output reg     [4:0] RdW_o,
    input          [1:0] ResultSrcM_i
);

`include "ucsbece154b_defines.vh"

//********************************************** for ICACHE instantiation
//wires for icache
reg reset_flag;
wire hit_w;

wire sdramDataReady, sdramReadRequest;
wire [31:0] sdramDataIn, sdramReadAddress;

reg [31:0] PCF;
wire [31:0] InstrF;
wire [31:0] PCTargetE;
reg [31:0] ResultW;
wire [31:0] PCPlus4F = PCF + 32'd4;
wire [31:0] PCnewF = PCSrcE_i ? PCTargetE : PCPlus4F;

//instantiate icache
ucsbece154b_icache icache(
    .clk(clk),
    .reset_i(reset),
    .readEnable_i(!StallF_i),
    .readAddress_i(PCF),

    .sdramDataReady_i(sdramDataReady),
    .sdramDataIn_i(sdramDataIn),
    .sdramReadRequest_o(sdramReadRequest), 
    .sdramReadAddress_o(sdramReadAddress),
    
    .ready_o(hit_w),
    .instruction_o(InstrF)
);

ucsbece154b_cache_controller controller (
    .clk(clk),
    .reset_i(reset),
    .ReadAddress(sdramReadAddress),
    .ReadRequest(sdramReadRequest),
    .Datain_icache(sdramDataIn),
    .Dataready_icache(sdramDataReady)
);

// Define signals earleir if needed here
//output signal from controller into icache to say full block was output

// ***** FETCH STAGE *********************************

// Update registers
always @ (posedge clk) begin
    if (reset) PCF <= pc_start;

    // Stage new address once we have a hit on the current address
    // If a branch is taken, allow it to overwrite current PCF
    else if ((!StallF_i && hit_w) || PCSrcE_i) PCF <= PCnewF;
end

// ***** DECODE STAGE ********************************
reg [31:0] InstrD, PCPlus4D, PCD;
wire [4:0] RdD, FlushD;

assign op_o       = InstrD[6:0];
assign funct3_o   = InstrD[14:12];
assign funct7b5_o = InstrD[30]; 

assign Rs1D_o = InstrD[19:15];
assign Rs2D_o = InstrD[24:20];
assign RdD = InstrD[11:7];

wire FlushE;
// Insert bubbles when the instruction cache misses
assign FlushD = FlushD_i | !hit_w;
assign FlushE = FlushE_i | !hit_w;

// Register File
wire [31:0] RD1D, RD2D;
ucsbece154b_rf rf (
    .clk(~clk),
    .a1_i(Rs1D_o), .a2_i(Rs2D_o), .a3_i(RdW_o),
    .rd1_o(RD1D), .rd2_o(RD2D),
    .we3_i(RegWriteW_i), .wd3_i(ResultW)
);

// Sign extension
reg [31:0] ExtImmD;

always @ * begin
   case(ImmSrcD_i)
      imm_Itype: ExtImmD = {{20{InstrD[31]}},InstrD[31:20]};
      imm_Stype: ExtImmD = {{20{InstrD[31]}},InstrD[31:25],InstrD[11:7]};
      imm_Btype: ExtImmD = {{20{InstrD[31]}},InstrD[7],InstrD[30:25], InstrD[11:8],1'b0};
      imm_Jtype: ExtImmD = {{12{InstrD[31]}},InstrD[19:12],InstrD[20],InstrD[30:21],1'b0};
      imm_Utype: ExtImmD = {InstrD[31:12],12'b0};
      default:   ExtImmD = 32'bx; 
//            `ifdef SIM
//            $warning("Unsupported ImmSrc given: %h", ImmSrc_i);
//            `else
//            ;
//            `endif
   endcase
end

// Update registers


always @ (posedge clk) begin
    if (reset | FlushD) begin
        InstrD   <= 32'b0;
        PCPlus4D <= 32'b0;
        PCD      <= 32'b0;
    end else if (!StallD_i) begin 
        InstrD   <= InstrF;
        PCPlus4D <= PCPlus4F;
        PCD      <= PCF;
    end 
end


// ***** EXECUTE STAGE ******************************
reg [31:0] RD1E, RD2E, PCPlus4E, ExtImmE, PCE; 
reg [31:0] ForwardDataM;

// Forwarding muxes 
reg  [31:0] SrcAE;
always @ * begin
    case (ForwardAE_i)
       forward_mem: SrcAE = ALUResultM_o; 
        forward_wb: SrcAE = ResultW;
        forward_ex: SrcAE = RD1E;
       default: SrcAE = 32'bx;
    endcase
end

reg  [31:0] SrcBE;
reg  [31:0] WriteDataE;
always @ * begin
    case (ForwardBE_i)
       forward_mem: WriteDataE = ForwardDataM; 
        forward_wb: WriteDataE = ResultW;
        forward_ex: WriteDataE = RD2E;
       default: WriteDataE = 32'bx;
    endcase
end


// Mux feeding ALU Src B
always @ * begin
    case (ALUSrcE_i)
        SrcB_imm: SrcBE = ExtImmE;
        SrcB_reg: SrcBE = WriteDataE;
      default: SrcBE = 32'bx;
    endcase
end


// ALU
wire [31:0] ALUResultE;
ucsbece154b_alu alu (
    .a_i(SrcAE), .b_i(SrcBE),
    .alucontrol_i(ALUControlE_i),
    .result_o(ALUResultE),
    .zero_o(ZeroE_o)
);

// PC Target
assign PCTargetE = PCE + ExtImmE;

// Update registers
always @ (posedge clk) begin
    if (reset | FlushE_i) begin
        RD1E     <= 32'b0;
        RD2E     <= 32'b0;
        PCE      <= 32'b0;
        ExtImmE  <= 32'b0;
        PCPlus4E <= 32'b0;
        Rs1E_o   <=  5'b0;
        Rs2E_o   <=  5'b0;
        RdE_o    <=  5'b0;
    end else begin 
        RD1E     <= RD1D;
        RD2E     <= RD2D;
        PCE      <= PCD;
        ExtImmE  <= ExtImmD;
        PCPlus4E <= PCPlus4D;
        Rs1E_o   <= Rs1D_o;
        Rs2E_o   <= Rs2D_o;
        RdE_o    <= RdD;
    end 
end


// ***** MEMORY STAGE ***************************
reg [31:0] ExtImmM, PCPlus4M;

always @ * begin
   case(ResultSrcM_i)
     MuxResult_aluout:  ForwardDataM = ALUResultM_o;
     MuxResult_PCPlus4: ForwardDataM = PCPlus4M;
     MuxResult_imm:     ForwardDataM = ExtImmM;
     default:           ForwardDataM = 32'bx;

   endcase
 end

// Update registers
always @ (posedge clk) begin
    if (reset) begin
        ALUResultM_o <= 32'b0;
        WriteDataM_o <= 32'b0;
        ExtImmM      <= 32'b0;
        PCPlus4M     <= 32'b0;
        RdM_o        <=  5'b0;
    end else begin 
        ALUResultM_o <= ALUResultE;
        WriteDataM_o <= WriteDataE;
        ExtImmM      <= ExtImmE;
        PCPlus4M     <= PCPlus4E;
        RdM_o        <= RdE_o;
    end 
end

// ***** WRITEBACK STAGE ************************
reg [31:0] PCPlus4W, ALUResultW, ReadDataW, ExtImmW;

always @ * begin
   case(ResultSrcW_i)
     MuxResult_mem: ResultW = ReadDataW;
     MuxResult_aluout:  ResultW = ALUResultW;
     MuxResult_PCPlus4:  ResultW = PCPlus4W;
     MuxResult_imm:  ResultW = ExtImmW;
     default:        ResultW = 32'bx;
  //          `ifdef SIM
  //          $warning("Unsupported ResultSrc given: %h", ResultSrc_i);
  //          `else
  //          ;
  //          `endif

  //   end
   endcase
 end

// Update registers
always @ (posedge clk) begin
    if (reset) begin
        ALUResultW <= 32'b0;
        ReadDataW  <= 32'b0;
        ExtImmW    <= 32'b0;
        PCPlus4W   <= 32'b0;
        RdW_o      <=  5'b0;
    end else begin 
        ALUResultW <= ALUResultM_o;
        ReadDataW  <= ReadDataM_i;
        ExtImmW    <= ExtImmM;
        PCPlus4W   <= PCPlus4M;
        RdW_o      <= RdM_o;
    end 
end

endmodule
