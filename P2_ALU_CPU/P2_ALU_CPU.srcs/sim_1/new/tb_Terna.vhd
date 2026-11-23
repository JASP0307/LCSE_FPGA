-------------------------------------------------------------------------------
-- tb_Terna.vhd
-- Testbench de la terna RS232top + DMA + RAM: recepcion y transmision.
-- (Sucesor de tb_DMA_RX: mismos casos 1-7 mas el caso 8 del interbloqueo.)
--
--   RS232_RX (8E1) --> RS232top (P1, FIFO real) --> DMA --> RAM
--   RS232_TX (8E1) <-- RS232top                 <-- DMA <-- RAM
--
-- El TB hace de CPU: concede los buses (DMA_ACK), lanza los envios
-- (Send_comm) y, cuando la DMA no tiene los buses, lee/escribe la RAM.
-- Como la CPU real, el modelo solo concede los buses en su Idle: nunca
-- mientras esta en Transmit (Send_comm = '1') ni mientras cpu_busy = '1'
-- (ejecutando instrucciones).
-- Monitores:
--   p_monitor    : cada escritura de la DMA en la RAM contra EXPECTED
--   p_tx_monitor : cada trama que sale por RS232_TX contra EXPECTED_TX
--   p_protocol   : bus, FIFO y handshake Valid_D/ACK (Figura 3)
--
-- Casos:
--   1. Estado tras reset
--   2. Comando "I41" con DMA_ACK rapido
--   3. Comando "T23" con DMA_ACK retrasado (3 bytes acumulados en la FIFO)
--   4. Comando "A35" a continuacion (cnt debe volver a 0x00)
--   5. SEND "OK"
--   6. SEND "A5" seguido, con el transmisor aun ocupado
--   7. Comando "I70" por RX mientras hay un SEND ("TX") en curso
--   8. Interbloqueo CPU<->DMA: llega un byte con la CPU ocupada y la CPU
--      ejecuta un SEND sin mirar DMA_RQ. Se repite con Send_comm subiendo
--      0, 1 y 5 ciclos despues de que caiga RX_Empty:
--        8a (0): la DMA aun esta en Idle -> prioridad de Send_comm
--        8b (1): la DMA acaba de entrar en RxBusReq (la carrera real)
--        8c (5): la DMA lleva varios ciclos en RxBusReq
--      En los tres, READY debe llegar, salir la respuesta y recibirse
--      despues el byte pendiente. Bytes "S", "I", "4" -> comando SI4.
--
-- Ejecutar con "run all": el reloj se detiene solo al terminar.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.PIC_pkg.all;

entity tb_Terna is
end tb_Terna;

architecture TestBench of tb_Terna is

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

  component DMA
    port (
      Reset     : in    std_logic;
      Clk       : in    std_logic;
      RCVD_Data : in    std_logic_vector(7 downto 0);
      RX_Full   : in    std_logic;
      RX_Empty  : in    std_logic;
      Data_Read : out   std_logic;
      ACK_out   : in    std_logic;
      TX_RDY    : in    std_logic;
      Valid_D   : out   std_logic;
      TX_Data   : out   std_logic_vector(7 downto 0);
      Address   : out   std_logic_vector(7 downto 0);
      Databus   : inout std_logic_vector(7 downto 0);
      Write_en  : out   std_logic;
      OE        : out   std_logic;
      DMA_RQ    : out   std_logic;
      DMA_ACK   : in    std_logic;
      Send_comm : in    std_logic;
      READY     : out   std_logic);
  end component;

  component RAM
    port (
      Clk      : in    std_logic;
      Reset    : in    std_logic;
      Write_en : in    std_logic;
      OE       : in    std_logic;
      Address  : in    std_logic_vector(7 downto 0);
      Databus  : inout std_logic_vector(7 downto 0);
      Switches : out   std_logic_vector(7 downto 0);
      Temp_L   : out   std_logic_vector(6 downto 0);
      Temp_H   : out   std_logic_vector(6 downto 0));
  end component;

