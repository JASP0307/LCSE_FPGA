
LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

USE work.PIC_pkg.all;

entity PICtop is
  port (
    Reset    : in  std_logic;           -- Asynchronous, active low
    Clk      : in  std_logic;           -- System clock, 20 MHz, rising_edge
    RS232_RX : in  std_logic;           -- RS232 RX line
    RS232_TX : out std_logic;           -- RS232 TX line
    switches : out std_logic_vector(7 downto 0);      -- Switch status bargraph
    Temp_L      : out std_logic_vector(6 downto 0);   -- Display value for TL
    Temp_H      : out std_logic_vector(6 downto 0));  -- Display value for TH
end PICtop;

architecture behavior of PICtop is
  -----------------------------------------------------------------------
  --  RS232
  ------------------------------------------------------------------------
  
  component RS232top
    port (
      Reset     : in  std_logic;
      Clk       : in  std_logic;
      Data_in   : in  std_logic_vector(7 downto 0);
      Valid_D   : in  std_logic;
      Ack_in    : out std_logic;
      TX_RDY    : out std_logic;
      TD        : out std_logic;
      RD        : in  std_logic;
      Data_out  : out std_logic_vector(7 downto 0);
      Data_read : in  std_logic;
      Full      : out std_logic;
      Empty     : out std_logic);
  end component;

  ------------------------------------------------------------------------
  -- RAM
  ------------------------------------------------------------------------
  
   component RAM
    port (
      Clk      : in    std_logic;
      Reset    : in    std_logic;
      write_en : in    std_logic;
      oe       : in    std_logic;
      address  : in    std_logic_vector(7 downto 0);
      Databus  : inout std_logic_vector(7 downto 0);
      Switches : out std_logic_vector(7 downto 0);
      Temp_L   : out std_logic_vector(6 downto 0);
      Temp_H   : out std_logic_vector(6 downto 0));
  end component;
  
  ------------------------------------------------------------------------
  --  DMA
  ------------------------------------------------------------------------
  
   component DMA
    port ( Reset 		: in STD_LOGIC;
           Clk 	 		: in STD_LOGIC;
           RCVD_Data 	: in STD_LOGIC_VECTOR (7 downto 0);
           RX_Full 		: in STD_LOGIC;
           RX_Empty     : in STD_LOGIC;
           Data_Read 	: out STD_LOGIC;
           ACK_out 		: in STD_LOGIC;
           TX_RDY 		: in STD_LOGIC;
           Valid_D 		: out STD_LOGIC;
           TX_Data 		: out STD_LOGIC_VECTOR (7 downto 0);
           Address 		: out STD_LOGIC_VECTOR (7 downto 0);
           Databus 		: inout STD_LOGIC_VECTOR (7 downto 0);
           Write_en 	: out STD_LOGIC;
           OE 			: out STD_LOGIC;
           DMA_RQ 		: out STD_LOGIC;
           DMA_ACK 		: in STD_LOGIC;
           Send_comm 	: in STD_LOGIC;
           READY 		: out STD_LOGIC	);
  end component;
  
  ------------------------------------------------------------------------
  --  CPU
  ------------------------------------------------------------------------
  
    component CPU 
    port ( Reset : in  STD_LOGIC;
           Clk : in  STD_LOGIC;
           ROM_Data : in  STD_LOGIC_VECTOR (11 downto 0);
           ROM_Addr : out  STD_LOGIC_VECTOR (11 downto 0);
           RAM_Addr : out  STD_LOGIC_VECTOR (7 downto 0);
           RAM_Write : out  STD_LOGIC;
           RAM_OE : out  STD_LOGIC;
           Databus : inout  STD_LOGIC_VECTOR (7 downto 0);
           DMA_RQ : in  STD_LOGIC;
           DMA_ACK : out  STD_LOGIC;
           SEND_comm : out  STD_LOGIC;
           DMA_READY : in  STD_LOGIC;
           Alu_op : out  alu_op;
           Index_Reg : in  STD_LOGIC_VECTOR (7 downto 0);
           FlagZ : in  STD_LOGIC;
           FlagC : in  STD_LOGIC;
           FlagN : in  STD_LOGIC;
           FlagE : in  STD_LOGIC);
    end component;
  
  ------------------------------------------------------------------------
  --  ROM
  ------------------------------------------------------------------------
  
    component ROM 
    port (
        Instruction     : out std_logic_vector(11 downto 0);  -- Instruction bus
        Program_counter : in  std_logic_vector(11 downto 0));
    end component;
    

  ------------------------------------------------------------------------
  --  ALU
  ------------------------------------------------------------------------
    component ALU
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
    end component;

  -- RS232 y DMA 
  
    signal TX_Data      : STD_LOGIC_VECTOR (7 downto 0);
	signal RCVD_Data    : STD_LOGIC_VECTOR (7 downto 0);
	signal address      : STD_LOGIC_VECTOR (7 downto 0);
	signal databus      : STD_LOGIC_VECTOR (7 downto 0);
	signal Valid_D      : STD_LOGIC;
	signal Ack_out      : STD_LOGIC;
	signal TX_RDY       : STD_LOGIC;
	signal Data_Read    : STD_LOGIC;
	signal Full         : STD_LOGIC;
	signal Empty        : STD_LOGIC;
	signal Write_en     : STD_LOGIC;
	signal OE           : STD_LOGIC;
    signal DMA_RQ       : STD_LOGIC;
    signal DMA_ACK      : STD_LOGIC;
    signal Send_comm    : STD_LOGIC;
    signal READY        : STD_LOGIC;

  -- Bus de la RAM (tras el arbitraje CPU/DMA)

    signal write_en_mem, oe_mem : STD_LOGIC;
    signal address_mem  : STD_LOGIC_VECTOR(7 downto 0);
    signal dma_owns_bus : STD_LOGIC;    -- '1' -> la DMA controla la RAM

  -- CPU, ROM y ALU

    signal rom_data      : STD_LOGIC_VECTOR(11 downto 0);
    signal rom_addr      : STD_LOGIC_VECTOR(11 downto 0);
    signal cpu_ram_addr  : STD_LOGIC_VECTOR(7 downto 0);
    signal cpu_ram_write : STD_LOGIC;
    signal cpu_ram_oe    : STD_LOGIC;
    signal alu_op_s      : alu_op;
    signal index_reg     : STD_LOGIC_VECTOR(7 downto 0);
    signal flagZ, flagC, flagN, flagE : STD_LOGIC;


