//`include "modular_square_simple.v"
module msu (
	clk,
	reset,
	s_axis_tvalid,
	s_axis_tready,
	s_axis_tdata,
	s_axis_tkeep,
	s_axis_tlast,
	s_axis_xfer_size_in_bytes,
	m_axis_tvalid,
	m_axis_tready,
	m_axis_tdata,
	m_axis_tkeep,
	m_axis_tlast,
	m_axis_xfer_size_in_bytes,
	ap_start,
	ap_done,
	start_xfer
);
	localparam [31:0] STATE_INIT = 32'd0;
	localparam [31:0] STATE_RECV = 32'd1;
	localparam [31:0] STATE_SQIN = 32'd2;
	localparam [31:0] STATE_START = 32'd3;
	localparam [31:0] STATE_COMPUTE = 32'd4;
	localparam [31:0] STATE_PREPARE_SEND = 32'd5;
	localparam [31:0] STATE_SEND = 32'd6;
	localparam [31:0] STATE_IDLE = 32'd7;
	parameter signed [31:0] AXI_LEN = 32;
	parameter signed [31:0] C_XFER_SIZE_WIDTH = 32;
	parameter signed [31:0] SQ_IN_BITS = 128;
	parameter signed [31:0] SQ_OUT_BITS = 128;
	parameter signed [31:0] T_LEN = 64;
	input wire clk;
	input wire reset;
	input wire s_axis_tvalid;
	output wire s_axis_tready;
	input wire [(AXI_LEN - 1):0] s_axis_tdata;
	input wire [((AXI_LEN / 8) - 1):0] s_axis_tkeep;
	input wire s_axis_tlast;
	output wire [(C_XFER_SIZE_WIDTH - 1):0] s_axis_xfer_size_in_bytes;
	output wire m_axis_tvalid;
	input wire m_axis_tready;
	output wire [(AXI_LEN - 1):0] m_axis_tdata;
	output wire [((AXI_LEN / 8) - 1):0] m_axis_tkeep;
	output wire m_axis_tlast;
	output wire [(C_XFER_SIZE_WIDTH - 1):0] m_axis_xfer_size_in_bytes;
	input wire ap_start;
	output wire ap_done;
	output wire start_xfer;
	localparam signed [31:0] AXI_IN_COUNT = (((T_LEN / AXI_LEN) * 2) + (SQ_IN_BITS / AXI_LEN));
	localparam signed [31:0] AXI_OUT_COUNT = ((T_LEN / AXI_LEN) + (SQ_OUT_BITS / AXI_LEN));
	localparam signed [31:0] AXI_BYTES_PER_TXN = (AXI_LEN / 8);
	localparam signed [31:0] AXI_IN_BITS = (AXI_IN_COUNT * AXI_LEN);
	localparam signed [31:0] AXI_OUT_BITS = (AXI_OUT_COUNT * AXI_LEN);
	// removed typedef: State
	reg [31:0] state;
	reg [31:0] next_state;
	reg [(T_LEN - 1):0] t_current;
	reg [(T_LEN - 1):0] t_final;
	reg [(SQ_IN_BITS - 1):0] sq_in;
	wire [(SQ_OUT_BITS - 1):0] sq_out;
	wire sq_start;
	wire sq_finished;
	wire final_iteration;
	reg [(AXI_IN_BITS - 1):0] axi_in;
	reg [(AXI_OUT_BITS - 1):0] axi_out;
	reg [(C_XFER_SIZE_WIDTH - 1):0] axi_out_count;
	wire axi_in_shift;
	genvar gi;
	reg reset_1d;
	always @(posedge clk) begin
		reset_1d <= reset;
	end
	always @(posedge clk) begin
		state <= next_state;
	end
	always @(*) begin
		if (reset_1d) begin
			next_state = STATE_INIT;
		end
		else begin
			case (state)
				STATE_INIT: if (ap_start) begin
					next_state = STATE_RECV;
				end
				else begin
					next_state = STATE_INIT;
				end
				STATE_RECV: if (((s_axis_tlast && s_axis_tvalid) && s_axis_tready)) begin
					next_state = STATE_SQIN;
				end
				else begin
					next_state = STATE_RECV;
				end
				STATE_SQIN: next_state = STATE_START;
				STATE_START: next_state = STATE_COMPUTE;
				STATE_COMPUTE: if ((t_current == t_final)) begin
					next_state = STATE_PREPARE_SEND;
				end
				else begin
					next_state = STATE_COMPUTE;
				end
				STATE_PREPARE_SEND: next_state = STATE_SEND;
				STATE_SEND: if (((axi_out_count == (AXI_OUT_COUNT - 1)) && m_axis_tready)) begin
					next_state = STATE_IDLE;
				end
				else begin
					next_state = STATE_SEND;
				end
				STATE_IDLE: next_state = STATE_INIT;
				default: next_state = STATE_INIT;
			endcase
		end
	end
	assign axi_in_shift = ((state == STATE_RECV) && s_axis_tvalid);
	always @(posedge clk) begin
		if (axi_in_shift) begin
			axi_in <= {s_axis_tdata, axi_in[(AXI_IN_BITS - 1):AXI_LEN]};
		end
	end
	always @(posedge clk) begin
		if ((state == STATE_SQIN)) begin
			t_current <= axi_in[(T_LEN - 1):0];
			t_final <= axi_in[((2 * T_LEN) - 1):T_LEN];
			sq_in <= axi_in[(AXI_IN_BITS - 1):(2 * T_LEN)];
		end
		else if (((state == STATE_COMPUTE) && sq_finished)) begin
			t_current <= (t_current + 1);
		end
	end
	assign final_iteration = (sq_finished && (t_current == (t_final - 1)));
	assign sq_start = (state == STATE_START);
	assign s_axis_xfer_size_in_bytes = (AXI_IN_COUNT * AXI_BYTES_PER_TXN);
	assign s_axis_tready = (state == STATE_RECV);
	modular_square_simple #(.MOD_LEN(SQ_IN_BITS)) modsqr(
		.clk(clk),
		.reset(((reset || reset_1d) || (state == STATE_RECV))),
		.start(sq_start),
		.sq_in(sq_in),
		.sq_out(sq_out),
		.valid(sq_finished)
	);
	localparam signed [31:0] SQ_OUT_OFFSET = 2;
	always @(posedge clk) begin
		if (final_iteration) begin
			axi_out_count <= 0;
			axi_out[(T_LEN - 1):0] <= t_current;
			axi_out[(AXI_OUT_BITS - 1):T_LEN] <= sq_out;
		end
		else if (((state == STATE_SEND) && m_axis_tready)) begin
			axi_out <= {{AXI_LEN {1'b0}}, axi_out[(AXI_OUT_BITS - 1):AXI_LEN]};
			axi_out_count <= (axi_out_count + 1);
		end
	end
	assign m_axis_xfer_size_in_bytes = (AXI_OUT_COUNT * AXI_BYTES_PER_TXN);
	assign m_axis_tvalid = ((state == STATE_SEND) && (axi_out_count < AXI_OUT_COUNT));
	assign m_axis_tdata = axi_out[(AXI_LEN - 1):0];
	assign m_axis_tlast = 0;
	assign m_axis_tkeep = {(AXI_LEN / 8) {1'b1}};
	assign start_xfer = (state == STATE_PREPARE_SEND);
	assign ap_done = (state == STATE_IDLE);
endmodule
