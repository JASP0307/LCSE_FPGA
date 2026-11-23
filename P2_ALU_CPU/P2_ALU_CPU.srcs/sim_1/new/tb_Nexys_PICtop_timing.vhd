-------------------------------------------------------------------------------
-- tb_Nexys_PICtop_timing.vhd
-- Testbench del top de placa nexys_PICtop: clk_wiz (modelo de la IP) + PICtop
-- completo, visto solo desde los pines de la Nexys A7.
--
-- Sirve para la simulacion behavioral y, sin cambios, para la post-sintesis y
-- la post-implementacion (con retardos): no usa nombres externos, solo puertos.
--
-- El TB hace de PC por el USB-UART (8E1, un bit de 173 ciclos de 20 MHz, como
-- P1): escribe en UART_TXD_IN y decodifica UART_RXD_OUT.
--
-- Casos:
--   1. SW(15) = '0': PIC en reset (LED15 apagado, LEDs 7..0 a 0, linea TX en
--      reposo '1')
--   2. SW(15) = '1': el clk_wiz engancha (locked) y el PIC sale de reset
--      (LED15 se enciende) en menos de T_LOCK
--   3. Displays tras reset: digito 0 (AN0) = '4', digito 1 (AN1) = '2'
--      (T_STAT = 0x24), multiplexados con contador(16)
--   4. I41 -> OK y LED4; SI4 -> S1
--   5. Reset a mitad de funcionamiento: SW(15) = '0' apaga LED15 y borra los
--      switches; al volver a '1' reengancha y SI4 -> S0
--
-- Ejecutar con "run all" (termina con std.env.finish). Compilar con -2008.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_Nexys_PICtop_timing is
end tb_Nexys_PICtop_timing;

architecture TestBench of tb_Nexys_PICtop_timing is

  constant T_CLK100   : time := 10 ns;          -- reloj de la placa
  constant BIT_PERIOD : time := 173 * 50 ns;    -- 8.65 us, igual que P1
  constant T_RESP     : time := 1 ms;           -- timeout de una respuesta
  constant T_LOCK     : time := 200 us;         -- maximo hasta salir de reset
  constant T_MUX      : time := 2**16 * 50 ns;  -- medio periodo de contador(16)

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

  function show (v : std_logic_vector(7 downto 0)) return string is
  begin
    if not Is_X(v) and unsigned(v) >= 16#20# and unsigned(v) < 16#7F# then
      return "'" & character'val(to_integer(unsigned(v))) & "'";
    end if;
    return "0x" & hex(v);
  end show;

  -- Codificacion de 7 segmentos (gfedcba, activo alto) de ep_ram
  function seg (d : natural) return std_logic_vector is
    type seg_table is array (0 to 9) of std_logic_vector(6 downto 0);
    constant SEGS : seg_table := (
      "0111111", "0000110", "1011011", "1001111", "1100110",
      "1101101", "1111101", "0000111", "1111111", "1101111");
  begin
    return SEGS(d);
  end seg;

  -- Pines de la placa
  signal CLK100MHZ    : std_logic := '0';
  signal SW           : std_logic_vector(15 downto 0) := (others => '0');
  signal LED          : std_logic_vector(15 downto 0);
  signal CA, CB, CC, CD, CE, CF, CG, DP : std_logic;
  signal AN           : std_logic_vector(7 downto 0);
  signal UART_TXD_IN  : std_logic := '1';     -- PC -> FPGA
  signal UART_RXD_OUT : std_logic;            -- FPGA -> PC

  signal sim_done : std_logic := '0';
  signal mon_on   : std_logic := '0';         -- monitor TX activo

  signal tx_log : byte_array(0 to 31) := (others => (others => '0'));
  signal tx_cnt : natural := 0;
  signal err_tx : natural := 0;

begin  -- TestBench

  UUT: entity work.nexys_PICtop
    port map (
      UART_TXD_IN  => UART_TXD_IN,
      UART_RXD_OUT => UART_RXD_OUT,
      CA => CA, CB => CB, CC => CC, CD => CD,
      CE => CE, CF => CF, CG => CG, DP => DP,
      AN        => AN,
      SW        => SW,
      LED       => LED,
      CLK100MHZ => CLK100MHZ);

-----------------------------------------------------------------------------
-- Reloj de la placa, 100 MHz
-----------------------------------------------------------------------------

  p_clk : process
  begin
    while sim_done = '0' loop
      CLK100MHZ <= '1';
      wait for T_CLK100/2;
      CLK100MHZ <= '0';
      wait for T_CLK100/2;
    end loop;
    wait;
  end process;

-----------------------------------------------------------------------------
-- Monitor de UART_RXD_OUT: decodifica tramas 8E1 y las guarda en tx_log
-----------------------------------------------------------------------------

  p_tx_monitor : process
    variable d    : std_logic_vector(7 downto 0);
    variable p    : std_logic;
    variable idx  : natural := 0;
    variable errs : natural := 0;
  begin
    wait until mon_on = '1';
    loop
      wait until UART_RXD_OUT = '0';
      wait for BIT_PERIOD/2;
      if UART_RXD_OUT /= '0' then
        report "TX: bit de start falso" severity error;
        errs := errs + 1;
      else
        p := '0';
        for i in 0 to 7 loop
          wait for BIT_PERIOD;
          d(i) := UART_RXD_OUT;
          p    := p xor UART_RXD_OUT;
        end loop;
        wait for BIT_PERIOD;
        if UART_RXD_OUT /= p then
          report "TX: paridad incorrecta en " & hex(d) severity error;
          errs := errs + 1;
        end if;
        wait for BIT_PERIOD;
        if UART_RXD_OUT /= '1' then
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

