------------------------------------------------------
-- Autor: Juan Antonio López Martín
-- Departamento de Ingeniería Electrónica
------------------------------------------------------
-- Top de placa (Nexys A7) del PIC, a partir del del profesor
-- (Nexys_PICtop/2. Prueba Nexys - Nexys_PICtop/Nexys_PICtop.vhd).
-- Cambios respecto al original:
--   * El PIC habla con el PC por el USB-UART (UART_TXD_IN / UART_RXD_OUT)
--     en vez de por el lazo JA1-JA2.
--   * El PIC no sale de reset hasta que el clk_wiz ha enganchado (locked).
--     El clk_wiz se resetea solo con SW(15), para no crear un bucle
--     reset -> clk_wiz -> locked -> reset.
--   * LED(15) muestra el reset real del PIC (encendido = funcionando).
------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity nexys_PICtop is
  port (

    -- Interfaz USB-RS232 (nombres vistos desde el chip USB: TXD_IN entra a la FPGA)
    UART_TXD_IN     : in  STD_LOGIC;
    UART_RXD_OUT    : out  STD_LOGIC;

	-- Displays 7 segmentos (x8)
    CA                 : out  STD_LOGIC;
    CB                 : out  STD_LOGIC;
    CC                 : out  STD_LOGIC;
    CD                 : out  STD_LOGIC;
    CE                 : out  STD_LOGIC;
    CF                 : out  STD_LOGIC;
    CG                 : out  STD_LOGIC;
    DP                 : out  STD_LOGIC;
    AN                 : out  STD_LOGIC_VECTOR(7 downto 0);

-- Interruptores (x16)
    SW                 : in   STD_LOGIC_VECTOR(15 downto 0);
-- LEDs (x16)
    LED                : out  STD_LOGIC_VECTOR(15 downto 0);

-- Reloj de la FPGA
    CLK100MHZ        : in   STD_LOGIC

	 );
end nexys_PICtop;


architecture a_behavior of nexys_PICtop is

-- declaración de componentes
    component clk_wiz_0
        port (
          reset     : in  std_logic;
          clk_in1   : in  std_logic;
          clk_out1  : out  std_logic;
          locked    : out std_logic);
    end component;

    component PICtop is
		port (
		  Reset    : in  std_logic;           -- Asynchronous, active low
		  Clk      : in  std_logic;           -- System clock, 20 MHz, rising_edge
		  RS232_RX : in  std_logic;           -- RS232 RX line
		  RS232_TX : out std_logic;           -- RS232 TX line
		  switches : out std_logic_vector(7 downto 0);   -- Switch status bargraph
		  Temp_L   : out std_logic_vector(6 downto 0);   -- Display value for TL
		  Temp_H   : out std_logic_vector(6 downto 0));  -- Display value for TH
    end component;


-- declaración de señales
    signal reset, reset_p : std_logic;   -- reset del PIC (activo bajo) y del clk_wiz (activo alto)
    signal clk : std_logic;
    signal locked : std_logic;

    signal contador : UNSIGNED(31 downto 0);

-- signals for UUT (PICtop)
    signal RS232_TX       : std_logic;   -- RS232 Transmission line
    signal RS232_RX       : std_logic;   -- RS232 Reception line
    signal switches       : std_logic_vector(7 downto 0);
    signal Temp_H, Temp_L : std_logic_vector(6 downto 0);

begin

-- Reset del PIC: con SW(15) = '0' el clk_wiz está en reset y locked = '0',
-- así que locked ya incluye el switch (equivale a SW(15) and locked).
     reset <= locked;

-- Visualización de las señales de salida y estado del sistema
     LED(7 downto 0) <= switches;
     LED(14 downto 8) <= "0000000";
     LED(15) <= reset;

-- Conexión con el PC por el puerto microUSB (puerto serie RS232)
     UART_RXD_OUT <= RS232_TX;
     RS232_RX <= UART_TXD_IN;


-- Displays: Muestra el valor de la temperatura en los dos displays inferiores, y anula los otros 6.
    CA <= not(temp_H(0)) when contador(16)='1' else not(temp_L(0));
    CB <= not(temp_H(1)) when contador(16)='1' else not(temp_L(1));
    CC <= not(temp_H(2)) when contador(16)='1' else not(temp_L(2));
    CD <= not(temp_H(3)) when contador(16)='1' else not(temp_L(3));
    CE <= not(temp_H(4)) when contador(16)='1' else not(temp_L(4));
    CF <= not(temp_H(5)) when contador(16)='1' else not(temp_L(5));
    CG <= not(temp_H(6)) when contador(16)='1' else not(temp_L(6));
    DP <= contador(24);      -- El último punto decimal parpadea cada segundo
    AN <= "111111" & not(contador(16)) & (contador(16));


-- Reset del clk_wiz: solo depende del switch (nunca de locked)
  reset_p <= not SW(15);

-- instanciación de componentes
    clk_20MHz : clk_wiz_0 PORT MAP(
        reset => reset_p,
        clk_in1 => CLK100MHz,
        clk_out1 => clk,
        locked => locked);

    UUT : PICtop PORT MAP(
        Reset      => reset,
        Clk        => clk,
        RS232_TX   => RS232_TX,
        RS232_RX   => RS232_RX,
        switches   => switches,
        Temp_L 	   => Temp_L,
        Temp_H     => Temp_H);

    process(reset, clk)
    begin
      if reset='0' then
        contador <= (others => '0');
      elsif clk'event and clk='1' then
          contador <= contador + 1;
          if contador >= 100000000 then
            contador <= (others => '0');
          end if;
      end if;
    end process;

end a_behavior;
