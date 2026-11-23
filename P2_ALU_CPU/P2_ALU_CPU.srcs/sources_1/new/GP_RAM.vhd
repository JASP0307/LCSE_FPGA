library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.PIC_pkg.all;

entity gp_ram is
port (
   Clk      : in    std_logic;
   write_en : in    std_logic;
   oe       : in    std_logic;
   address  : in    std_logic_vector(7 downto 0);
   databus  : inout std_logic_vector(7 downto 0));
end gp_ram;

architecture behavior of gp_ram is

  signal contents_ram : array8_ram(255 downto 0);   -- 8-bit RAM with 256 locations
  signal sel          : std_logic;

begin

  sel <= '1' when address(7 downto 6) /= "00" else '0';

  -------------------------------------------------------------------------
  -- Memoria de proposito general (sin reset)
  -------------------------------------------------------------------------
  p_ram : process (Clk)
  begin
    if rising_edge(Clk) then
      if write_en = '1' and sel = '1' then
        contents_ram(to_integer(unsigned(address))) <= databus;
      end if;
    end if;
  end process;

  databus <= contents_ram(to_integer(unsigned(address)))
             when (oe = '0' and sel = '1')
             else (others => 'Z');

end behavior;