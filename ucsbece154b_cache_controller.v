module ucsbece154b_cache_controller
    
(
    input clk,
    input reset_i,
    input hit,
    
    input [31:0] ReadAddress, // missed cache read request address, need to zero out and provide block starting from 0
    input ReadRequest, // bit to signify a readrequest  
    output reg [31:0] Datain_icache, //parallel word going to icache
    output reg Dataready_icache
);

// Cache size constants
// The number of sets and the number of words per block (and hence cache capacity) should be parameterized
// The default values are 8 sets and 4 32-bit words (32 bytes) per block, i.e., 512B capacity.
localparam NUM_SETS   = 8;
localparam BLOCK_SIZE = 4; // 32-bit words per block
localparam NUM_WAYS   = 4; // Fixed
localparam ADVANCED = 1;

// Derived parameters. Shouldn't need to be altered
localparam BLOCK_BITS = $clog2(BLOCK_SIZE);
localparam SET_BITS   = $clog2(NUM_SETS);
localparam TAG_BITS   = 32 - SET_BITS - BLOCK_BITS - 2;

// Number of cycles to delay before sending first word
localparam DELAY_CYCLES = 5;

// Instantiate imem
wire [31:0] imemOut;
reg  [31:0] imemAddr;

ucsbece154_imem imem (
    .a_i(imemAddr),
    .rd_o(imemOut)
);

// Define state machine
localparam IDLE        = 3'd0;
localparam DELAY       = 3'd1;
localparam MEMORY_READ = 3'd2;
reg [1:0] current_state; 

// Requested word address
reg [31:0] ReadAddressStore;

// Requested word offset
wire[BLOCK_BITS-1:0] ReadAddressWordOffset;
assign ReadAddressWordOffset = ReadAddressStore[BLOCK_BITS+1:2];

// Counters
reg [5:0] delayCounter = 8'd0; // [0, 40]
reg [7:0] sent_counter = 8'd0;
reg [BLOCK_BITS-1:0] word_counter = {BLOCK_BITS{1'b0}};


always @(posedge clk, reset_i) begin
    if (reset_i) begin
        current_state <= IDLE;
        word_counter <= 0;
        imemAddr <= 32'd0;
        Dataready_icache <= 1'b0;
        Datain_icache <= 32'd0;

    end else begin
        
        case (current_state)
        IDLE: begin
            word_counter <= 2'd0;
            Dataready_icache <= 1'b0;
            sent_counter <= 8'd0;
            if(ReadRequest) begin
                current_state <= DELAY;
                ReadAddressStore <= ReadAddress;
            end
        end

        DELAY: begin
            if(delayCounter < DELAY_CYCLES) begin
                delayCounter <= delayCounter + 1;
            end
            else begin
                if (ADVANCED == 0) begin
                current_state <= MEMORY_READ;
                imemAddr <= {ReadAddressStore[31:BLOCK_BITS+2], word_counter, 2'b00};
                word_counter <= word_counter + 1;
                delayCounter <= 8'b0;
                end
                else if (ADVANCED == 1) begin
                current_state <= MEMORY_READ;
                imemAddr <= ReadAddressStore;
                if (ReadAddressWordOffset == 0) begin
                word_counter <= word_counter + 1;
                end
                else begin
                word_counter <= 0;
                end
                delayCounter <= 8'b0;
                
                end
            end
        end

        MEMORY_READ: begin
        if (ADVANCED == 0) begin
            if (sent_counter < BLOCK_SIZE-1) begin
                Datain_icache <= imemOut;
                imemAddr <= {ReadAddressStore[31:BLOCK_BITS+2], word_counter, 2'b00};
                word_counter <= word_counter + 1;
                sent_counter <= sent_counter + 1;
                Dataready_icache <= 1'b1;
            end

            else if (sent_counter == BLOCK_SIZE-1) begin
                Datain_icache <= imemOut;
                current_state <= IDLE;

            end
            end
         else if (ADVANCED == 1) begin
            if (sent_counter < BLOCK_SIZE-1) begin
                if (ReadAddressWordOffset != word_counter) begin
                Datain_icache <= imemOut;
                imemAddr <= {ReadAddressStore[31:BLOCK_BITS+2], word_counter, 2'b00};
                word_counter <= word_counter + 1;
                sent_counter <= sent_counter + 1;
                Dataready_icache <= 1'b1;
                end
                else begin
                Datain_icache <= imemOut;
                imemAddr <= {ReadAddressStore[31:BLOCK_BITS+2], (word_counter + 1), 2'b00}; 
                Dataready_icache <= 1'b1;
                sent_counter <= sent_counter + 1;
                word_counter <= word_counter + 2;
                
                end
            end

            else if (sent_counter == BLOCK_SIZE-1) begin
                Datain_icache <= imemOut;
                current_state <= IDLE;

            end
         
         end
        end
        endcase
    end
end

endmodule
