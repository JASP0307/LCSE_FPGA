----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/10/2026 05:34:45 PM
-- Design Name: 
-- Module Name: ALU - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;
use work.PIC_pkg.all;
-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity ALU is
    port ( Reset        : in  std_logic;
           Clk          : in  std_logic;
           Alu_op       : in alu_op;
           Databus      : inout std_logic_vector(7 downto 0);
           Index_Reg    : out std_logic_vector(7 downto 0);
           FlagZ        : out std_logic;
           FlagC        : out std_logic;
           FlagN        : out std_logic;
           FlagE        : out std_logic
           );
end ALU;

architecture Behavioral of ALU is
    signal A, B : unsigned(Databus'range);
    signal res_A, res_B : unsigned(Databus'range);
    signal ACC, IDX  : unsigned(7 downto 0);
    signal res_ACC  : unsigned(7 downto 0);
    signal res_IndReg : unsigned(7 downto 0);
    signal res_FlagZ, res_FlagC, res_FlagN, res_FlagE : std_logic;
    signal Z, C, N, E : std_logic;
begin

Registers : process(Clk, Reset)
begin
    if Reset = '0' then
        A <= (others =>'0');
        B <= (others =>'0');
        ACC <= (others =>'0');
        IDX <= (others =>'0');
        Z <= '0';
        C <= '0';
        N <= '0';
        E <= '0';
    elsif rising_edge(Clk) then
        A <= res_A;
        B <= res_B;
        ACC <= res_ACC;
        IDX <= res_IndReg;
        Z <= res_FlagZ;
        C <= res_FlagC;
        N <= res_FlagN;
        E <= res_FlagE;

    end if;
end process;

Operaciones: process(A, B, ACC, IDX, Z, C, N, E, Alu_op, Databus)
    variable Aux : unsigned(8 downto 0);
    variable Aux2 : unsigned(4 downto 0);
begin
    
    res_A <= A;
    res_B <= B;
    res_ACC <= ACC;
    res_IndReg <= IDX;
    res_FlagZ <= Z;
    res_FlagC <= C;
    res_FlagN <= N;
    res_FlagE <= E;
    databus <= (others => 'Z');
    case Alu_op is
    -- no operation
        when nop =>
            null; 
    -- external value load    
        when op_lda => 
            res_A <= unsigned(Databus);
        when op_ldb => 
            res_B <= unsigned(Databus);
        when op_ldacc =>
            res_ACC <= unsigned(Databus);
        when op_ldid =>
            res_IndReg <= unsigned(Databus);
            
    -- internal load
        when op_mvacc2id =>
            res_IndReg <= ACC;

        when op_mvacc2a =>
            res_A <= ACC;

        when op_mvacc2b =>
            res_B <= ACC;
            
    -- arithmetic operations
        when op_add =>
            Aux := resize(A, 9) + resize(B, 9);
            res_ACC <= Aux(7 downto 0);
            res_FlagC <= Aux(8);
            if (Aux(7 downto 0) = 0) then
                res_FlagZ <= '1';
            else
                res_FlagZ <= '0';
            end if;
            Aux2 := resize(A(3 downto 0), 5) + resize(B(3 downto 0), 5);
                res_FlagN <= Aux2(4);

        when op_sub =>
            Aux := resize(A, 9) - resize(B, 9);
            res_ACC <= Aux(7 downto 0);
            res_FlagC <= Aux(8);
            if (Aux(7 downto 0) = 0) then
                res_FlagZ <= '1';
            else
                res_FlagZ <= '0';
            end if;
            if (A(3 downto 0) < B(3 downto 0)) then
                res_FlagN <= '1';
            else
                res_FlagN <= '0';
            end if;

        when op_shiftl => 
            res_ACC <= shift_left(ACC,1);
            
        when op_shiftr =>
            res_ACC <= shift_right(ACC,1);
            
    -- logic operations
        when op_and =>
            res_ACC <= A and B;
            if ((A and B) = 0) then
                res_FlagZ <= '1';
            else
                res_FlagZ <= '0';
            end if;
            
        when op_or =>
            res_ACC <= A or B;
            if ((A or B) = 0) then
                res_FlagZ <= '1';
            else
                res_FlagZ <= '0';
            end if;
            
        when op_xor =>
            res_ACC <= A xor B;
            if ((A xor B) = 0) then
                res_FlagZ <= '1';
            else
                res_FlagZ <= '0';
            end if;
            
    -- compare operations
        when op_cmpe =>
            if(A = B)then
                res_FlagZ <= '1';
            else 
                res_FlagZ <= '0';
            end if;
            
        when op_cmpl =>
            if(A < B)then
                res_FlagZ <= '1';
            else 
                res_FlagZ <= '0';
            end if;
            
        when op_cmpg =>
            if(A > B)then
                res_FlagZ <= '1';
            else 
                res_FlagZ <= '0';
            end if;
            
        when op_ascii2bin =>
            if (A < X"30" or A > X"39") then
                res_ACC <= X"FF";
                res_FlagE <= '1';
            else
                res_ACC <= "0000" & A(3 downto 0);
                res_FlagE <= '0';
            end if;
            
        when op_bin2ascii =>
            if (A > 9) then
                res_ACC <= X"FF";
                res_FlagE <= '1';
            else
                res_ACC <= "0011" & A(3 downto 0);
                res_FlagE <= '0';
            end if;
            
    -- output enable
        when op_oeacc =>
            Databus <= std_logic_vector(ACC);
        when others =>
            null;
    end case;

end process;


Index_Reg <= std_logic_vector(IDX);
FlagZ <= Z;
FlagC <= C;
FlagN <= N;
FlagE <= E;

end Behavioral;