-------------------------------------------------------------------------------
-- Escrituras que se esperan de la DMA en la RAM, en orden
-------------------------------------------------------------------------------

  type wr_t is record
    addr : std_logic_vector(7 downto 0);
    data : std_logic_vector(7 downto 0);
  end record;
  type wr_array is array (natural range <>) of wr_t;

  constant EXPECTED : wr_array(0 to 19) := (
    -- Caso 2: "I41"
    (DMA_RX_BUFFER_MSB, X"49"), (DMA_RX_BUFFER_MID, X"34"),
    (DMA_RX_BUFFER_LSB, X"31"), (NEW_INST, X"FF"),
    -- Caso 3: "T23"
    (DMA_RX_BUFFER_MSB, X"54"), (DMA_RX_BUFFER_MID, X"32"),
    (DMA_RX_BUFFER_LSB, X"33"), (NEW_INST, X"FF"),
    -- Caso 4: "A35"
    (DMA_RX_BUFFER_MSB, X"41"), (DMA_RX_BUFFER_MID, X"33"),
    (DMA_RX_BUFFER_LSB, X"35"), (NEW_INST, X"FF"),
    -- Caso 7: "I70"
    (DMA_RX_BUFFER_MSB, X"49"), (DMA_RX_BUFFER_MID, X"37"),
    (DMA_RX_BUFFER_LSB, X"30"), (NEW_INST, X"FF"),
    -- Caso 8: "SI4", un byte por subcaso
    (DMA_RX_BUFFER_MSB, X"53"), (DMA_RX_BUFFER_MID, X"49"),
    (DMA_RX_BUFFER_LSB, X"34"), (NEW_INST, X"FF"));

-------------------------------------------------------------------------------
-- Bytes que se esperan por la linea RS232_TX, en orden
-------------------------------------------------------------------------------

  type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

  constant EXPECTED_TX : byte_array(0 to 11) := (
    X"4F", X"4B",                       -- Caso 5: "OK"
    X"41", X"35",                       -- Caso 6: "A5"
    X"54", X"58",                       -- Caso 7: "TX"
    X"38", X"61",                       -- Caso 8a: "8a"
    X"38", X"62",                       -- Caso 8b: "8b"
    X"38", X"63");                      -- Caso 8c: "8c"

  constant T_CLK      : time := 50 ns;          -- 20 MHz
  constant BIT_PERIOD : time := 173 * T_CLK;    -- 8.65 us, igual que P1

  function hex (v : std_logic_vector(7 downto 0)) return string is
    constant H : string(1 to 16) := "0123456789ABCDEF";
  begin
    if Is_X(v) then
      return "??";
    end if;
    return H(to_integer(unsigned(v(7 downto 4))) + 1) &
           H(to_integer(unsigned(v(3 downto 0))) + 1);
  end hex;

-----------------------------------------------------------------------------
-- Internal signals
-----------------------------------------------------------------------------

  signal Reset    : std_logic := '0';
  signal Clk      : std_logic := '0';
  signal sim_done : std_logic := '0';

  -- RS232 <-> DMA
  signal RS232_RX  : std_logic := '1';
  signal RS232_TX  : std_logic;
  signal RCVD_Data : std_logic_vector(7 downto 0);
  signal RX_Full   : std_logic;
  signal RX_Empty  : std_logic;
  signal Data_read : std_logic;
  signal TX_Data   : std_logic_vector(7 downto 0);
  signal Valid_D   : std_logic;
  signal Ack_out   : std_logic;
  signal TX_RDY    : std_logic;

  -- Lado bus de la DMA
  signal dma_Address  : std_logic_vector(7 downto 0);
  signal dma_Write_en : std_logic;
  signal dma_OE       : std_logic;
  signal DMA_RQ       : std_logic;
  signal DMA_ACK      : std_logic := '0';
  signal Send_comm    : std_logic := '0';
  signal READY        : std_logic;
  signal dma_owns     : std_logic;      -- la DMA tiene los buses

  -- Lado bus del modelo de CPU
  signal cpu_Address  : std_logic_vector(7 downto 0) := (others => '0');
  signal cpu_Data     : std_logic_vector(7 downto 0) := (others => 'Z');
  signal cpu_Write_en : std_logic := '0';
  signal cpu_OE       : std_logic := '1';

  -- Bus compartido que ve la RAM
  signal Address  : std_logic_vector(7 downto 0);
  signal Databus  : std_logic_vector(7 downto 0);
  signal Write_en : std_logic;
  signal OE       : std_logic;

  -- Salidas de la RAM
  signal Switches : std_logic_vector(7 downto 0);
  signal Temp_L   : std_logic_vector(6 downto 0);
  signal Temp_H   : std_logic_vector(6 downto 0);

  -- Control del TB
  signal ack_delay : natural := 2;      -- ciclos entre DMA_RQ y DMA_ACK
  signal cpu_busy  : std_logic := '0';  -- CPU ejecutando: no concede
  signal wr_idx    : natural := 0;      -- escrituras vistas por el monitor
  signal tx_idx    : natural := 0;      -- tramas vistas en RS232_TX
  signal err_mon   : natural := 0;
  signal err_proto : natural := 0;
  signal err_txp   : natural := 0;      -- protocolo Valid_D/ACK
  signal err_tx    : natural := 0;      -- tramas de RS232_TX