begin  -- behavior

  RS232_PHY: RS232top
    port map (
        Reset     => Reset,
        Clk       => Clk,
        Data_in   => TX_Data,
        Valid_D   => Valid_D,
        Ack_in    => Ack_out,
        TX_RDY    => TX_RDY,
        TD        => RS232_TX,
        RD        => RS232_RX,
        Data_out  => RCVD_Data,
        Data_read => Data_read,
        Full      => Full,
        Empty     => Empty);

  RAM_PHY: RAM
    port map (
        Clk      => Clk,
        Reset    => Reset,
        write_en => write_en_mem,
        oe       => oe_mem,
        address  => address_mem,
        Databus  => databus,
        Switches => switches,
        Temp_L   => Temp_L,
        Temp_H   => Temp_H );
        
   DMA_PHY: DMA
    port map (
        Clk       => Clk,
        Reset     => Reset,
        RCVD_Data => RCVD_Data,
        RX_Full   => Full,
        RX_Empty  => Empty,
        Data_Read => Data_Read,
        ACK_out   => ACK_out,
        TX_RDY    => TX_RDY,
        Valid_D   => Valid_D,
        TX_Data   => TX_Data,
        Address   => address,
        Databus   => databus,
        Write_en  => Write_en,
        OE        => OE,
        DMA_RQ    => DMA_RQ,
        DMA_ACK   => DMA_ACK,
        Send_comm => Send_comm,
        READY     => READY );

   ROM_PHY: ROM
    port map (
        Instruction     => rom_data,
        Program_counter => rom_addr );

   CPU_PHY: CPU
    port map (
        Reset     => Reset,
        Clk       => Clk,
        ROM_Data  => rom_data,
        ROM_Addr  => rom_addr,
        RAM_Addr  => cpu_ram_addr,
        RAM_Write => cpu_ram_write,
        RAM_OE    => cpu_ram_oe,
        Databus   => databus,
        DMA_RQ    => DMA_RQ,
        DMA_ACK   => DMA_ACK,
        SEND_comm => Send_comm,
        DMA_READY => READY,
        Alu_op    => alu_op_s,
        Index_Reg => index_reg,
        FlagZ     => flagZ,
        FlagC     => flagC,
        FlagN     => flagN,
        FlagE     => flagE );

   ALU_PHY: ALU
    port map (
        Reset     => Reset,
        Clk       => Clk,
        Alu_op    => alu_op_s,
        Databus   => databus,
        Index_Reg => index_reg,
        FlagZ     => flagZ,
        FlagC     => flagC,
        FlagN     => flagN,
        FlagE     => flagE );

  ------------------------------------------------------------------------
  -- Arbitraje del bus de la RAM
  -- La DMA es duena del bus mientras la CPU se lo concede (DMA_ACK, estado
  -- Receive) o le pide transmitir (Send_comm, estado Transmit). En el resto
  -- de estados la RAM la maneja la CPU. Databus es un unico bus triestado
  -- compartido por RAM, DMA, CPU y ALU.
  ------------------------------------------------------------------------
   dma_owns_bus <= DMA_ACK or Send_comm;

   address_mem  <= address  when dma_owns_bus = '1' else cpu_ram_addr;
   write_en_mem <= Write_en when dma_owns_bus = '1' else cpu_ram_write;
   oe_mem       <= OE       when dma_owns_bus = '1' else cpu_ram_oe;

end behavior;