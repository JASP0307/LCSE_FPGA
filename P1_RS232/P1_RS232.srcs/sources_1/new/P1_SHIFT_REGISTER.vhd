----------------------------------------------------------------------------------
-- Create Date: Sep. 2025
-- Module Name: Shift_Register - Behavioral
-----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity ShiftRegister is
    port (
      Reset  : in  std_logic;
      Clk    : in  std_logic;
      Enable : in  std_logic;
      D      : in  std_logic;
      Q      : out std_logic_vector(7 downto 0));
end ShiftRegister;

architecture Behavioral of ShiftRegister is
  -- Declaracion de las señales internas de la arquitectura
  signal output : STD_LOGIC_VECTOR (7 downto 0);
begin

process (Reset, Clk)

begin
  -- Implementación secuencial del funcionamiento del registro
  if Reset = '0' then
    output <= (others => '0');
    
  elsif rising_edge(Clk) then 
      if Enable = '1' then
        output <= D & output(7 downto 1);
      end if;
  end if;

end process;

-- Asignación de las salidas
Q <= output;
end Behavioral;