begin  -- TestBench

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
      Full      => RX_Full,
      Empty     => RX_Empty);

  UUT: DMA
    port map (
      Reset     => Reset,
      Clk       => Clk,
      RCVD_Data => RCVD_Data,
      RX_Full   => RX_Full,
      RX_Empty  => RX_Empty,
      Data_Read => Data_read,
      ACK_out   => Ack_out,
      TX_RDY    => TX_RDY,
      Valid_D   => Valid_D,
      TX_Data   => TX_Data,
      Address   => dma_Address,
      Databus   => Databus,
      Write_en  => dma_Write_en,
      OE        => dma_OE,
      DMA_RQ    => DMA_RQ,
      DMA_ACK   => DMA_ACK,
      Send_comm => Send_comm,
      READY     => READY);

  MEM: RAM
    port map (
      Clk      => Clk,
      Reset    => Reset,
      Write_en => Write_en,
      OE       => OE,
      Address  => Address,
      Databus  => Databus,
      Switches => Switches,
      Temp_L   => Temp_L,
      Temp_H   => Temp_H);

-----------------------------------------------------------------------------
-- Arbitraje del bus: la DMA lo controla cuando la CPU se lo concede
-- (DMA_ACK) o mientras la CPU espera un envio (Send_comm)
-----------------------------------------------------------------------------

  dma_owns <= '1' when DMA_ACK = '1' or Send_comm = '1' else '0';

  Address  <= dma_Address  when dma_owns = '1' else cpu_Address;
  Write_en <= dma_Write_en when dma_owns = '1' else cpu_Write_en;
  OE       <= dma_OE       when dma_owns = '1' else cpu_OE;
  Databus  <= cpu_Data;                 -- 'Z' salvo cuando la CPU escribe

-----------------------------------------------------------------------------
-- Reset & clock generator
-----------------------------------------------------------------------------

  Reset <= '0', '1' after 500 ns;

  p_clk : process
  begin
    while sim_done = '0' loop
      Clk <= '1';
      wait for T_CLK/2;
      Clk <= '0';
      wait for T_CLK/2;
    end loop;
    wait;
  end process;

-----------------------------------------------------------------------------
-- Modelo de CPU: concede los buses cuando DMA_RQ lleva ack_delay+1 ciclos
-- activo con la CPU libre (ni cpu_busy ni Send_comm), y los recupera
-- cuando la DMA baja DMA_RQ
-----------------------------------------------------------------------------

  p_cpu_arbiter : process
    variable n : natural;
  begin
    DMA_ACK <= '0';
    wait until Reset = '1';
    loop
      n := 0;
      while n <= ack_delay loop
        wait until rising_edge(Clk);
        if DMA_RQ = '1' and Send_comm = '0' and cpu_busy = '0' then
          n := n + 1;
        else
          n := 0;
        end if;
      end loop;
      DMA_ACK <= '1';
      wait until rising_edge(Clk) and DMA_RQ = '0';
      DMA_ACK <= '0';
    end loop;
  end process;

