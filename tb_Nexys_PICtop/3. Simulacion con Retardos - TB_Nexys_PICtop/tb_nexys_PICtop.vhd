
library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   
entity TB_nexys_PICtop is
end TB_nexys_PICtop;

architecture Testbench of TB_nexys_PICtop is

  component nexys_PICtop is 
  port (
    
	-- Puertos PMOD de usuario (x4)
	JA 				: inout STD_LOGIC_VECTOR(2 downto 1);    
	
    --Interfaz USB-RS232
--    UART_TXD_IN     : in  STD_LOGIC;
--    UART_RXD_OUT    : out  STD_LOGIC;
--    UART_CTS        : in  STD_LOGIC;
--    UART_RTS        : in  STD_LOGIC;

---------------------------------------------------------------------------------------
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

-- Interruptores (x16) y LEDs (x16)
    SW                 : in   STD_LOGIC_VECTOR(15 downto 0);    
    LED                : out  STD_LOGIC_VECTOR(15 downto 0);   

-- Reloj de la FPGA
    CLK100MHZ        : in   STD_LOGIC

	 );    
   end component;

-- Board signals used in the design 
    signal Clk100MHz : std_logic;
    signal Clk, reset : std_logic;
    signal SW, LED : std_logic_vector(15 downto 0);
    signal CA, CB, CC, CD, CE, CF, CG, DP : std_logic;
    signal AN : std_logic_vector(7 downto 0);
    signal JA : std_logic_vector(2 downto 1);

-- Serial signals
    signal RS232_TX        : std_logic;   -- RS232 Transmission line
    signal RS232_RX        : std_logic;   -- RS232 Reception line
    
-- Time constants
  constant Tclk: time := 10 ns;   -- Clock Period (100 MHz)  
  constant Tclk2: time := 50 ns;  -- Clock Period (20 MHz)

begin

  -- Instantiation of "Unit Under Test" 
  Unit_nexys_PIC :  nexys_PICtop
    port map (
	JA => JA,

    CA => CA,
    CB => CB,
    CC => CC,
    CD => CD,
    CE => CE,
    CF => CF,
    CG => CG,
    DP => DP,
    AN => AN,

    SW => SW,
    LED => LED,
    CLK100MHZ => CLK100MHZ );

-----------------------------------------------------------------

  -- Reset generation (active low)
  reset <= '1', '0' after 75 ns, '1' after 175 ns;


  -- Clock generation (100 MHz)
  CLK100MHz <= Clk;

  p_clk : PROCESS
  BEGIN
     Clk <= '1';
     wait for Tclk/2;
     Clk <= '0';
     wait for Tclk/2;
  END PROCESS;


----------------------------------
-- 1.Señal de reset (entrada) 
     SW (15) <= reset;     			       -- SW(15) reset (active low) 
     SW (14 downto 0) <= (others => '0');  -- SW(14:0) no se usan 
  
-- 2.LEDs
     reset2 <= LED (15);               -- LED(15) vizualizacion de la señal de reset
     switches <= LED (7 downto 0);     -- LED(7:0) visualizacion del valor de los switches remotos

-- 3a.realimentación lineas TD => RD  (necesita un cable entre los pines 1 y 2 del pmodJA)
     RS232_TX <= JA(1);   -- OUTPUT PORT
     JA(2) <= RS232_RX;   -- INPUT PORT

     --RS232_RX <= RS232_TX;      -- RS232 test loop  =>  *** THIS LINE CONNECTS THE 'TD' SERIAL OUTPUT TO THE 'RD' SERIAL INPUT ***  

-- 3b.Conexión de las lineas TD y RD PC mediante el puerto microUSB (puerto serie RS232)
--     RS232_TX <= UART_RXD_OUT;
--     UART_TXD_IN <= RS232_RX;

 
----------------------------------------------------------

-- 4.Generation of the input stimuli
  p_estimuli : PROCESS
  BEGIN

     RS232_RX <= '1';
     wait for 40 us;
     Transmit(RS232_RX, X"49");
     wait for 40 us;
     Transmit(RS232_RX, X"34");
     wait for 40 us;
     Transmit(RS232_RX, X"31");
     wait;
     
  END PROCESS;

end Testbench;

