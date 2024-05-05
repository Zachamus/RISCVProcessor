// implement instruction cache module 


module ucsbece154b_icache
(
    input clk,
    input reset_i,
    
    // Read operation is initiated by raising ReadEnable and by supplying a valid 
    // read address ReadAddress at least setup time before the rising edge of the clock.
    // Note: requester should only deassert readEnable after ready is asserted in order for stall logic to work
    input        readEnable_i,
    input [31:0] readAddress_i,
    
    // Controller Bus
    // The ReadRequest = 1 and the valid ReadAddress should be supplied until receiving DataReady signal
    // The SDRAM controller sends the first word of data to cache controller via DataIn after T0 delay and raise DataReady to indicate beginning of the block transfer
    // The DataReady signal is lowered by the SDRAM controller automatically after all words are supplied
    output reg        sdramReadRequest_o, 
    output reg [31:0] sdramReadAddress_o, 
    input             sdramDataReady_i,
    input [31:0]      sdramDataIn_i,
    
    // Ready signal indicates when the instruction cache module outputs a valid instruction
    // Ready signal is set to 1 at some time after the rising edge of the clock but within the same clock cycle.
    // Ready = 0 until valid data are read from main memory and supplied to the Instruction.
    // The high Ready signal and the valid data at the Instruction are only kept for one cycle.
    // Read operation can be performed only when cache is not busy, i.e., Busy = 0.
    // The cache controller raises Busy output when it writes to cache.
    output reg ready_o,
    output reg [31:0] instruction_o
);

// Implementation flags
localparam ADVANCED = 1;

// Counters
reg[31:0] hit_counter;
reg[31:0] miss_counter;

// Cache size constants
// The number of sets and the number of words per block (and hence cache capacity) should be parameterized
// The default values are 8 sets and 4 32-bit words (32 bytes) per block, i.e., 512B capacity.
localparam NUM_SETS   = 8;
localparam BLOCK_SIZE = 4; // 32-bit words per block
localparam NUM_WAYS   = 4; // Fixed

// Derived parameters. Shouldn't need to be altered
localparam BLOCK_BITS = $clog2(BLOCK_SIZE);
localparam SET_BITS   = $clog2(NUM_SETS);
localparam TAG_BITS   = 32 - SET_BITS - BLOCK_BITS - 2;

// Create cache
// Set # of rows containing way # of columns
reg [31:0]         cache_line_data [NUM_SETS-1:0][NUM_WAYS-1:0][BLOCK_SIZE-1:0]; // block size # of words per block
reg [TAG_BITS-1:0] cache_line_tags [NUM_SETS-1:0][NUM_WAYS-1:0]; // one tag per block
reg                cache_line_valid[NUM_SETS-1:0][NUM_WAYS-1:0]; // one valid bit per block

// Parse read address
wire [TAG_BITS-1:0] read_tag;
wire [SET_BITS-1:0] read_set;
wire [BLOCK_BITS-1:0] block_offset;

assign read_tag     = readAddress_i[31:32-TAG_BITS];
assign read_set     = readAddress_i[32-TAG_BITS-1:BLOCK_BITS+2];
assign block_offset = readAddress_i[BLOCK_BITS+2-1:2];

// Registers for writing to cache
reg busy;
reg [TAG_BITS-1:0] req_tag;
reg [SET_BITS-1:0] req_set;
reg [BLOCK_BITS-1:0] req_offset;
reg [BLOCK_BITS-1:0] write_block;

integer set, way, word;
integer write_way;

always @(posedge clk) begin
    
    // Write to cache from PSRAM (Baseline)
    if (sdramDataReady_i && !ADVANCED) begin  
        // First word in burst
        if (!busy) begin
            // Writing starts at block offset 0
            write_block = {BLOCK_BITS{1'b0}}; 

            // Select random way
            write_way = $urandom % NUM_WAYS;

            // Write tag
            cache_line_tags[req_set][write_way] = req_tag;

            // Update flags
            sdramReadRequest_o = 1'b0;
            busy = 1'b1;
        end

        // Write word
        cache_line_data[req_set][write_way][write_block] = sdramDataIn_i;

        // On final word
        if (write_block == {BLOCK_BITS{1'b1}}) begin
            // Set valid bit
            cache_line_valid[req_set][write_way] = 1'b1;

            // Update flags
            busy = 1'b0;
        end
    end

    // Write to cache from PSRAM (ADVANCED)
    else if (sdramDataReady_i && ADVANCED) begin  
        // First word in burst
        if (!busy) begin
            // Writing starts at block offset 0
            write_block = (req_offset == 0) ? 1 : 0;

            // Select random way
            write_way = $urandom % NUM_WAYS;

            // Write tag
            cache_line_tags[req_set][write_way] = req_tag;

            // Write critical word
            cache_line_data[req_set][write_way][req_offset] = sdramDataIn_i;

            // Update flags
            sdramReadRequest_o = 1'b0;
            busy = 1'b1;
        end
        else begin
            // Write word normally
            cache_line_data[req_set][write_way][write_block] = sdramDataIn_i;

            // On final word
            if (write_block == {BLOCK_BITS{1'b1}}) begin
                // Set valid bit
                cache_line_valid[req_set][write_way] = 1'b1;

                // Update flags
                busy = 1'b0;
            end

            // Increment block offset
            write_block = write_block + 1;

            if (write_block == req_offset) begin
                write_block = write_block + 1;
                
                if (req_offset == {BLOCK_BITS{1'b1}}) begin
                    // Set valid bit
                    cache_line_valid[req_set][write_way] = 1'b1;

                    // Update flags
                    busy = 1'b0;
                end
            end 
        end
    end

    // On reset, undo any of the assignments we just made
    if (reset_i) begin
        // Clear cache
        for (set = 0; set < NUM_SETS; set = set+1) begin
            for (way = 0; way < NUM_WAYS; way = way+1) begin
                for (word = 0; word < BLOCK_SIZE; word = word+1) begin
                    cache_line_data[set][way][word] = 32'b0;
                end
                cache_line_tags [set][way] = {TAG_BITS{1'b0}};
                cache_line_valid[set][way] = 1'b0;
            end
        end

        // Clear output regs
        sdramReadRequest_o = 1'b0;
        sdramReadAddress_o = 32'b0;
        ready_o            = 1'b0;
        instruction_o      = 32'b0;
        busy               = 1'b0;

        // Zero counters
        hit_counter  = 32'b0;
        miss_counter = 32'b0;
    end
end

// Check reads at negedge to simulate longer delay in checking cache
always @(negedge clk) begin
    // Reset ready every cycle
    ready_o = 1'b0;
    
    // Read operation
    if (readEnable_i) begin

        // Check for a hit
        for (way = 0; way < NUM_WAYS; way = way+1) begin
            if ((cache_line_tags [read_set][way] == read_tag) && // Check tag
                ((cache_line_valid[read_set][way]) || // Check valid bit
                1'b0 && busy && (read_set == req_set) && ((block_offset == req_offset) || (block_offset <= write_block))) // Early restart
            ) begin
                // On hit
                instruction_o = cache_line_data[read_set][way][block_offset];
                ready_o = 1'b1;
                hit_counter = hit_counter+1;
            end
        end

        // On miss request data from controller
        if (!ready_o && !busy && !sdramReadRequest_o) begin
            sdramReadRequest_o = 1'b1;
            sdramReadAddress_o = readAddress_i;
            miss_counter = miss_counter+1;

            // Latch the requested address
            req_tag = read_tag;
            req_set = read_set;
            req_offset = block_offset;
        end
    end
end

endmodule
