
`timescale 1ns/100ps

   `define ADD  4'b0000
   `define SUB  4'b0001
   `define SLT  4'b0010
   `define SLTU 4'b0011
   `define AND  4'b0100
   `define XOR  4'b0101
   `define OR   4'b0110
   `define NOR  4'b0111
   `define LUI  4'b1000

module multi_cycle_mips(

   input clk,
   input reset,

   // Memory Ports
   output  [31:0] mem_addr,
   input   [31:0] mem_read_data,
   output  [31:0] mem_write_data,
   output         mem_read,
   output         mem_write
);

   // Data Path Registers
   reg MRE, MWE;
   reg [31:0] A, B, PC, IR, MDR, MAR;
   reg [31:0] hi , lo;

   // Data Path Control Lines, donot forget, regs are not always regs !!
   reg setMRE, clrMRE, setMWE, clrMWE;
   reg Awrt, Bwrt, RFwrt, PCwrt, IRwrt, MDRwrt, MARwrt , HIwrt , LOwrt;
   

   // Memory Ports Binding
   assign mem_addr = MAR;
   assign mem_read = MRE;
   assign mem_write = MWE;
   assign mem_write_data = B;

   // Mux & ALU Control Lines
   reg [3:0] aluOp;
   reg [1:0] aluSelB, IorD;
   reg [1:0] j;
   reg SgnExt, aluSelA, MemtoReg, RegDst , PCtoReg;
   reg ready,mult,HIorLO;

   // Wiring
   wire aluZero;
   wire [31:0] aluResult, rfRD1, rfRD2;
   wire ready1;
   wire [63:0]multu;

   // Clocked Registers
   always @( posedge clk ) begin
      if( reset )
         PC <= #0.1 32'h00000000;
      else if( PCwrt ) 
			case(j)
				2'b00: PC <= #0.1 aluResult;
				2'b01: PC <= #0.1 rfRD1;
				2'b10: PC <= #0.1 {PC[31:28],IR[25:0],2'b00};
			endcase
      if( Awrt ) A <= #0.1 rfRD1;
      if( Bwrt ) B <= #0.1 rfRD2;

      if( MARwrt ) MAR <= #0.1 (IorD==2'b01) ? aluResult :(IorD==2'b00)? PC :(IorD==2'b10)?{PC[31:28],IR[25:0],2'b00}: rfRD1;

      if( IRwrt ) IR <= #0.1 mem_read_data;
      if( MDRwrt ) MDR <= #0.1 mem_read_data;

      if( reset | clrMRE ) MRE <= #0.1 1'b0;
          else if( setMRE) MRE <= #0.1 1'b1;

      if( LOwrt ) lo <= #0.1 multu[31:0];
      if( HIwrt ) hi <= #0.1 multu[63:32];

      if( reset | clrMWE ) MWE <= #0.1 1'b0;
          else if( setMWE) MWE <= #0.1 1'b1;
   end

   // Register File
   reg_file rf(
      .clk( clk ),
      .write( RFwrt ),

      .RR1( IR[25:21] ),
      .RR2( IR[20:16] ),
      .RD1( rfRD1 ),
      .RD2( rfRD2 ),

      .WR(j ? 5'b11111 : (RegDst ? IR[15:11] : IR[20:16])  ),
      .WD(ready ? (HIorLO ? hi : lo) : (MemtoReg ? MDR : (PCtoReg ? PC : aluResult )) )
   );

   // Sign/Zero Extension
   wire [31:0] SZout = SgnExt ? {{16{IR[15]}}, IR[15:0]} : {16'h0000, IR[15:0]};

   // ALU-A Mux
   wire [31:0] aluA = aluSelA ? A : PC;

   // ALU-B Mux
   reg [31:0] aluB;
   always @(*)
   case (aluSelB)
      2'b00: aluB = B;
      2'b01: aluB = 32'h4;
      2'b10: aluB = SZout;
      2'b11: aluB = SZout << 2;
   endcase

   my_alu alu(
      .A( aluA ),
      .B( aluB ),
      .Op( aluOp ),
      .X( aluResult ),
      .Z( aluZero )
   );

    //mult

   multiplier my_multu(
	.clk(clk),
	.start(mult),
	.A(aluA),
	.B(aluB),
	.Product(multu),
	.ready(ready1)
    );

   // Controller Starts Here

   // Controller State Registers
   reg [4:0] state, nxt_state;

   // State Names & Numbers
   localparam
      RESET = 0, FETCH1 = 1, FETCH2 = 2, FETCH3 = 3, DECODE = 4,
      EX_ALU_R = 7, EX_ALU_I = 8,
      EX_LW_1 = 11, EX_LW_2 = 12, EX_LW_3 = 13, EX_LW_4 = 14, EX_LW_5 = 15,
      EX_SW_1 = 21, EX_SW_2 = 22, EX_SW_3 = 23,
      EX_BRA_1 = 25, EX_BRA_2 = 26,
      EX_ALU_R2 = 31, 
      EX_J = 30;

   // State Clocked Register 
   always @(posedge clk)
      if(reset)
         state <= #0.1 RESET;
      else
         state <= #0.1 nxt_state;

   task PrepareFetch;
      begin
         IorD = 2'b00;
         setMRE = 1;
         MARwrt = 1;
         nxt_state = FETCH1;
      end
   endtask

   // State Machine Body Starts Here
   always @( * ) begin

      nxt_state = 'bx;

      SgnExt = 'bx; IorD = 'bx;
      MemtoReg = 'bx; RegDst = 'bx;
      aluSelA = 'bx; aluSelB = 'bx; aluOp = 'bx;
      HIorLO = 'bx;

      PCwrt = 0;mult = 0;
      Awrt = 0; Bwrt = 0;
      RFwrt = 0; IRwrt = 0;
      MDRwrt = 0; MARwrt = 0;
      setMRE = 0; clrMRE = 0;
      setMWE = 0; clrMWE = 0;
      ready = 0; j = 0;PCtoReg = 0;
	   
      case(state)

         RESET:
            PrepareFetch;

         FETCH1:
            nxt_state = FETCH2;

         FETCH2:
            nxt_state = FETCH3;

         FETCH3: begin
            IRwrt = 1;
            PCwrt = 1;
            clrMRE = 1;
            aluSelA = 0;
            aluSelB = 2'b01;
            aluOp = `ADD;
            nxt_state = DECODE;
         end

         DECODE: begin
            Awrt = 1;
            Bwrt = 1;
            case( IR[31:26] )
               6'b000_000:             // R-format
                  case( IR[5:3] )
                     3'b000: ;
                     3'b001: nxt_state = EX_ALU_R;
                     3'b010: nxt_state = EX_ALU_R;
                     3'b011: nxt_state = EX_ALU_R;
                     3'b100: nxt_state = EX_ALU_R;
                     3'b101: nxt_state = EX_ALU_R;
                     3'b110: ;
                     3'b111: ;
                  endcase

               6'b001_000,             // addi
               6'b001_001,             // addiu
               6'b001_010,             // slti
               6'b001_011,             // sltiu
               6'b001_100,             // andi
               6'b001_101,             // ori
			   6'b001_111,			   //lui
               6'b001_110:             // xori
                  nxt_state = EX_ALU_I;

               6'b100_011:
                  nxt_state = EX_LW_1;

               6'b101_011:
                  nxt_state = EX_SW_1;

               6'b000_100,
               6'b000_101:
                  nxt_state = EX_BRA_1;
				  
				  
               6'b000_010:begin		//jump
					j = 2'b10;
					PCwrt = 1;
					IorD = 2'b10;
					setMRE = 1;
					MARwrt = 1;
					nxt_state = FETCH1;
				end
				
	       6'b000_011:begin           //jal
					ready = 0;
					MemtoReg = 0;
					PCtoReg = 1;
					j = 2'b10;
					RFwrt=1;
					IorD = 2'b10;
    				setMRE = 1;
   					MARwrt = 1;
    				PCwrt = 1;
    				nxt_state=FETCH1;
			end	  	
			    
                  

               // rest of instructiones should be decoded here

            endcase
         end

        EX_ALU_R: begin
                case( IR[5:0])
			6'b100_000,
			6'b100_001:begin   //add or addu
					aluOp = `ADD;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;	
				end
			6'b100_010,
			6'b100_011:begin    //sub or subu
					aluOp = `SUB;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b100_100:begin   //and
					aluOp = `AND;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b100_101:begin    //or
					aluOp = `OR;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b100_110:begin    //xor
					aluOp = `XOR;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b100_111:begin   // nor
					aluOp = `NOR;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b101_010:begin   // slt
					aluOp = `SLT;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b101_011:begin   // sltu
					aluOp = `SLTU;
					RFwrt = 1'b1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b011_001:begin     //multu
					mult = 1;
					aluSelA = 1'b1;
					aluSelB = 2'b00;
					nxt_state = EX_ALU_R2;	
				end
			6'b010_000:begin   //mfhi
					HIorLO = 1;
					ready = 1;
					RFwrt = 1'b1;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b010_010:begin    //mflo
					HIorLO = 0;
					ready = 1;
					RFwrt = 1'b1;
					MemtoReg = 1'b0;
					RegDst = 1'b1;
					PrepareFetch;
				end
			6'b001_000:begin   //jr
					j = 2'b01;
					PCwrt = 1;
					IorD = 2'b11;
    				setMRE = 1;
    				MARwrt = 1;
					nxt_state = FETCH1;
				end
			6'b001_001:begin   //jalr
					j = 2'b01;
					PCwrt = 1;
					ready = 0;
					MemtoReg = 0;
					PCtoReg = 1;
					RFwrt = 1'b1;
					IorD = 2'b11;
    				setMRE = 1;
   					MARwrt = 1;
    				nxt_state=FETCH1;	 
				end
		endcase
	end

			EX_ALU_R2:begin
					mult = 0;
					if(!ready1)
						nxt_state = EX_ALU_R2;
					else
					begin
						HIwrt = 1;
						LOwrt = 1;
						PrepareFetch;end
				end
			

		
         

         EX_ALU_I: begin
            	case(IR[31:26])	
              			 
				 6'b001_000:begin             // addi 	
							aluOp = `ADD;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b1;
							PrepareFetch;	
						end  

           			   6'b001_001:begin             //  addiu	
							aluOp = `ADD;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b0;
							PrepareFetch;	
						end  

            			   6'b001_010:begin             // slti	
							aluOp = `SLT;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b1;
							PrepareFetch;	
						
						end
            			   6'b001_011:begin             // sltiu	
							aluOp = `SLTU;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b0;
							PrepareFetch;	

						end
            			   6'b001_100:begin             // andi	
							aluOp = `AND;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b0;
							PrepareFetch;

						end
             			  6'b001_101:begin             // ori	
							aluOp = `OR;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b0;
							PrepareFetch;

						end
              			 6'b001_110:begin             // xori	
							aluOp = `XOR;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b0;
							PrepareFetch;	
	
						end
						
						6'b001_111:begin        //lui	
							aluOp = `LUI;
							RFwrt = 1'b1;
							aluSelA = 1'b1;
							aluSelB = 2'b10;
							MemtoReg = 1'b0;
							RegDst = 1'b0;
							SgnExt = 1'b0;
							PrepareFetch;
						end
		endcase
         end

         EX_LW_1: begin
            		MARwrt = 1'b1;
			aluSelA = 1'b1;
			aluSelB = 2'b10;
			SgnExt = 1'b1;
			setMRE = 1'b1;
			IorD = 2'b01;
			aluOp = `ADD;
			nxt_state = EX_LW_2;

         end

	     EX_LW_2: begin
		nxt_state = EX_LW_3;
	 end
	
	     EX_LW_3:begin
		nxt_state = EX_LW_4;
	 end

	     EX_LW_4:begin
		MDRwrt = 1'b1;
		clrMRE = 1'b1;
		nxt_state = EX_LW_5;
	 end

	     EX_LW_5:begin
		MemtoReg = 1'b1;
		RegDst = 1'b0;
		MDRwrt = 1'b0;
		RFwrt = 1'b1;
		PrepareFetch;
	 end

         EX_SW_1: begin
            	MARwrt = 1'b1;
		aluSelA = 1'b1;
		aluSelB = 2'b10;
		SgnExt = 1'b1;
		setMWE = 1'b1;
		IorD = 2'b01;
		aluOp = `ADD;
		nxt_state = EX_SW_2;
         end

	     EX_SW_2:begin
		clrMWE = 1'b1;
		nxt_state = EX_SW_3;
	 end	
	
	     EX_SW_3:begin
		PrepareFetch;
	 end

         EX_BRA_1: begin
  	        aluOp = `SUB;
		aluSelA = 1'b1;
		aluSelB = 2'b00;
		case( IR[28:26])
			3'b100:
				case(aluZero)
						1'b1 : nxt_state = EX_BRA_2;
						1'b0 : PrepareFetch;
				endcase
			3'b101:
				case(aluZero)
						1'b0 : nxt_state = EX_BRA_2;
						1'b1 : PrepareFetch;
				endcase
		endcase
         end
	     EX_BRA_2: begin
		PCwrt = 1'b1;
		MARwrt = 1'b1;
		aluOp = `ADD;
		aluSelA = 1'b0;
		aluSelB = 2'b11;
		SgnExt = 1'b1;
		setMRE = 1'b1;
		IorD = 2'b01;
		nxt_state = FETCH1;
	end
      

	  
	  endcase

   end

endmodule

//==============================================================================

module my_alu(
   input [3:0] Op,
   input [31:0] A,
   input [31:0] B,

   output [31:0] X,
   output        Z
);

   wire sub = Op != `ADD;

   wire [31:0] bb = sub ? ~B : B;

   wire [32:0] sum = A + bb + sub;

   wire sltu = ! sum[32];

   wire v = sub ? 
        ( A[31] != B[31] && A[31] != sum[31] )
      : ( A[31] == B[31] && A[31] != sum[31] );

   wire slt = v ^ sum[31];

   reg [31:0] x;

   always @( * )
      case( Op )
         `ADD : x = sum;
         `SUB : x = sum;
         `SLT : x = slt;
         `SLTU: x = sltu;
         `AND : x =   A & B;
         `OR  : x =   A | B;
         `NOR : x = ~(A | B);
         `XOR : x =   A ^ B;
		 `LUI : x = {B[15:0] , 16'h0000};
         default : x = 32'hxxxxxxxx;
      endcase

   assign #2 X = x;
   assign #2 Z = x == 32'h00000000;

endmodule

//==============================================================================

module reg_file(
   input clk,
   input write,
   input [4:0] WR,
   input [31:0] WD,
   input [4:0] RR1,
   input [4:0] RR2,
   output [31:0] RD1,
   output [31:0] RD2
);

   reg [31:0] rf_data [0:31];

   assign #2 RD1 = rf_data[ RR1 ];
   assign #2 RD2 = rf_data[ RR2 ];   

   always @( posedge clk ) begin
      if ( write )
         rf_data[ WR ] <= WD;

      rf_data[0] <= 32'h00000000;
   end

endmodule

//==============================================================================

//==============================================================================
module multiplier(
//-----------------------Port directions and deceleration
   input clk,  
   input start,
   input [31:0] A, 
   input [31:0] B, 
   output reg [63:0] Product,
   output ready
    );



//------------------------------------------------------

//----------------------------------- register deceleration
reg [63:0] Multiplicand ;
reg [31:0]  Multiplier;
reg [5:0]  counter;
//-------------------------------------------------------

//------------------------------------- wire deceleration
wire product_write_enable;
wire [63:0] adder_output;
//---------------------------------------------------------

//-------------------------------------- combinational logic
assign adder_output = Multiplicand + Product;
assign product_write_enable = Multiplier[0];
assign ready = counter[5];
//---------------------------------------------------------

//--------------------------------------- sequential Logic
always @ (posedge clk)

   if(start) begin
      counter <= 6'b000000 ;
      Multiplier <= B;
      Product <= 64'h0000000000000000;
      Multiplicand <= {32'h00000000, A} ;
   end

   else if(! ready) begin
         counter <= counter + 1;
         Multiplier <= Multiplier >> 1;
         Multiplicand <= Multiplicand << 1;

      if(product_write_enable)
         Product <= adder_output;
   end   

endmodule
