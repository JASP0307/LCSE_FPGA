
library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   
entity RS232top is

  port (
    Reset     : in  std_logic;   -- Low-level asynchronous reset
    Clk       : in  std_logic;   -- System clock (20MHz), rising edge 
	
    Data_in   : in  std_logic_vector(7 downto 0);  -- Parallel TX byte 
    Valid_D   : in  std_logic;   -- Handshake signal from guest, active low 
    Ack_in    : out std_logic;   -- Data ack, low when it has been stored
    TX_RDY    : out std_logic;   -- System ready to transmit
    TD        : out std_logic;   -- RS232 Transmission line
	
    RD        : in  std_logic;   -- RS232 Reception line
    Data_out  : out std_logic_vector(7 downto 0);  -- Parallel RX byte
    Data_read : in  std_logic;   -- Send RX data to guest 
    Full      : out std_logic;   -- Internal RX memory full 
    Empty     : out std_logic);  -- Internal RX memory empty

end RS232top;

architecture RTL of RS232top is
 
 ------------------------------------------------------------------------
  -- Components for Transmitter Block
  ------------------------------------------------------------------------

  component TxRS232
    port (
      Clk     : in  std_logic;
      Reset   : in  std_logic;
      Start   : in  std_logic;
      DataIn  : in  std_logic_vector(7 downto 0);
      EOT     : out std_logic;
      TX      : out std_logic);
  end component;

  ------------------------------------------------------------------------
  -- Components for Receiver Block
  ------------------------------------------------------------------------

  component ShiftRegister
    port (
      Reset  : in  std_logic;
      Clk    : in  std_logic;
      Enable : in  std_logic;
      D      : in  std_logic;
      Q      : out std_logic_vector(7 downto 0));
  end component;

  component RxRS232
    port (
      Clk       : in  std_logic;
      Reset     : in  std_logic;
      LineRdIn : in  std_logic;
      ValidOut : out std_logic;
      CodeOut  : out std_logic;
      StoreOut : out std_logic);
  end component;

  component fifo
    port (
      clk   : IN  std_logic;
      srst  : IN  std_logic;
      din   : IN  std_logic_VECTOR(7 downto 0);
      wr_en : IN  std_logic;
      rd_en : IN  std_logic;
      dout  : OUT std_logic_VECTOR(7 downto 0);
      full  : OUT std_logic;
      empty : OUT std_logic);
  end component;

  ------------------------------------------------------------------------
  -- Internal Signals
  ------------------------------------------------------------------------

  signal Data_FF    : std_logic_vector(7 downto 0);
  signal StartTX    : std_logic;  -- start signal for transmitter
  signal LineRdIn   : std_logic;  -- internal RX line
  signal ValidOut   : std_logic;  -- valid bit at the receiver
  signal CodeOut    : std_logic;  -- bit at the receiver output
  signal sinit      : std_logic;  -- fifo reset
  signal Fifo_in    : std_logic_vector(7 downto 0);
  signal Fifo_write : std_logic;
  signal TX_RDY_i   : std_logic;

begin  -- RTL

  Transmisor: TxRS232
    port map (
      Clk   => Clk,
      Reset => Reset,
      Start => StartTX,
      DataIn  => Data_FF,
      EOT   => TX_RDY_i,
      TX    => TD);

  Receptor: RxRS232
    port map (
      Clk       => Clk,
      Reset     => Reset,
      LineRdIn  => LineRdIn,
      ValidOut => ValidOut,
      CodeOut  => CodeOut,
      StoreOut => Fifo_write);

  Shift: ShiftRegister
    port map (
      Reset  => Reset,
      Clk    => Clk,
      Enable => ValidOut,
      D      => CodeOut,
      Q      => Fifo_in);

  sinit <= not Reset;
  
  Internal_memory: fifo
    port map (
      clk   => clk,
      srst  => sinit,
      din   => Fifo_in,
      wr_en => Fifo_write,
      rd_en => Data_read,
      dout  => Data_out,
      full  => Full,
      empty => Empty);

  -- purpose: Clocking process for input protocol
  Clocking : process (Clk, Reset)
  begin
    if Reset = '0' then  -- asynchronous reset (active low)
      Data_FF   <= (others => '0');
      LineRdIn <= '1';
      Ack_in    <= '1';
    elsif rising_edge(Clk) then  -- rising edge of the clock
      LineRdIn <= RD;
      if Valid_D = '0' and TX_RDY_i = '1' then
        Data_FF <= Data_in;
        Ack_in  <= '0';
        StartTX <= '1';
      else
        Ack_in  <= '1';
        StartTX <= '0';
      end if;
    end if;
  end process Clocking;

  TX_RDY <= TX_RDY_i;

end RTL;

