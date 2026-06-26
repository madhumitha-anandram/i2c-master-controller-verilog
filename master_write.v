module master_write #(
    parameter SYS_CLK_FREQ = 50_000_000, // 50 MHz
    parameter I2C_FREQ     = 100_000      // 100 kHz (Standard Mode)
)(
    input clk,
    input rst_n,
    input start,
    input [6:0] addr,
    input [7:0] data,
    output reg scl,
    inout sda,
    output reg busy
);
    // I2C State definitions
    localparam IDLE   = 3'd0;
    localparam START  = 3'd1;
    localparam ADDR   = 3'd2;
    localparam ACK1   = 3'd3;
    localparam DATA   = 3'd4;
    localparam ACK2   = 3'd5;
    localparam STOP   = 3'd6;
    // Clock division logic to run FSM at 4x the I2C SCL frequency
    // This allows dividing each SCL period into 4 phases (0, 1, 2, 3) for setup/hold times.
    localparam CLK_DIV = SYS_CLK_FREQ / (I2C_FREQ * 4);
    
    reg [$clog2(CLK_DIV)-1:0] clk_cnt;
    reg scl_tick; // Tick generated at 4x SCL frequency
    reg [2:0] state;
    reg [1:0] phase;       // 4 sub-phases per SCL clock cycle
    reg [3:0] bit_cnt;     // Bit counter
    reg [7:0] addr_reg;    // Shift register for Address + Write Bit (0)
    reg [7:0] data_reg;    // Shift register for Data
    reg sda_out;           // Reg to hold driven SDA value
    reg sda_oe;            // Output Enable for SDA (1 = drive, 0 = High-Z)
    reg ack_received;      // Internal register to capture slave ACK/NACK status
    // Tri-state buffer control for SDA line
    assign sda = sda_oe ? sda_out : 1'bz;
    // 4x SCL frequency tick generator
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= 0;
            scl_tick <= 1'b0;
        end else begin
            if (state == IDLE && !start) begin
                clk_cnt  <= 0;
                scl_tick <= 1'b0;
            end else begin
                if (clk_cnt == CLK_DIV - 1) begin
                    clk_cnt  <= 0;
                    scl_tick <= 1'b1;
                end else begin
                    clk_cnt  <= clk_cnt + 1;
                    scl_tick <= 1'b0;
                end
            end
        end
    end
    // I2C Master Write State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            phase        <= 2'b00;
            bit_cnt      <= 4'd0;
            addr_reg     <= 8'h00;
            data_reg     <= 8'h00;
            scl          <= 1'b1;
            sda_out      <= 1'b1;
            sda_oe       <= 1'b1; // Drive SDA by default
            busy         <= 1'b0;
            ack_received <= 1'b0;
        end else begin
            if (state == IDLE) begin
                scl          <= 1'b1;
                sda_out      <= 1'b1;
                sda_oe       <= 1'b1;
                busy         <= 1'b0;
                phase        <= 2'b00;
                ack_received <= 1'b0;
                if (start) begin
                    busy     <= 1'b1;
                    state    <= START;
                    addr_reg <= {addr, 1'b0}; // 7-bit Address + Write (0) bit
                    data_reg <= data;
                end
            end else if (scl_tick) begin
                case (state)
                    
                    START: begin
                        // START condition: SDA transitions High -> Low while SCL is High
                        case (phase)
                            2'b00: begin
                                scl     <= 1'b1;
                                sda_out <= 1'b1;
                                sda_oe  <= 1'b1;
                                phase   <= 2'b01;
                            end
                            2'b01: begin
                                scl     <= 1'b1;
                                sda_out <= 1'b0; // SDA falls while SCL remains High
                                sda_oe  <= 1'b1;
                                phase   <= 2'b10;
                            end
                            2'b10: begin
                                scl     <= 1'b0; // SCL falls next to begin data transmission
                                sda_out <= 1'b0;
                                sda_oe  <= 1'b1;
                                phase   <= 2'b11;
                            end
                            2'b11: begin
                                state   <= ADDR;
                                phase   <= 2'b00;
                                bit_cnt <= 4'd8; // Shift 8 bits (7 addr + 1 R/W)
                            end
                        endcase
                    end
                    ADDR: begin
                        // Transmit 7-bit Address + R/W bit
                        case (phase)
                            2'b00: begin
                                scl     <= 1'b0;
                                sda_out <= addr_reg[7]; // Setup data while SCL is low
                                sda_oe  <= 1'b1;
                                phase   <= 2'b01;
                            end
                            2'b01: begin
                                scl     <= 1'b1; // SCL goes High, data must remain stable
                                phase   <= 2'b10;
                            end
                            2'b10: begin
                                scl     <= 1'b1; // SCL remains High for sampling
                                phase   <= 2'b11;
                            end
                            2'b11: begin
                                scl      <= 1'b0; // SCL falls
                                addr_reg <= {addr_reg[6:0], 1'b0}; // Shift address register
                                phase    <= 2'b00;
                                if (bit_cnt == 4'd1) begin
                                    state   <= ACK1;
                                    bit_cnt <= 4'd0;
                                    sda_oe  <= 1'b0; // Release SDA immediately on SCL falling edge
                                end else begin
                                    bit_cnt <= bit_cnt - 1;
                                end
                            end
                        endcase
                    end
                    ACK1: begin
                        // Read Address Acknowledge from Slave
                        case (phase)
                            2'b00: begin
                                scl    <= 1'b0;
                                sda_oe <= 1'b0; // Release SDA to High-Z (let slave drive it)
                                phase  <= 2'b01;
                            end
                            2'b01: begin
                                scl   <= 1'b1; // SCL goes High
                                phase <= 2'b10;
                            end
                            2'b10: begin
                                scl <= 1'b1;
                                // Sample ACK (low = ACK, high = NACK)
                                ack_received <= ~sda;
                                phase <= 2'b11;
                            end
                            2'b11: begin
                                scl   <= 1'b0; // SCL falls
                                state <= DATA;
                                phase   <= 2'b00;
                                bit_cnt <= 4'd8; // Shift 8 data bits
                            end
                        endcase
                    end
                    DATA: begin
                        // Transmit 8-bit Data Frame
                        case (phase)
                            2'b00: begin
                                scl     <= 1'b0;
                                sda_out <= data_reg[7]; // Setup data while SCL is low
                                sda_oe  <= 1'b1;
                                phase   <= 2'b01;
                            end
                            2'b01: begin
                                scl     <= 1'b1; // SCL goes High, data must remain stable
                                phase   <= 2'b10;
                            end
                            2'b10: begin
                                scl     <= 1'b1;
                                phase   <= 2'b11;
                            end
                            2'b11: begin
                                scl      <= 1'b0; // SCL falls
                                data_reg <= {data_reg[6:0], 1'b0}; // Shift data register
                                phase    <= 2'b00;
                                if (bit_cnt == 4'd1) begin
                                    state   <= ACK2;
                                    bit_cnt <= 4'd0;
                                    sda_oe  <= 1'b0; // Release SDA immediately on SCL falling edge
                                end else begin
                                    bit_cnt <= bit_cnt - 1;
                                end
                            end
                        endcase
                    end
                    ACK2: begin
                        // Read Data Acknowledge from Slave
                        case (phase)
                            2'b00: begin
                                scl    <= 1'b0;
                                sda_oe <= 1'b0; // Release SDA to High-Z
                                phase  <= 2'b01;
                            end
                            2'b01: begin
                                scl   <= 1'b1; // SCL goes High
                                phase <= 2'b10;
                            end
                            2'b10: begin
                                scl <= 1'b1;
                                ack_received <= ~sda; // Sample ACK
                                phase <= 2'b11;
                            end
                            2'b11: begin
                                scl   <= 1'b0; // SCL falls
                                state <= STOP;
                                phase <= 2'b00;
                            end
                        endcase
                    end
                    STOP: begin
                        // STOP condition: SDA transitions Low -> High while SCL is High
                        case (phase)
                            2'b00: begin
                                scl     <= 1'b0;
                                sda_out <= 1'b0; // Pull SDA Low while SCL is Low
                                sda_oe  <= 1'b1;
                                phase   <= 2'b01;
                            end
                            2'b01: begin
                                scl     <= 1'b1; // SCL goes High
                                sda_out <= 1'b0;
                                sda_oe  <= 1'b1;
                                phase   <= 2'b10;
                            end
                            2'b10: begin
                                scl     <= 1'b1;
                                sda_out <= 1'b1; // SDA transitions Low -> High (STOP)
                                sda_oe  <= 1'b1;
                                phase   <= 2'b11;
                            end
                            2'b11: begin
                                state <= IDLE;
                                busy  <= 1'b0;
                                phase <= 2'b00;
                            end
                        endcase
                    end
                    
                    default: state <= IDLE;
                endcase
            end
        end
    end
endmodule

