`timescale 1ns / 1ps
module tb_master_write;
    reg clk;
    reg rst_n;
    reg start;
    reg [6:0] addr;
    reg [7:0] data;
    wire scl;
    wire sda;
    wire busy;
    // Pull-up resistor on SDA line (essential for I2C open-drain lines)
    pullup(sda);
    // Instantiation of UUT
    // System Clock = 50 MHz, I2C Clock = 100 kHz
    master_write #(
        .SYS_CLK_FREQ(50_000_000),
        .I2C_FREQ(100_000)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .addr(addr),
        .data(data),
        .scl(scl),
        .sda(sda),
        .busy(busy)
    );
    // Clock generator (50 MHz -> 20ns period)
    always #10 clk = ~clk;
    // Slave model logic to acknowledge transactions
    reg slave_ack_en;
    assign sda = slave_ack_en ? 1'b0 : 1'bz;
    initial begin
        // Initialize signals
        clk = 0;
        rst_n = 0;
        start = 0;
        addr = 7'h00;
        data = 8'h00;
        slave_ack_en = 0;
        // Reset the system
        #100;
        rst_n = 1;
        #100;
        // Testcase 1: Write data 0xA5 to slave address 0x5A
        $display("[TB] Starting I2C Write: Addr = 0x5A, Data = 0xA5");
        addr = 7'h5A;
        data = 8'hA5;
        start = 1;
        #20;
        start = 0; // De-assert start immediately, busy will remain high
        // Monitor protocol events in the testbench
        // Wait for Start condition (SDA falls while SCL is High)
        @(negedge sda);
        if (scl === 1'b1) begin
            $display("[TB] START condition detected successfully.");
        end
        // Wait for 8 SCL falling edges (7 Address bits + 1 R/W bit)
        repeat (8) @(negedge scl);
        // Slave drives ACK on the 9th SCL clock pulse
        #100; // Small delay after SCL falling edge to mimic physical gate delay
        slave_ack_en = 1;
        $display("[TB] Slave driving ACK (SDA = 0) for address phase.");
        // Wait for the 9th falling edge of SCL (ACK pulse complete)
        @(negedge scl);
        #100;
        slave_ack_en = 0; // Release SDA
        $display("[TB] Slave released SDA after address ACK.");
        // Wait for 8 SCL falling edges (8 Data bits)
        repeat (8) @(negedge scl);
        // Slave drives ACK for data byte
        #100;
        slave_ack_en = 1;
        $display("[TB] Slave driving ACK (SDA = 0) for data phase.");
        // Wait for the 9th falling edge of SCL (ACK pulse complete)
        @(negedge scl);
        #100;
        slave_ack_en = 0; // Release SDA
        $display("[TB] Slave released SDA after data ACK.");
        // Wait for STOP condition (SDA rises while SCL is High)
        @(posedge sda);
        if (scl === 1'b1) begin
            $display("[TB] STOP condition detected successfully.");
        end
        // Wait for IDLE state
        #10000;
        $display("[TB] Simulation completed successfully!");
        $finish;
    end
    // Monitor signals in console
    initial begin
        $monitor("Time = %0t ns | State = %0d | SCL = %b | SDA = %b | Busy = %b", 
                 $time, uut.state, scl, sda, busy);
    end
    // Dump waveform for visualization
    initial begin
        $dumpfile("i2c_write.vcd");
        $dumpvars(0, tb_master_write);
    end
endmodule
