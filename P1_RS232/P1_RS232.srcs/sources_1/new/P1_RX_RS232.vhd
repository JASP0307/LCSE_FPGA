----------------------------------------------------------------------------------
-- Create Date: Sep. 2025
-- Module Name: RxRS232 - Behavioral
-- Description: Receptor RS232. 20 MHz / 173 = 115200 baudios aprox.
--              8 bits de datos + paridad par + 1 bit de stop.
-----------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity RxRS232 is
    Port ( Reset        : in  STD_LOGIC;
           Clk          : in  STD_LOGIC;
           LineRdIn     : in  STD_LOGIC;
           ValidOut     : out STD_LOGIC;
           CodeOut      : out STD_LOGIC;
           StoreOut     : out STD_LOGIC
           );
end RxRS232;

architecture Behavioral of RxRS232 is

    constant PulseEndOfCount : integer := 173;

    type State is (Idle, StartBit, RcvData, ParityBit, StopBit);
    signal PresentState, NextState : State;
    signal DataCount    : integer range 0 to 7;
    signal PulseCounter : integer range 0 to PulseEndOfCount-1;
    signal BaudTick     : std_logic := '0';
    signal ParityAcc    : std_logic;
    signal ParityOK     : std_logic;

begin


FFs : process(Clk, Reset)
begin
    if Reset = '0' then
        PresentState <= Idle;
    elsif rising_edge(Clk) then
        PresentState <= NextState;
    end if;
end process;

Pulse: process(Clk, Reset)
begin
    if Reset = '0' then
        PulseCounter <= 0;
    elsif rising_edge(Clk) then
        if PresentState = Idle then
            PulseCounter <= 0;
        elsif BaudTick = '1' then
            PulseCounter <= 0;
        else
            PulseCounter <= PulseCounter + 1;
        end if;
    end if;
end process;

Tick: process(PulseCounter, PresentState)
begin
    case PresentState is
        when StartBit =>
            if (PulseCounter = (PulseEndOfCount/2)-1) then
                BaudTick <= '1';
            else
                BaudTick <= '0';
            end if;
        when others =>
            if (PulseCounter = PulseEndOfCount-1) then
                BaudTick <= '1';
            else
                BaudTick <= '0';
            end if;
    end case;
end process;

DataCounter : process(Clk, Reset)
begin
    if Reset = '0' then
        DataCount <= 0;
    elsif rising_edge(Clk) then
        if PresentState /= RcvData then
            DataCount <= 0;
        elsif BaudTick = '1' and DataCount < 7 then
            DataCount <= DataCount + 1;
        end if;
    end if;
end process;

ParityAccum : process(Clk, Reset)
begin
    if Reset = '0' then
        ParityAcc <= '0';
    elsif rising_edge(Clk) then
        if PresentState = Idle then
            ParityAcc <= '0';
        elsif PresentState = RcvData and BaudTick = '1' then
            ParityAcc <= ParityAcc xor LineRdIn;
        end if;
    end if;
end process;

ParityCheck : process(Clk, Reset)
begin
    if Reset = '0' then
        ParityOK <= '0';
    elsif rising_edge(Clk) then
        if PresentState = Idle then
            ParityOK <= '0';
        elsif PresentState = ParityBit and BaudTick = '1' then
            if LineRdIn = ParityAcc then
                ParityOK <= '1';
            else
                ParityOK <= '0';
            end if;
        end if;
    end if;
end process;

FSM : process(PresentState, BaudTick, DataCount, LineRdIn)
begin
    NextState <= PresentState;

    case PresentState is
        when Idle =>
            if LineRdIn = '0' then
                NextState <= StartBit;
            end if;

        when StartBit =>
            if BaudTick = '1' then
                if LineRdIn = '0' then
                    NextState <= RcvData;
                else
                    NextState <= Idle;
                end if;
            end if;

        when RcvData =>
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


Output : process(PresentState, BaudTick, LineRdIn, ParityOK)
begin
    case PresentState is
        when Idle =>
            ValidOut <= '0';
            StoreOut <= '0';
            CodeOut  <= '0';
            -- CurrentState <= "00";

        when StartBit =>
            ValidOut <= '0';
            StoreOut <= '0';
            CodeOut  <= '0';
            -- CurrentState <= "01";

        when RcvData =>
            ValidOut <= BaudTick;
            StoreOut <= '0';
            CodeOut  <= LineRdIn;
            -- CurrentState <= "10";

        when ParityBit =>
            ValidOut <= '0';
            StoreOut <= '0';
            CodeOut  <= '0';

        when StopBit =>
            ValidOut <= '0';
            if LineRdIn = '1' and BaudTick = '1' and ParityOK = '1' then
                StoreOut <= '1';
            else
                StoreOut <= '0';
            end if;
            CodeOut  <= '0';
            -- CurrentState <= "11";
    end case;
end process;

end Behavioral;