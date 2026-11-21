-------------------------------------------------------------------------------
-- tb_ALU.vhd
-- Banco de pruebas autocomprobado de la ALU, aislada del resto del PIC
-- (enunciado 2b, apartado 8.7).
--
-- Temporizacion: todos los estimulos cambian en el flanco de BAJADA y la ALU
-- los captura en el flanco de SUBIDA siguiente. Asi, tras cada operacion
-- (procedimiento exec) los registros y flags ya estan actualizados y se
-- pueden comprobar sin carreras.
--
-- La TB solo ve la ALU por sus puertos: ACC se lee con op_oeacc por el
-- Databus; A y B se comprueban indirectamente a traves de las operaciones.
--
-- Uso: top de simulacion tb_ALU, "run all". Mensaje final:
--   *** TEST ALU SUPERADO ***   o   *** TEST ALU CON ERRORES ***
-------------------------------------------------------------------------------
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

use work.PIC_pkg.all;

entity tb_ALU is
end tb_ALU;

architecture TestBench of tb_ALU is

  component ALU
    port ( Reset     : in    std_logic;
           Clk       : in    std_logic;
           Alu_op    : in    alu_op;
           Databus   : inout std_logic_vector(7 downto 0);
           Index_Reg : out   std_logic_vector(7 downto 0);
           FlagZ     : out   std_logic;
           FlagC     : out   std_logic;
           FlagN     : out   std_logic;
           FlagE     : out   std_logic);
  end component;

  constant T_CLK : time := 50 ns;                          -- 20 MHz
  constant BUS_Z : std_logic_vector(7 downto 0) := (others => 'Z');

  signal Reset     : std_logic := '0';
  signal Clk       : std_logic := '0';
  signal Alu_op_s  : alu_op    := nop;
  signal Databus   : std_logic_vector(7 downto 0);
  signal tb_drive  : std_logic_vector(7 downto 0) := BUS_Z; -- lo que pone la TB en el bus
  signal Index_Reg : std_logic_vector(7 downto 0);
  signal FlagZ, FlagC, FlagN, FlagE : std_logic;

  signal sim_end   : boolean := false;
  signal mon_errs  : natural := 0;                         -- errores del monitor de bus

  -- Byte en hexadecimal para los mensajes
  function hex (v : std_logic_vector(7 downto 0)) return string is
    constant H : string(1 to 16) := "0123456789ABCDEF";
    variable s : string(1 to 2);
  begin
    if Is_X(v) then
      return "??";
    end if;
    s(1) := H(to_integer(unsigned(v(7 downto 4))) + 1);
    s(2) := H(to_integer(unsigned(v(3 downto 0))) + 1);
    return s;
  end function;

  -- Un std_logic como caracter ('0', '1', '-', 'X'...)
  function chr (b : std_logic) return character is
    constant img : string := std_logic'image(b);           -- p. ej. "'1'"
  begin
    return img(2);
  end function;

