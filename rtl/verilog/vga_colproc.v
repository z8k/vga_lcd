//
// File colproc.vhd, Color Processor
// Project: VGA
// Author : Richard Herveille. Ideas and thoughts: Sherif Taher Eid
//
// rev. 1.0 August   2nd, 2001. Initial Verilog release
// rev. 1.1 August  29th, 2001. Changed statemachine to increase bandwidth.
// rev. 2.0 October  2nd, 2001. Revised core. Included color lookup table in Color Processor

`include "timescale.v"

module vga_colproc(clk, srst, pixel_buffer_di, ColorDepth, PseudoColor, 
						pixel_buffer_empty, pixel_buffer_rreq, RGB_fifo_full,
						RGB_fifo_wreq, R, G, B, 
						clut_req, clut_ack, clut_offs, clut_q);

	//
	// inputs & outputs
	//
	input clk;                    // master clock
	input srst;                   // synchronous reset

	input [31:0] pixel_buffer_di; // Pixel Buffer data input

	input [1:0] ColorDepth;       // color depth (8bpp, 16bpp, 24bpp)
	input       PseudoColor;      // pseudo color enabled (only for 8bpp color depth)

	input  pixel_buffer_empty;
	output pixel_buffer_rreq;     // pixel buffer read request
	reg    pixel_buffer_rreq;

	input  RGB_fifo_full;
	output RGB_fifo_wreq;
	reg    RGB_fifo_wreq;
	output [7:0] R, G, B;         // pixel color information
	reg    [7:0] R, G, B;

	output        clut_req;  // clut request
	reg clut_req;
	input         clut_ack;  // clut acknowledge
	output [ 7:0] clut_offs; // clut offset
	reg [7:0] clut_offs;
	input  [23:0] clut_q;    // clut data in

	//
	// variable declarations
	//
	reg [31:0] DataBuffer;

	reg [7:0] Ra, Ga, Ba;
	reg [1:0] colcnt;
	reg RGBbuf_wreq;

	//
	// Module body
	//

	// store word from pixelbuffer / wishbone input
	always@(posedge clk)
		if (pixel_buffer_rreq)
			DataBuffer <= #1 pixel_buffer_di;

	//
	// generate statemachine
	//
	// extract color information from data buffer
	parameter idle        = 6'b00_0000, 
	          fill_buf    = 6'b00_0001,
	          bw_8bpp     = 6'b00_0010,
	          col_8bpp    = 6'b00_0100,
	          col_16bpp_a = 6'b00_1000,
	          col_16bpp_b = 6'b01_0000,
	          col_24bpp   = 6'b10_0000;

	reg [5:0] c_state; // synopsis enum_state
	reg [5:0] nxt_state; // synopsis enum_state

	// next state decoder
	always@(c_state or pixel_buffer_empty or ColorDepth or PseudoColor or RGB_fifo_full or colcnt or clut_ack)
	begin : nxt_state_decoder
		// initial value
		nxt_state = c_state;

		case (c_state) // synopsis full_case parallel_case
			// idle state
			idle:
				if (!pixel_buffer_empty)
					nxt_state = fill_buf;

			// fill data buffer
			fill_buf:
				case (ColorDepth) // synopsis full_case parallel_case
					2'b00: 
						if (PseudoColor)
							nxt_state = col_8bpp;
						else
							nxt_state = bw_8bpp;

					2'b01:
						nxt_state = col_16bpp_a;

					default:
						nxt_state = col_24bpp;

				endcase

			//
			// 8 bits per pixel
			//
			bw_8bpp:
				if (!RGB_fifo_full && !(|colcnt) )
					if (!pixel_buffer_empty)
						nxt_state = fill_buf;
					else
						nxt_state = idle;

			col_8bpp:
				if (!RGB_fifo_full && !(|colcnt) )
					if (clut_ack)
						if (!pixel_buffer_empty)
							nxt_state = fill_buf;
						else
							nxt_state = idle;

			//
			// 16 bits per pixel
			//
			col_16bpp_a:
				if (!RGB_fifo_full)
					nxt_state = col_16bpp_b;

			col_16bpp_b:
				if (!RGB_fifo_full)
					if (!pixel_buffer_empty)
						nxt_state = fill_buf;
					else
						nxt_state = idle;

			//
			// 24 bits per pixel
			//
			col_24bpp:
				if (!RGB_fifo_full)
					if (colcnt == 2'h1) // (colcnt == 1)
						nxt_state = col_24bpp; // stay in current state
					else if (!pixel_buffer_empty)
						nxt_state = fill_buf;
					else
						nxt_state = idle;

		endcase
	end // next state decoder

	// generate state registers
	always@(posedge clk)
			if (srst)
				c_state <= #1 idle;
			else
				c_state <= #1 nxt_state;


	reg iclut_req;
	reg pixelbuf_rreq;
	reg [7:0] iR, iG, iB, iRa, iGa, iBa;

	// output decoder
	always@(c_state or pixel_buffer_empty or colcnt or DataBuffer or RGB_fifo_full or clut_ack or clut_q or Ba or Ga or Ra)
	begin : output_decoder

		// initial values
		pixelbuf_rreq = 1'b0;
		RGBbuf_wreq = 1'b0;
		iclut_req = 1'b0;
				
		iR  = 'h0;
		iG  = 'h0;
		iB  = 'h0;
		iRa = 'h0;
		iGa = 'h0;
		iBa = 'h0;

		case (c_state) // synopsis full_case parallel_case
			idle:
				if (!pixel_buffer_empty)
					pixelbuf_rreq = 1'b1;

			//		
			// 8 bits per pixel
			//
			bw_8bpp:
			begin
				if (!RGB_fifo_full)
					begin
						RGBbuf_wreq = 1'b1;

						if ( (!pixel_buffer_empty) && !(|colcnt) )
							pixelbuf_rreq = 1'b1;
					end

				case (colcnt) // synopsis full_case parallel_case
					2'b11:
					begin
						iR = DataBuffer[31:24];
						iG = DataBuffer[31:24];
						iB = DataBuffer[31:24];
					end

					2'b10:
					begin
						iR = DataBuffer[23:16];
						iG = DataBuffer[23:16];
						iB = DataBuffer[23:16];
					end

					2'b01:
					begin
						iR = DataBuffer[15:8];
						iG = DataBuffer[15:8];
						iB = DataBuffer[15:8];
					end

					default:
					begin
						iR = DataBuffer[7:0];
						iG = DataBuffer[7:0];
						iB = DataBuffer[7:0];
					end
				endcase
			end

			col_8bpp:
			begin
				if (!RGB_fifo_full & clut_ack)
					begin
						RGBbuf_wreq = 1'b1;

						if ( (!pixel_buffer_empty) && !(|colcnt) )
							pixelbuf_rreq = 1'b1;
					end

				iR = clut_q[23:16];
				iG = clut_q[15: 8];
				iB = clut_q[ 7: 0];

				iclut_req = ~RGB_fifo_full;

				if ( !(|colcnt) && clut_ack)
					iclut_req =1'b0;
			end

			//
			// 16 bits per pixel
			//
			col_16bpp_a:
			begin
				if (!RGB_fifo_full)
					RGBbuf_wreq = 1'b1;

				iR[7:3] = DataBuffer[31:27];
				iG[7:2] = DataBuffer[26:21];
				iB[7:3] = DataBuffer[20:16];
			end

			col_16bpp_b:
			begin
				if (!RGB_fifo_full)
					begin
						RGBbuf_wreq = 1'b1;

						if (!pixel_buffer_empty)
							pixelbuf_rreq = 1'b1;
					end

				iR[7:3] = DataBuffer[15:11];
				iG[7:2] = DataBuffer[10: 5];
				iB[7:3] = DataBuffer[ 4: 0];
			end

			//
			// 24 bits per pixel
			//
			col_24bpp:
			begin
				if (!RGB_fifo_full)
					begin
						RGBbuf_wreq = 1'b1;

						if ( (colcnt != 2'h1) && !pixel_buffer_empty)
							pixelbuf_rreq = 1'b1;
					end


				case (colcnt) // synopsis full_case parallel_case
					2'b11:
					begin
						iR  = DataBuffer[31:24];
						iG  = DataBuffer[23:16];
						iB  = DataBuffer[15: 8];
						iRa = DataBuffer[ 7: 0];
					end

					2'b10:
					begin
						iR  = Ra;
						iG  = DataBuffer[31:24];
						iB  = DataBuffer[23:16];
						iRa = DataBuffer[15: 8];
						iGa = DataBuffer[ 7: 0];
					end

					2'b01:
					begin
						iR  = Ra;
						iG  = Ga;
						iB  = DataBuffer[31:24];
						iRa = DataBuffer[23:16];
						iGa = DataBuffer[15: 8];
						iBa = DataBuffer[ 7: 0];
					end

					default:
					begin
						iR = Ra;
						iG = Ga;
						iB = Ba;
					end
				endcase
			end

		endcase
	end // output decoder

	// generate output registers
	always@(posedge clk)
		begin
			R  <= #1 iR;
			G  <= #1 iG;
			B  <= #1 iB;

			if (RGBbuf_wreq)
				begin
					Ra <= #1 iRa;
					Ba <= #1 iBa;
					Ga <= #1 iGa;
				end

			if (srst)
				begin
					pixel_buffer_rreq <= #1 1'b0;
					RGB_fifo_wreq <= #1 1'b0;
					clut_req <= #1 1'b0;
				end
			else
				begin
					pixel_buffer_rreq <= #1 pixelbuf_rreq;
					RGB_fifo_wreq <= #1 RGBbuf_wreq;
					clut_req <= #1 iclut_req;
				end
	end

	// assign clut offset
	always@(colcnt or DataBuffer)
		case (colcnt) // synopsis full_case parallel_case
			2'b11: clut_offs = DataBuffer[31:24];
			2'b10: clut_offs = DataBuffer[23:16];
			2'b01: clut_offs = DataBuffer[15: 8];
			2'b00: clut_offs = DataBuffer[ 7: 0];
		endcase


	//
	// color counter
	//
	always@(posedge clk)
		if(srst)
			colcnt <= #1 2'b11;
		else if (RGBbuf_wreq)
			colcnt <= #1 colcnt -2'h1;
endmodule