`timescale 1ns / 1ps
module tb_master_read;
    reg clk;
    reg rst_n;
    reg start;
    reg [6:0] addr;
    wire [7:0] data_out;
    wire scl;
    wire sda;
    wire busy;
    // Pull-up resistor on SDA line (essential for I2C open-drain lines)
    pullup(sda);
    // Instantiation of UUT
    // System Clock = 50 MHz, I2C Clock = 100 kHz
    master_read #(
        .SYS_CLK_FREQ(50_000_000),
        .I2C_FREQ(100_000)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .addr(addr),
        .data_out(data_out),
        .scl(scl),
        .sda(sda),
        .busy(busy)
    );
    // Clock generator (50 MHz -> 20ns period)
    always #10 clk = ~clk;
    // Slave model logic to drive ACK and data
    reg slave_ack_en;
    reg slave_data_en;
    reg [7:0] test_slave_byte;
    reg [3:0] slave_bit_cnt;
    // Slave drives SDA when slave_ack_en is active (drives 0) 
    // or when slave_data_en is active (drives the current data bit)
    wire slave_data_bit = test_slave_byte[slave_bit_cnt];
    assign sda = slave_ack_en ? 1'b0 : 
                 (slave_data_en ? slave_data_bit : 1'bz);
    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        start = 0;
        addr = 7'h00;
        slave_ack_en = 0;
        slave_data_en = 0;
        test_slave_byte = 8'h3C; // Data byte the slave will send (binary: 00111100)
        slave_bit_cnt = 4'd7;
        // Reset the system
        #100;
        rst_n = 1;
        #100;
        // Start read operation for slave address 0x5A
        $display("[TB] Starting I2C Read: Addr = 0x5A");
        $display("[TB] Expected Read Data from Slave = 0x%h (bin: %b)", test_slave_byte, test_slave_byte);
        addr = 7'h5A;
        start = 1;
        #20;
        start = 0; // De-assert start immediately, busy will remain high
        // Monitor protocol events
        // Wait for START condition (SDA falls while SCL is High)
        @(negedge sda);
        if (scl === 1'b1) begin
            $display("[TB] START condition detected successfully.");
        end
        // Consume the START condition falling edge of SCL
        @(negedge scl);
        // Wait for 8 SCL falling edges (7 Address bits + 1 Read bit)
        repeat (8) @(negedge scl);
        
        // Address byte complete. Slave drives ACK.
        #100; // Small setup delay
        slave_ack_en = 1;
        $display("[TB] Slave driving ACK (SDA = 0) for address phase.");
        // Wait for the 9th falling edge of SCL (ACK pulse complete)
        @(negedge scl);
        #100;
        slave_ack_en = 0; // Release SDA
        $display("[TB] Slave released SDA after address ACK.");
        // Now enter READ phase. The slave must drive the bits of 8'h3C (00111100)
        // Slave updates its output data on the falling edge of SCL.
        slave_bit_cnt = 4'd7;
        slave_data_en = 1;
        
        repeat (8) begin
            $display("[TB] Slave driving data bit[%0d] = %b", slave_bit_cnt, slave_data_bit);
            @(negedge scl);
            #100; // Setup delay after SCL falling edge
            if (slave_bit_cnt > 0) begin
                slave_bit_cnt = slave_bit_cnt - 1;
            end
        end
        
        // 8 data bits transmitted. Slave releases SDA.
        slave_data_en = 0;
        $display("[TB] Slave released SDA after transmitting 8 data bits.");
        // Wait for the 9th falling edge of SCL (NACK pulse from master complete)
        @(negedge scl);
        
        // Wait for STOP condition (SDA rises while SCL is High)
        @(posedge sda);
        if (scl === 1'b1) begin
            $display("[TB] STOP condition detected successfully.");
        end
        // Wait a small duration, then verify output
        #1000;
        $display("[TB] Transaction complete.");
        if (data_out === test_slave_byte) begin
            $display("[TB] SUCCESS: Read data matches expected value 0x%h!", test_slave_byte);
        end else begin
            $display("[TB] ERROR: Read data mismatch! Expected: 0x%h, Got: 0x%h", test_slave_byte, data_out);
        end
        
        #5000;
        $finish;
    end
    // Monitor signals in console
    initial begin
        $monitor("Time = %0t ns | State = %0d | SCL = %b | SDA = %b | Busy = %b | DataOut = 0x%h", 
                 $time, uut.state, scl, sda, busy, data_out);
    end
    // Dump waveform for visualization
    initial begin
        $dumpfile("i2c_read.vcd");
        $dumpvars(0, tb_master_read);
    end
endmodule