-----------------------------------------------------------------------------
-- Monitor: cada escritura de la DMA en la RAM se compara con EXPECTED
-----------------------------------------------------------------------------

  p_monitor : process (Clk)
    variable idx  : natural := 0;
    variable errs : natural := 0;
  begin
    if rising_edge(Clk) then
      if DMA_ACK = '1' and dma_Write_en = '1' then
        report "DMA escribe [" & hex(Address) & "] <= " & hex(Databus);
        if idx > EXPECTED'high then
          report "Escritura inesperada de la DMA" severity error;
          errs := errs + 1;
        elsif Address /= EXPECTED(idx).addr or Databus /= EXPECTED(idx).data then
          report "Escritura " & integer'image(idx) & " incorrecta: esperado [" &
                 hex(EXPECTED(idx).addr) & "] <= " & hex(EXPECTED(idx).data)
            severity error;
          errs := errs + 1;
        end if;
        idx    := idx + 1;
        wr_idx  <= idx;
        err_mon <= errs;
      end if;
    end if;
  end process;

-----------------------------------------------------------------------------
-- Monitor de la linea TX: decodifica tramas 8E1 y las compara con
-- EXPECTED_TX. Muestrea a mitad de cada bit.
-----------------------------------------------------------------------------

  p_tx_monitor : process
    variable d    : std_logic_vector(7 downto 0);
    variable p    : std_logic;
    variable idx  : natural := 0;
    variable errs : natural := 0;
  begin
    wait until Reset = '1';
    loop
      wait until RS232_TX = '0';
      wait for BIT_PERIOD/2;
      if RS232_TX /= '0' then
        report "TX: bit de start falso" severity error;
        errs := errs + 1;
      else
        p := '0';
        for i in 0 to 7 loop
          wait for BIT_PERIOD;
          d(i) := RS232_TX;
          p    := p xor RS232_TX;
        end loop;
        wait for BIT_PERIOD;
        if RS232_TX /= p then
          report "TX: paridad incorrecta en " & hex(d) severity error;
          errs := errs + 1;
        end if;
        wait for BIT_PERIOD;
        if RS232_TX /= '1' then
          report "TX: bit de stop incorrecto en " & hex(d) severity error;
          errs := errs + 1;
        end if;
        report "TX envia " & hex(d);
        if idx > EXPECTED_TX'high then
          report "TX: byte de mas" severity error;
          errs := errs + 1;
        elsif d /= EXPECTED_TX(idx) then
          report "TX: byte " & integer'image(idx) & " incorrecto, esperado " &
                 hex(EXPECTED_TX(idx)) severity error;
          errs := errs + 1;
        end if;
        idx := idx + 1;
      end if;
      tx_idx <= idx;
      err_tx <= errs;
    end loop;
  end process;

-----------------------------------------------------------------------------
-- Protocolo del bus, de la FIFO y del handshake Valid_D/ACK
-----------------------------------------------------------------------------

  p_protocol : process (Clk)
    variable prev_read : std_logic := '0';
    variable errs      : natural   := 0;
    variable errs_tx   : natural   := 0;
  begin
    if rising_edge(Clk) and Reset = '1' then
      -- Recepcion y bus
      if Data_read = '1' and prev_read = '1' then
        report "Data_read activo mas de un ciclo" severity error;
        errs := errs + 1;
      end if;
      if Data_read = '1' and DMA_ACK = '0' then
        report "Data_read sin tener los buses (DMA_ACK = '0')" severity error;
        errs := errs + 1;
      end if;
      if dma_Write_en = '1' and DMA_ACK = '0' then
        report "La DMA escribe en RAM sin DMA_ACK" severity error;
        errs := errs + 1;
      end if;
      if dma_owns = '0' and (dma_Write_en /= '0' or dma_OE /= '1') then
        report "La DMA activa Write_en/OE sin tener los buses" severity error;
        errs := errs + 1;
      end if;
      if dma_owns = '0' and cpu_OE = '1' and cpu_Write_en = '0'
         and Databus /= "ZZZZZZZZ" then
        report "Databus no esta en alta impedancia sin duenno" severity error;
        errs := errs + 1;
      end if;
      -- Transmision (Figura 3)
      if Ack_out = '0' and Valid_D = '0' then
        report "Valid_D no sube con ACK_out = '0' (Figura 3)" severity error;
        errs_tx := errs_tx + 1;
      end if;
      if Valid_D = '0' and Send_comm = '0' then
        report "Valid_D activo sin Send_comm" severity error;
        errs_tx := errs_tx + 1;
      end if;
      prev_read := Data_read;
      err_proto <= errs;
      err_txp   <= errs_tx;
    end if;
  end process;

