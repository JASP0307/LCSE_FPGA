-------------------------------------------------------------------------------
-- tb_PICtop.vhd
-- Testbench del sistema completo: PICtop con RS232top, DMA, RAM, CPU, ROM y
-- ALU reales, ejecutando el programa de la ROM.
--
-- El TB hace de PC al otro lado de la linea serie (8E1, 115200 bps, un bit
-- de 173 ciclos como en P1). Respeta el protocolo del programa: envia un
-- comando de 3 bytes y espera la respuesta de 2 bytes antes del siguiente.
-- Al PIC se le trata como caja negra: solo se miran RS232_TX, switches,
-- Temp_H y Temp_L. Para lo interno se usan nombres externos VHDL-2008
-- (compilar este fichero con -2008):
--   p_bus_monitor : 'X' en Databus o en el bus de la RAM (contencion)
--   p_watchdog    : Send_comm activo demasiado tiempo (interbloqueo)
--
-- Casos:
--   1. Estado tras reset: switches = 0x00, displays "24", ST? -> "24"
--   2. Interruptores: I41, I71, I40 -> OK y switches; I81, I42, I4X, IX1 -> ER
--      sin cambios
--   3. Lectura de interruptores: SI7 -> S1, SI4 -> S0, SI8 -> ER
--   4. Actuadores: A35, SA3 -> A5, A90, SA9 -> A0; A3X, AX5, SAX -> ER y el
--      actuador 3 sigue a 5
--   5. Termostato: T19 -> displays "19", ST? -> 19; T29; T31, T2X -> ER sin
--      cambios; T00
--   6. Comandos invalidos: X12, SX1, i41 (minuscula) -> ER
--   7. Final: los comandos A/T no han tocado los switches; numero total de
--      bytes por RS232_TX
--
-- Ejecutar con "run all": el reloj se detiene solo al terminar.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.PIC_pkg.all;

entity tb_PICtop is
end tb_PICtop;

