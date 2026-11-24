----------------------------------------------------------------------------------
-- Create Date: Sep. 2025
-- Module Name: TxRS232 - Behavioral
-- Description: Transmisor RS232. 20 MHz / 173 = 115200 baudios aprox.
-----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity TxRS232 is
    Port ( Reset        : in  STD_LOGIC;
           Clk          : in  STD_LOGIC;
           Start        : in  STD_LOGIC;
           DataIn       : in  STD_LOGIC_VECTOR(7 downto 0);
           EOT          : out STD_LOGIC;
           TX           : out STD_LOGIC);
end TxRS232;

architecture Behavioral of TxRS232 is

    constant PulseEndOfCount : integer := 173;

    type State is (Idle, StartBit, SendData, ParityBit, StopBit);
    signal PresentState, NextState : State;

    signal PulseWidth : integer range 0 to PulseEndOfCount-1;
    signal BaudTick   : std_logic;
    signal DataCount  : integer range 0 to 7;
    signal DataReg    : std_logic_vector(7 downto 0); -- dato capturado
    signal Parity_Bit : std_logic;
begin

FFs : process(Clk, Reset)
begin
    if Reset = '0' then
        PresentState <= Idle;
    elsif rising_edge(Clk) then
        PresentState <= NextState;
    end if;
end process;

BaudTick <= '1' when PulseWidth = PulseEndOfCount-1 else '0';

Parity_Bit <= DataReg(0) xor DataReg(1) xor DataReg(2) xor DataReg(3) xor DataReg(4) xor DataReg(5) xor DataReg(6) xor DataReg(7);

Pulse : process(Clk, Reset)
begin
    if Reset = '0' then
        PulseWidth <= 0;
    elsif rising_edge(Clk) then
        if PresentState = Idle then
            PulseWidth <= 0;
        elsif BaudTick = '1' then
            PulseWidth <= 0;
        else
            PulseWidth <= PulseWidth + 1;
        end if;
    end if;
end process;

BitCounter : process(Clk, Reset)
begin
    if Reset = '0' then
        DataCount <= 0;
    elsif rising_edge(Clk) then
        if PresentState /= SendData then
            DataCount <= 0;
        elsif BaudTick = '1' and DataCount < 7 then
            DataCount <= DataCount + 1;
        end if;
    end if;
end process;

Capture : process(Clk, Reset)
begin
    if Reset = '0' then
        DataReg <= (others => '0');
    elsif rising_edge(Clk) then
        if PresentState = Idle and Start = '1' then
            DataReg <= DataIn;
        end if;
    end if;
end process;

FSM : process(PresentState, Start, BaudTick, DataCount)
begin
    NextState <= PresentState;          

    case PresentState is
        when Idle =>
            if Start = '1' then
                NextState <= StartBit;
            end if;

        when StartBit =>
            if BaudTick = '1' then
                NextState <= SendData;
            end if;

        when SendData =>
            if BaudTick = '1' and DataCount = 7 then
                NextState <= ParityBit;
            end if;
        when ParityBit =>
            if BaudTick = '1' then
                NextState <= StopBit;
            end if;
        when StopBit =>
            if BaudTick = '1' then
                NextState <= Idle;
            end if;
    end case;
end process;

EOT <= '1' when NextState = Idle else '0';

Output : process(PresentState, DataCount, DataReg, Parity_Bit)
begin
    case PresentState is
        when Idle =>
            TX           <= '1';
            --EOT          <= '1';

        when StartBit =>
            TX           <= '0';
            --EOT          <= '0';
            
        when SendData =>
            TX           <= DataReg(DataCount);
            --EOT          <= '0';

        when ParityBit =>
            TX           <= Parity_Bit;
            --EOT          <= '0';

        when StopBit =>
            TX           <= '1';
            --EOT          <= '0';

    end case;
end process;

end Behavioral;