-------------------------------------------------------------------------------
-- Secuencia de pruebas
-------------------------------------------------------------------------------

  p_stimulus : process
    variable errs  : natural := 0;
    variable t0    : time;

    procedure check (cond : boolean; msg : string) is
    begin
      if not cond then
        report msg severity error;
        errs := errs + 1;
      end if;
    end check;

    procedure SendByte (constant D : in std_logic_vector(7 downto 0)) is
      variable P : std_logic := '0';
    begin
      for i in 0 to 7 loop
        P := P xor D(i);
      end loop;
      UART_TXD_IN <= '0';
      wait for BIT_PERIOD;
      for i in 0 to 7 loop
        UART_TXD_IN <= D(i);
        wait for BIT_PERIOD;
      end loop;
      UART_TXD_IN <= P;
      wait for BIT_PERIOD;
      UART_TXD_IN <= '1';
      wait for BIT_PERIOD;
    end SendByte;

    procedure cmd (c : string(1 to 3); r : string(1 to 2)) is
      variable n0 : natural;
    begin
      n0 := tx_cnt;
      for i in 1 to 3 loop
        SendByte(to_slv(c(i)));
      end loop;
      if tx_cnt < n0 + 2 then
        wait until tx_cnt >= n0 + 2 for T_RESP;
      end if;
      if tx_cnt < n0 + 2 then
        check(false, "Comando " & c & ": timeout, solo " &
                     integer'image(tx_cnt - n0) & " de 2 bytes de respuesta");
      elsif tx_log(n0) /= to_slv(r(1)) or tx_log(n0 + 1) /= to_slv(r(2)) then
        check(false, "Comando " & c & ": respuesta " & show(tx_log(n0)) &
                     show(tx_log(n0 + 1)) & ", esperada " & r);
      else
        report "  " & c & " -> " & r;
      end if;
      wait for 3 * BIT_PERIOD;
    end cmd;

    -- Espera a que el PIC salga de reset (LED15) tras subir SW(15)
    procedure wait_run (when_s : string) is
    begin
      t0 := now;
      SW(15) <= '1';
      wait until LED(15) = '1' for T_LOCK;
      if LED(15) /= '1' then
        check(false, when_s & ": el PIC no sale de reset en " &
                     time'image(T_LOCK) & " (locked no sube?)");
      else
        report when_s & ": PIC fuera de reset " &
               time'image(now - t0) & " despues de subir SW(15)";
      end if;
    end wait_run;

    -- Segmentos que se ven ahora (gfedcba, activo alto) frente a un digito
    procedure check_digit (an_exp : std_logic_vector(7 downto 0);
                           d : natural; when_s : string) is
      variable segs : std_logic_vector(6 downto 0);
    begin
      segs := not (CG & CF & CE & CD & CC & CB & CA);
      check(AN = an_exp, when_s & ": AN = " & hex(AN) &
                         ", esperado " & hex(an_exp));
      check(segs = seg(d), when_s & ": el digito no es " &
                           integer'image(d));
    end check_digit;

  begin
    ---------------------------------------------------------------------------
    report "Caso 1: SW(15) = 0, PIC en reset";
    wait for 2 us;
    check(LED(15) = '0', "Caso 1: LED15 encendido con SW(15) = 0");
    check(LED(7 downto 0) = x"00", "Caso 1: LEDs 7..0 = " &
                                   hex(LED(7 downto 0)) & " en reset");
    check(UART_RXD_OUT = '1', "Caso 1: linea TX no esta en reposo en reset");

    ---------------------------------------------------------------------------
    report "Caso 2: SW(15) = 1, arranque";
    wait_run("Caso 2");
    mon_on <= '1';
    check(UART_RXD_OUT = '1', "Caso 2: linea TX no esta en reposo al arrancar");

    ---------------------------------------------------------------------------
    report "Caso 3: displays tras reset (T_STAT = 0x24)";
    wait for 1 us;
    check_digit("11111110", 4, "Caso 3, digito 0");

    ---------------------------------------------------------------------------
    report "Caso 4: comandos por el USB-UART";
    cmd("I41", "OK");
    check(LED(7 downto 0) = x"10", "Caso 4: LEDs 7..0 = " &
                                   hex(LED(7 downto 0)) & ", esperado 10");
    cmd("SI4", "S1");

    -- El digito 1 se enciende cuando contador(16) pasa a '1'
    if AN /= "11111101" then
      wait until AN = "11111101" for 2 * T_MUX;
    end if;
    wait for 1 us;
    check_digit("11111101", 2, "Caso 3, digito 1");

    ---------------------------------------------------------------------------
    report "Caso 5: reset a mitad de funcionamiento";
    SW(15) <= '0';
    wait for 1 us;
    check(LED(15) = '0', "Caso 5: LED15 sigue encendido con SW(15) = 0");
    check(LED(7 downto 0) = x"00", "Caso 5: el reset no borra los switches");
    wait for 10 us;
    wait_run("Caso 5");
    cmd("SI4", "S0");

    ---------------------------------------------------------------------------
    report "===== Resumen =====";
    report "Errores de estimulo/comprobacion: " & integer'image(errs);
    report "Errores de tramas TX:              " & integer'image(err_tx);
    report "Bytes recibidos por UART_RXD_OUT:  " & integer'image(tx_cnt) &
           " (esperados 6)";
    if errs = 0 and err_tx = 0 and tx_cnt = 6 then
      report "SIMULACION CORRECTA" severity note;
    else
      report "SIMULACION CON ERRORES" severity error;
    end if;
    sim_done <= '1';
    wait for 100 ns;
    std.env.finish;
  end process;

end TestBench;
