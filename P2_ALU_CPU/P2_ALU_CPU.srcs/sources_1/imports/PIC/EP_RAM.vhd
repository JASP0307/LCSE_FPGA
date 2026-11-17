
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.PIC_pkg.all;

entity ep_ram is
port (
   Clk      : in    std_logic;
   Reset    : in    std_logic;
   write_en : in    std_logic;
   oe       : in    std_logic;
   address  : in    std_logic_vector(5 downto 0);
   databus  : inout std_logic_vector(7 downto 0);
   Switches : out   std_logic_vector(7 downto 0);
   Temp_L   : out   std_logic_vector(6 downto 0);
   Temp_H   : out   std_logic_vector(6 downto 0));
end ep_ram;

architecture behavior of ep_ram is

    signal contents_ram : array8_ram(63 downto 0);
    
begin

p_ram : process (clk, Reset)
begin
    if Reset = '0' then
    
        contents_ram <= (others => X"00");
        contents_ram(to_integer(unsigned(T_STAT)))            <= X"24";

    elsif rising_edge(clk) then
        if write_en = '1' then
          contents_ram(to_integer(unsigned(address))) <= databus;
        end if;
  end if;

end process;

databus <= contents_ram(to_integer(unsigned(address))) when oe = '0' else (others => 'Z');

gen_sw : for i in 0 to 7 generate
    Switches(i) <= contents_ram(to_integer(unsigned(SWITCH_BASE(5 downto 0))) + i)(0);
end generate; 
    
-----------------------------------------------------------------------
-- Decodificador de BCD a 7 segmentos
-----------------------------------------------------------------------
with contents_ram(to_integer(unsigned(T_STAT)))(7 downto 4) select
Temp_H <=
    "0111111" when "0000",  -- 0
    "0000110" when "0001",  -- 1    
    "1011011" when "0010",  -- 2
    "1001111" when "0011",  -- 3
    "1100110" when "0100",  -- 4
    "1101101" when "0101",  -- 5
    "1111101" when "0110",  -- 6
    "0000111" when "0111",  -- 7
    "1111111" when "1000",  -- 8
    "1101111" when "1001",  -- 9
    "1111001" when others;  -- E (error)
    
with contents_ram(to_integer(unsigned(T_STAT)))(3 downto 0) select
Temp_L <=
    "0111111" when "0000",  -- 0
    "0000110" when "0001",  -- 1    
    "1011011" when "0010",  -- 2
    "1001111" when "0011",  -- 3
    "1100110" when "0100",  -- 4
    "1101101" when "0101",  -- 5
    "1111101" when "0110",  -- 6
    "0000111" when "0111",  -- 7
    "1111111" when "1000",  -- 8
    "1101111" when "1001",  -- 9
    "1111001" when others;  -- E (error)

end behavior;