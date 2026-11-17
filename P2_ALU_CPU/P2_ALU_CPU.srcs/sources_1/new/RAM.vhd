-------------------------------------------------------------------------
-- RAM.vhd
-- Entidad superior de la memoria de datos del PIC.
-- Une los dos bancos como subcomponentes:
--   * ram_dedicada : 0x00 .. 0x3F  (registros especificos, con Reset)
--   * gp_ram       : 0x40 .. 0xFF  (proposito general, sin Reset)
-------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.PIC_pkg.all;

entity RAM is
port (
   Clk      : in    std_logic;                     -- Reloj del sistema (20 MHz)
   Reset    : in    std_logic;                     -- Reset asincrono, activo a nivel bajo
   Write_en : in    std_logic;                     -- Escritura, activa a nivel alto
   OE       : in    std_logic;                     -- Lectura, activa a nivel bajo
   Address  : in    std_logic_vector(7 downto 0);
   Databus  : inout std_logic_vector(7 downto 0);
   Switches : out   std_logic_vector(7 downto 0);
   Temp_L   : out   std_logic_vector(6 downto 0);
   Temp_H   : out   std_logic_vector(6 downto 0));
end RAM;

architecture structural of RAM is
    
    component ep_ram
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
    end component;
    
    component gp_ram
    port (
        Clk      : in    std_logic;
        write_en : in    std_logic;
        oe       : in    std_logic;
        address  : in    std_logic_vector(7 downto 0);
        databus  : inout std_logic_vector(7 downto 0));
    end component;
    
  signal sel_ded : std_logic;   -- '1' -> banco dedicado (0x00..0x3F)
  signal we_ded  : std_logic;
  signal we_gp   : std_logic;
  signal oe_ded  : std_logic;
  signal oe_gp   : std_logic;

begin

  -----------------------------------------------------------------------
  -- Decodificacion de direcciones
  -----------------------------------------------------------------------
  sel_ded <= '1' when Address(7 downto 6) = "00" else '0';

  -- Escritura (activa a nivel alto): solo al banco seleccionado
  we_ded <= Write_en and sel_ded;
  we_gp  <= Write_en and not sel_ded;

  -- Lectura (activa a nivel bajo): el banco no seleccionado queda en '1'
  oe_ded <= OE when sel_ded = '1' else '1';
  oe_gp  <= OE when sel_ded = '0' else '1';

  -----------------------------------------------------------------------
  -- Banco de registros especificos (0x00 .. 0x3F)
  -----------------------------------------------------------------------
  u_ram_dedicada : ep_ram
    port map (
      Clk      => Clk,
      Reset    => Reset,
      write_en => we_ded,
      oe       => oe_ded,
      address  => Address(5 downto 0),
      databus  => Databus,
      Switches => Switches,
      Temp_L   => Temp_L,
      Temp_H   => Temp_H);

  -----------------------------------------------------------------------
  -- Memoria de proposito general (0x40 .. 0xFF)
  -----------------------------------------------------------------------
  u_gp_ram : gp_ram
    port map (
      Clk      => Clk,
      write_en => we_gp,
      oe       => oe_gp,
      address  => Address,
      databus  => Databus);

end structural;