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
begin

Register_A : process(Clk, Reset)
begin
    if Reset = '0' then
        A <= (others =>'0');
    elsif rising_edge(Clk) then
        A <= res_A;
    end if;
end process;

Register_B : process(Clk, Reset)
begin
    if Reset = '0' then
        B <= (others =>'0');
    elsif rising_edge(Clk) then
        B <= res_B;
    end if;
end process;

Register_ACC : process(Clk, Reset)
begin
    if Reset = '0' then
        ACC <= (others =>'0');
    elsif rising_edge(Clk) then
        ACC <= res_ACC;
    end if;
end process;

Register_IDX : process(Clk, Reset)
begin
    if Reset = '0' then
        Index_Reg <= (others =>'0');
    elsif rising_edge(Clk) then
        Index_Reg <= std_logic_vector(res_IndReg);
    end if;
end process;

Operaciones: process(A, B, Alu_op)
begin
    case Alu_op is
    -- no operation
        when nop =>
            Databus <= (others => 'Z');   
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
            Databus <= (others => 'Z');
        when op_mvacc2a =>
            res_A <= ACC;
            Databus <= (others => 'Z');
        when op_mvacc2b =>
            res_B <= ACC;
            Databus <= (others => 'Z');
            
    -- arithmetic operations
        when op_add =>
            res_ACC <= A + B;
            if (res_ACC = 0) then
                FlagZ <= '1';
            else
                FlagZ <= '0';
            end if;
            Databus <= (others => 'Z');
            
        when op_sub =>
            res_ACC <= A - B;
            Databus <= (others => 'Z');
        when op_shiftl => 
            res_ACC <= shift_left(unsigned(ACC),1);
            Databus <= (others => 'Z');
        when op_shiftr =>
            res_ACC <= shift_right(unsigned(ACC),1);
            Databus <= (others => 'Z');
            
    -- logic operations
        when op_and =>
            res_ACC <= A and B;
            if (res_ACC = (others=>'0')) then
                FlagZ <= '1';
            else
                FlagZ <= '0';
            end if;
            Databus <= (others => 'Z');
        when op_or =>
            res_ACC <= A or B;
            if (res_ACC = (others=>'0')) then
                FlagZ <= '1';
            else
                FlagZ <= '0';
            end if;
        when op_xor =>
            res_ACC <= A xor B;
            if (res_ACC = (others=>'0')) then
                FlagZ <= '1';
            else
                FlagZ <= '0';
            end if;
            Databus <= (others => 'Z');
    -- compare operations
        when op_cmpe =>
            if(A = B)then
                FlagZ <= '1';
            else 
                FlagZ <= '0';
            end if;
            Databus <= (others => 'Z');
        when op_cmpl =>
            if(A < B)then
                FlagZ <= '1';
            else 
                FlagZ <= '0';
            end if;
            Databus <= (others => 'Z');
        when op_cmpg =>
            if(A > B)then
                FlagZ <= '1';
            else 
                FlagZ <= '0';
            end if;
            Databus <= (others => 'Z');
        when op_ascii2bin =>
            if (unsigned(A(3 downto 0))> "1001") then
                res_ACC <= X"FF";
                FlagE <= '1';
            else
                res_ACC <= unsigned(A(3 downto 0));
                FlagE <= '0';
            end if;
            Databus <= (others => 'Z');
        when op_bin2ascii =>
            if (A < X"10") then
                if (A > "1001") then
                    res_ACC <= X"FF";
                    FlagE <= '1';
                else
                    res_ACC <= "0011" & unsigned(A);
                    FlagE <= '0';
                end if;
            end if;
            Databus <= (others => 'Z');
    -- output enable
        when op_oeacc =>
            Databus <= std_logic_vector(ACC);
        when others =>
            Databus <= (others => 'Z');
    end case;

end process;

end Behavioral;
