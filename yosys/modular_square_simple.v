module modular_square_simple (
	clk,
	reset,
	start,
	sq_in,
	sq_out,
	valid
);
	parameter signed [31:0] MOD_LEN = 128;
	input wire clk;
	input wire reset;
	input wire start;
	input wire [(MOD_LEN - 1):0] sq_in;
	output wire [(MOD_LEN - 1):0] sq_out;
	output reg valid;
	localparam [(MOD_LEN - 1):0] MODULUS = 128'he3e70682c2094cac629f6fbed82c07cd;
	reg [(MOD_LEN - 1):0] cur_sq_in;
	reg [((MOD_LEN * 2) - 1):0] squared;
	reg [(MOD_LEN - 1):0] sq_out_comb;
	localparam [3:0] PIPELINE_DEPTH = 10;
	reg [3:0] valid_count;
	reg running;
	wire valid_next;
	always @(posedge clk) begin
		if (start) begin
			cur_sq_in <= sq_in;
		end
		else if (valid_next) begin
			cur_sq_in <= sq_out_comb;
		end
	end
	assign sq_out = (valid ? cur_sq_in : {MOD_LEN {1'bx}});
	always @(posedge clk) begin
		if (reset) begin
			running <= 0;
			valid_count <= 0;
		end
		else begin
			if ((start || valid_next)) begin
				running <= 1;
				valid_count <= 0;
			end
			else begin
				valid_count <= (valid_count + 1);
			end
		end
	end
	assign valid_next = (running && (valid_count == (PIPELINE_DEPTH - 1)));
	always @(posedge clk) begin
		valid <= valid_next;
	end
	always @(*) begin
		squared = {{MOD_LEN {1'b0}}, cur_sq_in};
		squared = (squared * squared);
		squared = (squared % {{MOD_LEN {1'b0}}, MODULUS});
		sq_out_comb = squared[(MOD_LEN - 1):0];
	end
endmodule