architecture TestBench of tb_PICtop is

  component PICtop
    port (
      Reset    : in  std_logic;
      Clk      : in  std_logic;
      RS232_RX : in  std_logic;
      RS232_TX : out std_logic;
      switches : out std_logic_vector(7 downto 0);
      Temp_L   : out std_logic_vector(6 downto 0);
      Temp_H   : out std_logic_vector(6 downto 0));
  end component;

  constant T_CLK      : time := 50 ns;          -- 20 MHz
  constant BIT_PERIOD : time := 173 * T_CLK;    -- 8.65 us, igual que P1
  constant T_RESP     : time := 1 ms;           -- timeout de una respuesta
  constant T_SEND_MAX : time := 400 us;         -- Send_comm maximo (2 bytes)

  type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

  function to_slv (c : character) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(character'pos(c), 8));
  end to_slv;

  function hex (v : std_logic_vector(7 downto 0)) return string is
    constant H : string(1 to 16) := "0123456789ABCDEF";
  begin
    if Is_X(v) then
      return "??";
    end if;
    return H(to_integer(unsigned(v(7 downto 4))) + 1) &
           H(to_integer(unsigned(v(3 downto 0))) + 1);
  end hex;

  -- Byte recibido como texto: el caracter si es imprimible, si no 0xNN
  function show (v : std_logic_vector(7 downto 0)) return string is
  begin
    if not Is_X(v) and unsigned(v) >= 16#20# and unsigned(v) < 16#7F# then
      return "'" & character'val(to_integer(unsigned(v))) & "'";
    end if;
    return "0x" & hex(v);
  end show;

  -- Codificacion de 7 segmentos (gfedcba, activo alto) de la entrega
  function seg (d : natural) return std_logic_vector is
    type seg_table is array (0 to 9) of std_logic_vector(6 downto 0);
    constant SEGS : seg_table := (
      "0111111", "0000110", "1011011", "1001111", "1100110",
      "1101101", "1111101", "0000111", "1111111", "1101111");
  begin
    return SEGS(d);
  end seg;

-----------------------------------------------------------------------------
-- Internal signals
-----------------------------------------------------------------------------

  signal Reset    : std_logic := '0';
  signal Clk      : std_logic := '0';
  signal sim_done : std_logic := '0';
  signal RS232_RX : std_logic := '1';
  signal RS232_TX : std_logic;
  signal switches : std_logic_vector(7 downto 0);
  signal Temp_H   : std_logic_vector(6 downto 0);
  signal Temp_L   : std_logic_vector(6 downto 0);

  -- Bytes que salen por RS232_TX, en orden
  signal tx_log : byte_array(0 to 127) := (others => (others => '0'));
  signal tx_cnt : natural := 0;

  -- Errores de los monitores
  signal err_tx    : natural := 0;      -- tramas mal formadas
  signal err_bus   : natural := 0;      -- 'X' en el bus
  signal err_wdog  : natural := 0;      -- Send_comm atascado

begin  -- TestBench

  UUT: PICtop
    port map (
      Reset    => Reset,
      Clk      => Clk,
      RS232_RX => RS232_RX,
      RS232_TX => RS232_TX,
      switches => switches,
      Temp_H   => Temp_H,
      Temp_L   => Temp_L);

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
-- Monitor de RS232_TX: decodifica tramas 8E1 (muestreo a mitad de bit) y
-- las va guardando en tx_log
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
        if idx <= tx_log'high then
          tx_log(idx) <= d;
        end if;
        idx    := idx + 1;
        tx_cnt <= idx;
      end if;
      err_tx <= errs;
    end loop;
  end process;

-----------------------------------------------------------------------------
-- Monitor del bus interno: a mitad de ciclo (flanco de bajada, ya estable)
-- ningun bit del Databus ni del bus de la RAM puede valer 'X' o 'U'.
-- Una 'X' en el Databus resuelto indica dos bloques conduciendo a la vez.
-----------------------------------------------------------------------------

  p_bus_monitor : process
    alias databus  is << signal .tb_PICtop.UUT.databus      : std_logic_vector(7 downto 0) >>;
    alias addr_mem is << signal .tb_PICtop.UUT.address_mem  : std_logic_vector(7 downto 0) >>;
    alias we_mem   is << signal .tb_PICtop.UUT.write_en_mem : std_logic >>;
    alias oe_mem   is << signal .tb_PICtop.UUT.oe_mem       : std_logic >>;
    variable errs : natural := 0;
    variable bad  : boolean;
  begin
    wait until Reset = '1';
    while sim_done = '0' loop
      wait until falling_edge(Clk);
      bad := false;
      for i in 7 downto 0 loop
        if databus(i) = 'X' or databus(i) = 'U' or
           addr_mem(i) = 'X' or addr_mem(i) = 'U' then
          bad := true;
        end if;
      end loop;
      if we_mem /= '0' and we_mem /= '1' then
        bad := true;
      end if;
      if oe_mem /= '0' and oe_mem /= '1' then
        bad := true;
      end if;
      if bad then
        errs := errs + 1;
        if errs <= 10 then              -- no inundar el log
          report "Bus indefinido: Databus=" & hex(databus) &
                 " Address=" & hex(addr_mem) &
                 " Write_en=" & std_logic'image(we_mem) &
                 " OE=" & std_logic'image(oe_mem) severity error;
        end if;
        err_bus <= errs;
      end if;
    end loop;
    wait;
  end process;

-----------------------------------------------------------------------------
-- Watchdog: un SEND (2 bytes, transmisor quiza ocupado con el anterior)
-- no puede tener Send_comm activo mas de T_SEND_MAX. Si se pasa, la CPU
-- esta esperando un READY que no llega: el interbloqueo con la DMA.
-----------------------------------------------------------------------------

  p_watchdog : process
    alias send_comm is << signal .tb_PICtop.UUT.Send_comm : std_logic >>;
    alias dma_rq    is << signal .tb_PICtop.UUT.DMA_RQ    : std_logic >>;
    variable errs : natural := 0;
  begin
    wait until Reset = '1';
    loop
      wait until send_comm = '1' or sim_done = '1';
      exit when sim_done = '1';
      wait until send_comm = '0' or sim_done = '1' for T_SEND_MAX;
      exit when sim_done = '1';
      if send_comm = '1' then
        report "Send_comm lleva " & time'image(T_SEND_MAX) &
               " activo (DMA_RQ = " & std_logic'image(dma_rq) &
               "): posible interbloqueo CPU-DMA" severity error;
        errs     := errs + 1;
        err_wdog <= errs;
        wait until send_comm = '0' or sim_done = '1';
        exit when sim_done = '1';
      end if;
    end loop;
    wait;
  end process;

-------------------------------------------------------------------------------
-- Secuencia de pruebas
-------------------------------------------------------------------------------

  p_stimulus : process
    variable errs   : natural := 0;
    variable n_cmd  : natural := 0;
    variable n_resp : natural := 0;    -- bytes de respuesta esperados

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

    -- Envia un comando de 3 caracteres y comprueba la respuesta de 2
    procedure cmd (c : string(1 to 3); r : string(1 to 2)) is
      variable n0 : natural;
    begin
      n_cmd  := n_cmd + 1;
      n0     := tx_cnt;
      for i in 1 to 3 loop
        SendByte(RS232_RX, to_slv(c(i)));
      end loop;
      if tx_cnt < n0 + 2 then
        wait until tx_cnt >= n0 + 2 for T_RESP;
      end if;
      n_resp := n_resp + 2;
      if tx_cnt < n0 + 2 then
        check(false, "Comando " & c & ": timeout, solo " &
                     integer'image(tx_cnt - n0) & " de 2 bytes de respuesta");
      elsif tx_log(n0) /= to_slv(r(1)) or tx_log(n0 + 1) /= to_slv(r(2)) then
        check(false, "Comando " & c & ": respuesta " & show(tx_log(n0)) &
                     show(tx_log(n0 + 1)) & ", esperada " & r);
      else
        report "  " & c & " -> " & r;
      end if;
      wait for 3 * BIT_PERIOD;          -- el PC procesa antes del siguiente
    end cmd;

    procedure check_switches (exp : std_logic_vector(7 downto 0);
                              when_s : string) is
    begin
      check(switches = exp, when_s & ": switches = " & hex(switches) &
                            ", esperado " & hex(exp));
    end check_switches;

    procedure check_disp (h, l : natural; when_s : string) is
    begin
      check(Temp_H = seg(h) and Temp_L = seg(l),
            when_s & ": los displays no muestran " &
            integer'image(h) & integer'image(l));
    end check_disp;

  begin
    ---------------------------------------------------------------------------
    report "CASO 1: estado tras reset";
    wait until Reset = '1';
    wait for 2 us;                      -- la FIFO sale de su reset sincrono
    check_switches(X"00", "Tras reset");
    check_disp(2, 4, "Tras reset (T_STAT = 0x24)");
    cmd("ST?", "24");

    ---------------------------------------------------------------------------
    report "CASO 2: escritura de interruptores";
    cmd("I41", "OK");
    check_switches(X"10", "Tras I41");
    cmd("I71", "OK");
    check_switches(X"90", "Tras I71");
    cmd("I40", "OK");
    check_switches(X"80", "Tras I40");
    cmd("I81", "ER");                   -- interruptor fuera de rango
    cmd("I42", "ER");                   -- valor distinto de 0/1
    cmd("I4X", "ER");                   -- valor no numerico
    cmd("IX1", "ER");                   -- interruptor no numerico
    check_switches(X"80", "Tras los I con error");

    ---------------------------------------------------------------------------
    report "CASO 3: lectura de interruptores";
    cmd("SI7", "S1");
    cmd("SI4", "S0");
    cmd("SI8", "ER");

    ---------------------------------------------------------------------------
    report "CASO 4: actuadores";
    cmd("A35", "OK");
    cmd("SA3", "A5");
    cmd("A90", "OK");
    cmd("SA9", "A0");
    cmd("A3X", "ER");                   -- valor no numerico
    cmd("AX5", "ER");                   -- actuador no numerico
    cmd("SA3", "A5");                   -- los ER no lo han tocado
    cmd("SAX", "ER");

    ---------------------------------------------------------------------------
    report "CASO 5: termostato";
    cmd("T19", "OK");
    check_disp(1, 9, "Tras T19");
    cmd("ST?", "19");
    cmd("T29", "OK");
    check_disp(2, 9, "Tras T29");
    cmd("T31", "ER");                   -- decenas > 2
    cmd("T2X", "ER");                   -- unidades no numericas
    check_disp(2, 9, "Tras los T con error");
    cmd("ST0", "29");
    cmd("T00", "OK");
    check_disp(0, 0, "Tras T00");

    ---------------------------------------------------------------------------
    report "CASO 6: comandos invalidos";
    cmd("X12", "ER");
    cmd("SX1", "ER");
    cmd("i41", "ER");                   -- minuscula

    ---------------------------------------------------------------------------
    report "CASO 7: comprobaciones finales";
    check_switches(X"80", "Al final (A y T no deben tocar los switches)");
    wait for 2 * 11 * BIT_PERIOD;       -- no debe salir ningun byte de mas
    check(tx_cnt = n_resp, "Bytes por RS232_TX: " & integer'image(tx_cnt) &
                           ", esperados " & integer'image(n_resp));

    ---------------------------------------------------------------------------
    report "FIN: " & integer'image(n_cmd) & " comandos; errores estimulo=" &
           integer'image(errs) & " tramas_TX=" & integer'image(err_tx) &
           " bus=" & integer'image(err_bus) &
           " watchdog=" & integer'image(err_wdog);
    if errs + err_tx + err_bus + err_wdog = 0 then
      report "*** TEST PICtop SUPERADO ***";
    else
      report "*** TEST PICtop CON ERRORES ***" severity error;
    end if;
    sim_done <= '1';
    wait;
  end process;

end TestBench;