begin

  UUT : ALU
    port map (
      Reset     => Reset,
      Clk       => Clk,
      Alu_op    => Alu_op_s,
      Databus   => Databus,
      Index_Reg => Index_Reg,
      FlagZ     => FlagZ,
      FlagC     => FlagC,
      FlagN     => FlagN,
      FlagE     => FlagE);

  -- La TB es un conductor mas del bus triestado (como la CPU o la RAM)
  Databus <= tb_drive;

  -----------------------------------------------------------------------------
  -- Reloj, se para al acabar para que "run all" termine solo
  -----------------------------------------------------------------------------
  p_clk : process
  begin
    while not sim_end loop
      Clk <= '0';
      wait for T_CLK/2;
      Clk <= '1';
      wait for T_CLK/2;
    end loop;
    wait;
  end process;

  -----------------------------------------------------------------------------
  -- Monitor del bus, en cada flanco de subida:
  --  * fuera de op_oeacc la ALU no puede conducir el Databus;
  --  * en op_oeacc el bus no puede tener 'X' (contencion);
  --  * mientras la TB carga un valor, en el bus debe verse ese valor.
  -----------------------------------------------------------------------------
  p_bus_monitor : process (Clk)
    variable errs : natural := 0;
  begin
    if rising_edge(Clk) and Reset = '1' then
      if Alu_op_s /= op_oeacc and tb_drive = BUS_Z and Databus /= BUS_Z then
        report "BUS: la ALU conduce el Databus durante " &
               alu_op'image(Alu_op_s) & " (" & hex(Databus) & ")" severity error;
        errs := errs + 1;
      end if;
      if Alu_op_s = op_oeacc and Is_X(Databus) then
        report "BUS: contencion durante op_oeacc" severity error;
        errs := errs + 1;
      end if;
      if tb_drive /= BUS_Z and Databus /= tb_drive then
        report "BUS: contencion mientras la TB carga " & hex(tb_drive) &
               " con " & alu_op'image(Alu_op_s) severity error;
        errs := errs + 1;
      end if;
      mon_errs <= errs;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Estimulos y comprobaciones
  -----------------------------------------------------------------------------
  p_stimulus : process
    variable errs : natural := 0;

    procedure check (cond : boolean; msg : string) is
    begin
      if not cond then
        report msg severity error;
        errs := errs + 1;
      end if;
    end procedure;

    -- Ejecuta una microinstruccion durante un ciclo (opcionalmente con un
    -- dato de la TB en el bus) y vuelve a nop. Se llama y retorna en un
    -- flanco de bajada: al volver, el flanco de subida ya ha actualizado
    -- los registros.
    procedure exec (op   : alu_op;
                    data : std_logic_vector(7 downto 0) := BUS_Z) is
    begin
      Alu_op_s <= op;
      tb_drive <= data;
      wait until falling_edge(Clk);
      Alu_op_s <= nop;
      tb_drive <= BUS_Z;
    end procedure;

    procedure load_ab (a, b : std_logic_vector(7 downto 0)) is
    begin
      exec(op_lda, a);
      exec(op_ldb, b);
    end procedure;

    -- Lee ACC por el bus con op_oeacc (un ciclo, no debe cambiar nada)
    procedure expect_acc (v : std_logic_vector(7 downto 0); msg : string) is
    begin
      Alu_op_s <= op_oeacc;
      wait for T_CLK/4;
      check(Databus = v, msg & ": ACC=" & hex(Databus) & ", esperado " & hex(v));
      wait until falling_edge(Clk);
      Alu_op_s <= nop;
    end procedure;

    -- Flags esperados; '-' = no importa
    procedure expect_flags (z, c, n, e : std_logic; msg : string) is
    begin
      check(std_match(FlagZ, z) and std_match(FlagC, c) and
            std_match(FlagN, n) and std_match(FlagE, e),
            msg & ": ZCNE=" & chr(FlagZ) & chr(FlagC) & chr(FlagN) & chr(FlagE) &
            ", esperado " & chr(z) & chr(c) & chr(n) & chr(e));
    end procedure;

    procedure expect_index (v : std_logic_vector(7 downto 0); msg : string) is
    begin
      check(Index_Reg = v, msg & ": Index_Reg=" & hex(Index_Reg) &
                           ", esperado " & hex(v));
    end procedure;

    -- Operacion de dos operandos: carga A y B, ejecuta y comprueba
    procedure test_ab (op      : alu_op;
                       a, b    : std_logic_vector(7 downto 0);
                       res     : std_logic_vector(7 downto 0);
                       z, c, n : std_logic;
                       msg     : string) is
    begin
      load_ab(a, b);
      exec(op);
      expect_flags(z, c, n, '-', msg);
      expect_acc(res, msg);
    end procedure;

    -- Conversion: carga A, ejecuta y comprueba ACC y E
    procedure test_conv (op  : alu_op;
                         a   : std_logic_vector(7 downto 0);
                         res : std_logic_vector(7 downto 0);
                         e   : std_logic;
                         msg : string) is
    begin
      exec(op_lda, a);
      exec(op);
      expect_flags('-', '-', '-', e, msg);
      expect_acc(res, msg);
    end procedure;

    -- Comparacion: solo Z, y ACC no debe cambiar
    procedure test_cmp (op   : alu_op;
                        a, b : std_logic_vector(7 downto 0);
                        z    : std_logic;
                        msg  : string) is
    begin
      load_ab(a, b);
      exec(op);
      expect_flags(z, '-', '-', '-', msg);
    end procedure;

  begin
    ---------------------------------------------------------------------------
    report "CASO 0: reset asincrono";
    ---------------------------------------------------------------------------
    Reset <= '0';
    wait for 3*T_CLK + T_CLK/4;
    expect_index(X"00", "Reset");
    expect_flags('0', '0', '0', '0', "Reset");
    wait until falling_edge(Clk);
    Reset <= '1';
    wait until falling_edge(Clk);
    expect_acc(X"00", "Reset");
    wait for 1 ns;
    check(Databus = BUS_Z, "Tras reset el bus no esta en alta impedancia: " &
                           hex(Databus));
    wait until falling_edge(Clk);

    ---------------------------------------------------------------------------
    report "CASO 1: cargas y movimientos entre registros";
    ---------------------------------------------------------------------------
    exec(op_ldacc, X"5A");
    expect_acc(X"5A", "LD .ACC, 5A");
    exec(op_ldid, X"07");
    expect_index(X"07", "LD .INDEX, 07");
    exec(op_mvacc2id);
    expect_index(X"5A", "LD .INDEX, .ACC");
    -- A y B se comprueban sumandolos
    exec(op_ldacc, X"03");
    exec(op_mvacc2a);
    exec(op_ldacc, X"04");
    exec(op_mvacc2b);
    exec(op_add);
    expect_acc(X"07", "LD .A,.ACC / LD .B,.ACC y ADD");
    expect_flags('-', '-', '-', '0', "Las cargas no tocan E");

    ---------------------------------------------------------------------------
    report "CASO 2: ADD (Z, C, N)";
    ---------------------------------------------------------------------------
    test_ab(op_add, X"12", X"34", X"46", '0', '0', '0', "ADD 12+34");
    test_ab(op_add, X"0F", X"01", X"10", '0', '0', '1', "ADD 0F+01 (N)");
    test_ab(op_add, X"08", X"08", X"10", '0', '0', '1', "ADD 08+08 (N)");
    test_ab(op_add, X"07", X"08", X"0F", '0', '0', '0', "ADD 07+08");
    test_ab(op_add, X"F0", X"10", X"00", '1', '1', '0', "ADD F0+10 (Z, C)");
    test_ab(op_add, X"FF", X"01", X"00", '1', '1', '1', "ADD FF+01 (Z, C, N)");
    test_ab(op_add, X"10", X"00", X"10", '0', '0', '0', "ADD 10+00 (bit 4 de A)");
    test_ab(op_add, X"00", X"10", X"10", '0', '0', '0', "ADD 00+10 (bit 4 de B)");
    test_ab(op_add, X"0F", X"11", X"20", '0', '0', '1', "ADD 0F+11 (N)");
    test_ab(op_add, X"80", X"80", X"00", '1', '1', '0', "ADD 80+80 (C)");

    ---------------------------------------------------------------------------
    report "CASO 3: SUB (Z, C = prestamo, N = prestamo de nibble)";
    ---------------------------------------------------------------------------
    test_ab(op_sub, X"35", X"12", X"23", '0', '0', '0', "SUB 35-12");
    test_ab(op_sub, X"10", X"01", X"0F", '0', '0', '1', "SUB 10-01 (N)");
    test_ab(op_sub, X"03", X"05", X"FE", '0', '1', '1', "SUB 03-05 (C, N)");
    test_ab(op_sub, X"42", X"42", X"00", '1', '0', '0', "SUB 42-42 (Z)");
    test_ab(op_sub, X"00", X"01", X"FF", '0', '1', '1', "SUB 00-01 (C, N)");
    test_ab(op_sub, X"50", X"40", X"10", '0', '0', '0', "SUB 50-40");

    ---------------------------------------------------------------------------
    report "CASO 4: SHIFTL / SHIFTR (no tocan flags)";
    ---------------------------------------------------------------------------
    test_ab(op_add, X"FF", X"01", X"00", '1', '1', '1', "Flags a 1 antes de desplazar");
    exec(op_ldacc, X"81");
    expect_flags('1', '1', '1', '-', "LD .ACC no toca Z, C, N");
    exec(op_shiftl);
    expect_acc(X"02", "SHIFTL 81 (entra un 0, se pierde el bit 7)");
    expect_flags('1', '1', '1', '-', "SHIFTL no toca flags");
    exec(op_shiftr);
    expect_acc(X"01", "SHIFTR 02");
    exec(op_ldacc, X"81");
    exec(op_shiftr);
    expect_acc(X"40", "SHIFTR 81 (entra un 0, se pierde el bit 0)");
    expect_flags('1', '1', '1', '-', "SHIFTR no toca flags");
    -- Cuatro desplazamientos como en #TEMP / #TSND
    exec(op_ldacc, X"02");
    exec(op_shiftl); exec(op_shiftl); exec(op_shiftl); exec(op_shiftl);
    expect_acc(X"20", "4 x SHIFTL de 02");
    exec(op_shiftr); exec(op_shiftr); exec(op_shiftr); exec(op_shiftr);
    expect_acc(X"02", "4 x SHIFTR de 20");

    ---------------------------------------------------------------------------
    report "CASO 5: AND / OR / XOR (solo Z)";
    ---------------------------------------------------------------------------
    test_ab(op_add, X"FF", X"01", X"00", '1', '1', '1', "Flags a 1 antes de las logicas");
    test_ab(op_and, X"F0", X"0F", X"00", '1', '1', '1', "AND F0,0F (Z; C y N intactos)");
    test_ab(op_and, X"3C", X"0F", X"0C", '0', '1', '1', "AND 3C,0F");
    test_ab(op_or,  X"00", X"00", X"00", '1', '1', '1', "OR 00,00 (Z)");
    test_ab(op_or,  X"A0", X"05", X"A5", '0', '1', '1', "OR A0,05");
    test_ab(op_xor, X"55", X"55", X"00", '1', '1', '1', "XOR 55,55 (Z)");
    test_ab(op_xor, X"55", X"AA", X"FF", '0', '1', '1', "XOR 55,AA");
    -- Mascaras de #TSND
    test_ab(op_and, X"23", "11110000", X"20", '0', '-', '-', "AND 23,F0 (#TSND)");
    test_ab(op_and, X"23", "00001111", X"03", '0', '-', '-', "AND 23,0F (#TSND)");

    ---------------------------------------------------------------------------
    report "CASO 6: CMPE / CMPL / CMPG (solo Z, ACC intacto)";
    ---------------------------------------------------------------------------
    exec(op_ldacc, X"77");
    test_cmp(op_cmpe, X"05", X"05", '1', "CMPE 05=05");
    test_cmp(op_cmpe, X"05", X"06", '0', "CMPE 05=06");
    test_cmp(op_cmpl, X"05", X"06", '1', "CMPL 05<06");
    test_cmp(op_cmpl, X"06", X"05", '0', "CMPL 06<05");
    test_cmp(op_cmpl, X"05", X"05", '0', "CMPL 05<05");
    test_cmp(op_cmpg, X"06", X"05", '1', "CMPG 06>05");
    test_cmp(op_cmpg, X"05", X"06", '0', "CMPG 05>06");
    test_cmp(op_cmpg, X"05", X"05", '0', "CMPG 05>05");
    test_cmp(op_cmpg, X"80", X"7F", '1', "CMPG 80>7F (sin signo)");
    test_cmp(op_cmpl, X"FE", X"FF", '1', "CMPL FE<FF (bucle #INIT)");
    test_cmp(op_cmpl, X"FF", X"FF", '0', "CMPL FF<FF (sale de #INIT)");
    expect_acc(X"77", "Las comparaciones no tocan ACC");

    ---------------------------------------------------------------------------
    report "CASO 7: los flags se conservan en cargas, movimientos y nop";
    ---------------------------------------------------------------------------
    test_cmp(op_cmpe, X"05", X"05", '1', "CMPE verdadero");
    exec(op_lda, X"00");
    exec(op_ldb, X"00");
    exec(op_ldacc, X"00");
    exec(op_ldid, X"00");
    exec(op_mvacc2a);
    exec(op_mvacc2b);
    exec(op_mvacc2id);
    exec(nop);
    expect_acc(X"00", "oeacc");
    expect_flags('1', '-', '-', '-', "Z=1 se conserva tras cargas/movimientos/nop/oeacc");
    test_cmp(op_cmpe, X"05", X"06", '0', "CMPE falso");
    exec(op_lda, X"FF");
    exec(op_ldb, X"FF");
    expect_flags('0', '-', '-', '-', "Z=0 se conserva tras cargas");

    ---------------------------------------------------------------------------
    report "CASO 8: ASCII2BIN (solo '0'..'9'; si no, FF y E=1)";
    ---------------------------------------------------------------------------
    test_conv(op_ascii2bin, X"30", X"00", '0', "ASCII2BIN '0'");
    test_conv(op_ascii2bin, X"35", X"05", '0', "ASCII2BIN '5'");
    test_conv(op_ascii2bin, X"39", X"09", '0', "ASCII2BIN '9'");
    test_conv(op_ascii2bin, X"2F", X"FF", '1', "ASCII2BIN '/' (0x2F)");
    test_conv(op_ascii2bin, X"3A", X"FF", '1', "ASCII2BIN ':' (0x3A)");
    test_conv(op_ascii2bin, X"49", X"FF", '1', "ASCII2BIN 'I' (nibble bajo 9)");
    test_conv(op_ascii2bin, X"00", X"FF", '1', "ASCII2BIN 0x00");
    test_conv(op_ascii2bin, X"34", X"04", '0', "ASCII2BIN '4' limpia E");

    ---------------------------------------------------------------------------
    report "CASO 9: BIN2ASCII (solo 0..9; si no, FF y E=1)";
    ---------------------------------------------------------------------------
    test_conv(op_bin2ascii, X"00", X"30", '0', "BIN2ASCII 0");
    test_conv(op_bin2ascii, X"07", X"37", '0', "BIN2ASCII 7");
    test_conv(op_bin2ascii, X"09", X"39", '0', "BIN2ASCII 9");
    test_conv(op_bin2ascii, X"0A", X"FF", '1', "BIN2ASCII 0A");
    test_conv(op_bin2ascii, X"10", X"FF", '1', "BIN2ASCII 10");
    test_conv(op_bin2ascii, X"FF", X"FF", '1', "BIN2ASCII FF");
    test_conv(op_bin2ascii, X"01", X"31", '0', "BIN2ASCII 1 limpia E");

    ---------------------------------------------------------------------------
    report "CASO 10: secuencias reales del programa (ROM)";
    ---------------------------------------------------------------------------
    -- #SWITCH con "I41": el valor convertido debe sobrevivir a CMPG para WRI
    exec(op_lda, X"31");                 -- LD .A, [RCBUF2] = '1'
    exec(op_ascii2bin);
    exec(op_mvacc2a);                    -- LD .A, .ACC
    exec(op_ldb, X"01");                 -- LD .B, X01
    exec(op_cmpg);                       -- CMPG
    expect_flags('0', '-', '-', '0', "#SWITCH: 1 > 1 es falso");
    expect_acc(X"01", "#SWITCH: ACC conserva el valor para WRI");
    -- #TEMP con "T23": T_STAT = 0x23
    exec(op_lda, X"32");                 -- LD .A, [RCBUF1] = '2'
    exec(op_ascii2bin);
    exec(op_mvacc2a);
    exec(op_ldb, X"02");
    exec(op_cmpg);
    expect_flags('0', '-', '-', '-', "#TEMP: 2 > 2 es falso");
    exec(op_ldb, X"00");
    exec(op_add);
    exec(op_shiftl); exec(op_shiftl); exec(op_shiftl); exec(op_shiftl);
    expect_acc(X"20", "#TEMP: decenas en el nibble alto");
    exec(op_lda, X"33");                 -- LD .A, [RCBUF2] = '3'
    exec(op_ascii2bin);
    exec(op_mvacc2a);
    exec(op_ldb, X"FF");
    exec(op_cmpe);
    expect_flags('0', '-', '-', '0', "#TEMP: '3' no es error");
    exec(op_ldb, X"20");                 -- LD .B, [TMP]
    exec(op_add);
    expect_acc(X"23", "#TEMP: T_STAT");

    ---------------------------------------------------------------------------
    report "CASO 11: reset asincrono a mitad de ciclo";
    ---------------------------------------------------------------------------
    exec(op_ldacc, X"AA");
    exec(op_ldid, X"BB");
    test_ab(op_add, X"FF", X"01", X"00", '1', '1', '1', "Flags a 1 antes del reset");
    test_conv(op_ascii2bin, X"41", X"FF", '1', "E a 1 antes del reset");
    wait for T_CLK/4;                    -- lejos de cualquier flanco
    Reset <= '0';
    wait for 1 ns;
    expect_index(X"00", "Reset asincrono");
    expect_flags('0', '0', '0', '0', "Reset asincrono");
    wait until falling_edge(Clk);
    Reset <= '1';
    wait until falling_edge(Clk);
    expect_acc(X"00", "Reset asincrono");
    test_ab(op_add, X"01", X"02", X"03", '0', '0', '0', "A y B a 0 tras reset y recargados");

    ---------------------------------------------------------------------------
    -- Fin
    ---------------------------------------------------------------------------
    wait until falling_edge(Clk);
    sim_end <= true;
    wait for T_CLK;
    report "FIN: errores comprobacion=" & integer'image(errs) &
           ", errores bus=" & integer'image(mon_errs);
    if errs = 0 and mon_errs = 0 then
      report "*** TEST ALU SUPERADO ***";
    else
      report "*** TEST ALU CON ERRORES ***" severity error;
    end if;
    wait;
  end process;

end TestBench;