-------------------------------------------------------------------------------
-- Secuencia de pruebas
-------------------------------------------------------------------------------

  p_stimulus : process
    variable errs : natural := 0;

    procedure check (cond : boolean; msg : string) is
    begin
      if not cond then
        report msg severity error;
        errs := errs + 1;
      end if;
    end check;

    -- Trama 8E1 como la del receptor de P1: start '0', 8 bits LSB primero,
    -- paridad par, stop '1'
    procedure SendByte (signal   Line : out std_logic;
                        constant D    : in  std_logic_vector(7 downto 0)) is
      variable P : std_logic := '0';
    begin
      for i in 0 to 7 loop
        P := P xor D(i);
      end loop;
      Line <= '0';
      wait for BIT_PERIOD;
      for i in 0 to 7 loop
        Line <= D(i);
        wait for BIT_PERIOD;
      end loop;
      Line <= P;
      wait for BIT_PERIOD;
      Line <= '1';
      wait for BIT_PERIOD;
    end SendByte;

    -- Lectura de la RAM por la CPU (OE activo bajo)
    procedure cpu_read (addr : std_logic_vector(7 downto 0);
                        exp  : std_logic_vector(7 downto 0)) is
    begin
      wait until falling_edge(Clk);
      check(dma_owns = '0', "La CPU lee sin tener los buses");
      cpu_Address <= addr;
      cpu_OE      <= '0';
      wait until falling_edge(Clk);
      check(Databus = exp, "RAM[" & hex(addr) & "] = " & hex(Databus) &
                           ", esperado " & hex(exp));
      cpu_OE      <= '1';
    end cpu_read;

    procedure cpu_write (addr : std_logic_vector(7 downto 0);
                         data : std_logic_vector(7 downto 0)) is
    begin
      wait until falling_edge(Clk);
      check(dma_owns = '0', "La CPU escribe sin tener los buses");
      cpu_Address  <= addr;
      cpu_Data     <= data;
      cpu_Write_en <= '1';
      wait until falling_edge(Clk);
      cpu_Write_en <= '0';
      cpu_Data     <= (others => 'Z');
    end cpu_write;

    -- Espera a que la DMA haya hecho n escrituras en total y vuelva a reposo
    procedure wait_writes (n : natural; timeout : time) is
    begin
      if wr_idx < n then
        wait until wr_idx >= n for timeout;
      end if;
      check(wr_idx >= n, "Timeout: la DMA solo ha hecho " &
                         integer'image(wr_idx) & " de " & integer'image(n) &
                         " escrituras");
      for i in 1 to 10 loop
        wait until rising_edge(Clk);
      end loop;
      check(DMA_RQ = '0' and DMA_ACK = '0', "La DMA no ha devuelto los buses");
      check(READY = '1', "READY no vuelve a '1' tras recibir");
    end wait_writes;

    -- Comprueba el buffer RX como lo haria el programa y limpia NEW_INST
    procedure check_buffer (b0, b1, b2 : std_logic_vector(7 downto 0)) is
    begin
      cpu_read(DMA_RX_BUFFER_MSB, b0);
      cpu_read(DMA_RX_BUFFER_MID, b1);
      cpu_read(DMA_RX_BUFFER_LSB, b2);
      cpu_read(NEW_INST, X"FF");
      cpu_write(NEW_INST, X"00");
      cpu_read(NEW_INST, X"00");
    end check_buffer;

    -- Instruccion SEND, primera mitad: carga el buffer TX y sube Send_comm
    procedure start_send (b0, b1 : std_logic_vector(7 downto 0)) is
    begin
      cpu_write(DMA_TX_BUFFER_MSB, b0);
      cpu_write(DMA_TX_BUFFER_LSB, b1);
      wait until falling_edge(Clk);
      Send_comm <= '1';
      wait for 1 ns;
      check(READY = '0', "READY no baja al instante con Send_comm = '1'");
    end start_send;

    -- Instruccion SEND, segunda mitad: espera READY y baja Send_comm
    procedure end_send (timeout : time) is
    begin
      if READY /= '1' then
        wait until READY = '1' for timeout;
      end if;
      check(READY = '1', "Timeout: READY no vuelve a '1' tras el SEND");
      wait until falling_edge(Clk);
      Send_comm <= '0';
      for i in 1 to 3 loop
        wait until rising_edge(Clk);
      end loop;
      check(Valid_D = '1', "Valid_D no vuelve a reposo tras el SEND");
    end end_send;

    -- Espera a que hayan salido n tramas en total por RS232_TX
    procedure wait_tx (n : natural; timeout : time) is
    begin
      if tx_idx < n then
        wait until tx_idx >= n for timeout;
      end if;
      check(tx_idx >= n, "Timeout: solo han salido " & integer'image(tx_idx) &
                         " de " & integer'image(n) & " bytes por RS232_TX");
    end wait_tx;

    -- Caso 8: llega el byte rx con la CPU ocupada y, 'offset' ciclos
    -- despues de que caiga RX_Empty, la CPU ejecuta SEND sin mirar DMA_RQ
    -- (como la CPU real: en Fetch/Decode no atiende DMA_RQ). n_wr y n_tx son
    -- los totales de escrituras en RAM y de bytes por TX al terminar.
    procedure race_send (rx     : std_logic_vector(7 downto 0);
                         b0, b1 : std_logic_vector(7 downto 0);
                         offset : natural;
                         n_wr   : natural;
                         n_tx   : natural) is
      variable P : std_logic := '0';
    begin
      cpu_busy <= '1';
      cpu_write(DMA_TX_BUFFER_MSB, b0);
      cpu_write(DMA_TX_BUFFER_LSB, b1);
      -- Trama 8E1 sin esperar al final del stop, para no perder la caida
      -- de RX_Empty (la linea ya queda en reposo)
      for i in 0 to 7 loop
        P := P xor rx(i);
      end loop;
      RS232_RX <= '0';
      wait for BIT_PERIOD;
      for i in 0 to 7 loop
        RS232_RX <= rx(i);
        wait for BIT_PERIOD;
      end loop;
      RS232_RX <= P;
      wait for BIT_PERIOD;
      RS232_RX <= '1';
      check(RX_Empty = '1', "Caso 8: la FIFO no estaba vacia antes del byte");
      wait until RX_Empty = '0' for 2 * BIT_PERIOD;
      check(RX_Empty = '0', "Caso 8: el byte no llega a la FIFO");
      -- RX_Empty cae tras un flanco de subida: la DMA lo vera en el siguiente
      wait until falling_edge(Clk);
      for i in 1 to offset loop
        wait until falling_edge(Clk);
      end loop;
      report "  Send_comm sube " & integer'image(offset) &
             " ciclos tras caer RX_Empty (DMA_RQ = " & std_logic'image(DMA_RQ) & ")";
      Send_comm <= '1';
      cpu_busy  <= '0';                 -- en Transmit tampoco concede
      wait for 1 ns;
      check(READY = '0', "READY no baja al instante con Send_comm = '1'");
      end_send(300 us);
      wait_tx(n_tx, 300 us);
      wait_writes(n_wr, 200 us);
      wait for 11 * BIT_PERIOD;         -- hueco antes del siguiente byte
    end race_send;

  begin
    ---------------------------------------------------------------------------
    report "CASO 1: estado tras reset";
    wait for 300 ns;                    -- aun en reset
    check(DMA_RQ = '0', "DMA_RQ /= '0' en reset");
    check(dma_Write_en = '0', "Write_en /= '0' en reset");
    check(dma_OE = '1', "OE /= '1' en reset");
    check(Data_read = '0', "Data_read /= '0' en reset");
    check(Valid_D = '1', "Valid_D /= '1' en reset");
    check(Databus = "ZZZZZZZZ", "Databus no esta en 'Z' en reset");
    check(READY = '1', "READY /= '1' en reposo");
    wait until Reset = '1';
    wait for 2 us;                      -- la FIFO sale de su reset sincrono

    ---------------------------------------------------------------------------
    report "CASO 2: comando I41 con DMA_ACK rapido";
    ack_delay <= 2;
    SendByte(RS232_RX, X"49");          -- 'I'
    SendByte(RS232_RX, X"34");          -- '4'
    SendByte(RS232_RX, X"31");          -- '1'
    wait_writes(4, 200 us);
    check_buffer(X"49", X"34", X"31");
    -- La DMA no debe tocar los registros de perifericos
    check(Switches = X"00", "Switches cambiado por la DMA");
    check(Temp_H = "1011011", "Temp_H /= '2' (T_STAT de reset = 0x24)");
    check(Temp_L = "1100110", "Temp_L /= '4' (T_STAT de reset = 0x24)");

    ---------------------------------------------------------------------------
    report "CASO 3: comando T23 con DMA_ACK retrasado 250 us";
    ack_delay <= 5000;                  -- 3 bytes llegan antes de conceder
    SendByte(RS232_RX, X"54");          -- 'T'
    SendByte(RS232_RX, X"32");          -- '2'
    SendByte(RS232_RX, X"33");          -- '3'
    wait_writes(8, 1 ms);
    check_buffer(X"54", X"32", X"33");

    ---------------------------------------------------------------------------
    report "CASO 4: comando A35 a continuacion";
    ack_delay <= 2;
    SendByte(RS232_RX, X"41");          -- 'A'
    SendByte(RS232_RX, X"33");          -- '3'
    SendByte(RS232_RX, X"35");          -- '5'
    wait_writes(12, 200 us);
    check_buffer(X"41", X"33", X"35");

    ---------------------------------------------------------------------------
    report "CASO 5: SEND OK";
    start_send(X"4F", X"4B");           -- 'O', 'K'
    end_send(300 us);
    check(READY = '1', "READY no vuelve a '1' tras el SEND");

    ---------------------------------------------------------------------------
    report "CASO 6: SEND A5 con el transmisor aun ocupado";
    check(TX_RDY = '0', "El caso 6 debe empezar con el transmisor ocupado");
    start_send(X"41", X"35");           -- 'A', '5'
    end_send(400 us);
    check(READY = '1', "READY no vuelve a '1' tras el SEND");
    wait_tx(4, 300 us);
    wait for 2 * 11 * BIT_PERIOD;       -- no debe salir ningun byte de mas
    check(tx_idx = 4, "Bytes de mas por RS232_TX tras dos SEND: " &
                      integer'image(tx_idx));

    ---------------------------------------------------------------------------
    report "CASO 7: comando I70 por RX con un SEND en curso";
    start_send(X"54", X"58");           -- 'T', 'X'
    SendByte(RS232_RX, X"49");          -- 'I'
    SendByte(RS232_RX, X"37");          -- '7'
    SendByte(RS232_RX, X"30");          -- '0'
    check(wr_idx = 12, "La DMA atiende RX mientras Send_comm = '1'");
    end_send(300 us);
    wait_writes(16, 200 us);
    check_buffer(X"49", X"37", X"30");
    wait_tx(6, 300 us);
    wait for 11 * BIT_PERIOD;

    ---------------------------------------------------------------------------
    report "CASO 8a: SEND justo cuando cae RX_Empty (DMA aun en Idle)";
    race_send(X"53", X"38", X"61", 0, 17, 8);    -- RX 'S', TX "8a"
    report "CASO 8b: SEND un ciclo despues (DMA recien en RxBusReq)";
    race_send(X"49", X"38", X"62", 1, 18, 10);   -- RX 'I', TX "8b"
    report "CASO 8c: SEND con la DMA varios ciclos en RxBusReq";
    race_send(X"34", X"38", X"63", 5, 20, 12);   -- RX '4', TX "8c"
    check_buffer(X"53", X"49", X"34");

    ---------------------------------------------------------------------------
    wait for 1 us;
    check(wr_idx = EXPECTED'length, "Numero de escrituras de la DMA: " &
                                    integer'image(wr_idx));
    check(tx_idx = EXPECTED_TX'length, "Numero de bytes por RS232_TX: " &
                                       integer'image(tx_idx));
    report "FIN: errores estimulo=" & integer'image(errs) &
           " escrituras=" & integer'image(err_mon) &
           " protocolo=" & integer'image(err_proto) &
           " protocolo_TX=" & integer'image(err_txp) &
           " linea_TX=" & integer'image(err_tx);
    if errs + err_mon + err_proto + err_txp + err_tx = 0 then
      report "*** TEST TERNA SUPERADO ***";
    else
      report "*** TEST TERNA CON ERRORES ***" severity error;
    end if;
    sim_done <= '1';
    wait;
  end process;

end TestBench;
