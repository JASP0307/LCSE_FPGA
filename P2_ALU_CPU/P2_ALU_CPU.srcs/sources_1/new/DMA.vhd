----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 10/23/2026 02:19:17 AM
-- Design Name: 
-- Module Name: DMA - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.std_logic_1164.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.numeric_std.all;
use work.PIC_pkg.all;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity DMA is
    port ( Reset        : in  std_logic;
           Clk          : in  std_logic;
           RCVD_Data    : in  std_logic_vector(7 downto 0);
           RX_Full      : in  std_logic;
           RX_Empty     : in  std_logic;
           Data_Read    : out std_logic;
           ACK_out      : in  std_logic;
           TX_RDY       : in  std_logic;
           Valid_D      : out std_logic;
           TX_Data      : out std_logic_vector(7 downto 0);
           Address      : out std_logic_vector(7 downto 0);
           Databus      : inout std_logic_vector(7 downto 0);
           Write_en     : out std_logic;
           OE           : out std_logic;
           DMA_RQ       : out std_logic;
           DMA_ACK      : in std_logic;
           Send_comm    : in  std_logic;
           READY        : out std_logic);
end DMA;

architecture Behavioral of DMA is
    type State is (Idle, RxBusReq, RxWrite, RcvDone, TxSend, TxDone);
    signal PresentState, NextState : State;
    signal cnt         : integer range 0 to 3 := 0;
    signal tx_cnt      : integer range 0 to 1 := 0;
begin

FFs : process(Clk, Reset)
begin
    if Reset = '0' then
        PresentState <= Idle;
    elsif rising_edge(Clk) then
        PresentState <= NextState;
    end if;
end process;

Rx_Count: process(Clk, Reset)
begin
    if Reset = '0' then
        cnt  <= 0;
    elsif rising_edge(clk) then
        if PresentState /= RxWrite then
            if cnt = 3 then
                cnt <= 0;
            end if;
        elsif cnt < 3 then 
            cnt <= cnt +1;
        end if;
    end if;
end process;

Tx_Count: process(Clk, Reset)
begin
    if Reset = '0' then
        tx_cnt  <= 0;
    elsif rising_edge(clk) then
        if PresentState /= TxSend then
            if tx_cnt = 1 then
                tx_cnt <= 0;
            end if;
        elsif ACK_out = '0' and tx_cnt < 1 then 
            tx_cnt <= tx_cnt +1;
        end if;
    end if;
end process;

FSM : process(PresentState, RX_Empty, DMA_ACK, cnt, tx_cnt, Send_comm, ACK_out)
begin
    NextState <= PresentState;          

    case PresentState is
        when Idle =>
            if Send_comm = '1' then
                NextState <= TxSend;
            elsif RX_Empty = '0' then
                NextState <= RxBusReq;
            end if;

        when RxBusReq =>
            if DMA_ACK = '1' then
                NextState <= RxWrite;
            end if;

            if Send_comm = '1' then
                NextState <= TxSend;
            end if;

        when RxWrite =>
            if cnt /= 2 then
                NextState <= RcvDone;
            else
                NextState <= RxWrite;
            end if;
            
        when RcvDone =>
            if DMA_ACK = '0' then
                NextState <= Idle;
            end if;

        when TxSend =>
            if ACK_out = '0' and tx_cnt = 1 then
                NextState <= TxDone;
            end if;

        when TxDone =>
            if Send_comm = '0' then
                NextState <= Idle;
            end if;
            
    end case;
end process;

READY <= '1' when (PresentState = Idle and Send_comm = '0') or PresentState = TxDone else '0';

Output : process(PresentState, cnt, RCVD_Data, Databus, TX_RDY, tx_cnt, ACK_out)
begin
    case PresentState is
        when Idle =>
            Data_Read    <= '0';
            Valid_D      <= '1';
            TX_Data      <= (others => '0');
            Address      <= (others => '0');
            Databus      <= (others => 'Z');
            Write_en     <= '0';
            OE           <= '1';
            DMA_RQ       <= '0';
           
        when RxBusReq =>
            Data_Read    <= '0';
            Valid_D      <= '1';
            TX_Data      <= (others => '0');
            Address      <= (others => '0');
            Databus      <= (others => 'Z');
            Write_en     <= '0';
            OE           <= '1';
            DMA_RQ       <= '1';

        when RxWrite =>
            Valid_D      <= '1';
            TX_Data      <= (others => '0');
            if (cnt < 3) then
                Data_Read <= '1';
                Address   <= std_logic_vector(unsigned(DMA_RX_BUFFER_MSB) + cnt);
                Databus   <= RCVD_Data;
            else
                Data_Read <= '0';
                Address   <= X"03";
                Databus   <= X"FF";
            end if;
            
            Write_en     <= '1';
            OE           <= '1';
            DMA_RQ       <= '1';
        
        when RcvDone =>
            Data_Read    <= '0';
            Valid_D      <= '1';
            TX_Data      <= (others => '0');
            Address      <= (others => '0');
            Databus      <= (others => 'Z');
            Write_en     <= '0';
            OE           <= '1';
            DMA_RQ       <= '0';

        when TxSend =>
            Data_Read    <= '0';

            if TX_RDY = '1' and ACK_out = '1' then
                Valid_D <= '0';
            else
                Valid_D <= '1';
            end if;

            TX_Data      <= Databus;
            Address      <= std_logic_vector(unsigned(DMA_TX_BUFFER_MSB) + tx_cnt);
            Databus      <= (others => 'Z');
            Write_en     <= '0';
            OE           <= '0';
            DMA_RQ       <= '0';

        when TxDone =>
            Data_Read    <= '0';
            Valid_D      <= '1';
            TX_Data      <= (others => '0');
            Address      <= (others => '0');
            Databus      <= (others => 'Z');
            Write_en     <= '0';
            OE           <= '1';
            DMA_RQ       <= '0';

        when others =>
            Data_Read    <= '0';
            Valid_D      <= '1';
            TX_Data      <= (others => '0');
            Address      <= (others => '0');
            Databus      <= (others => 'Z');
            Write_en     <= '0';
            OE           <= '1';
            DMA_RQ       <= '0';

    end case;
end process;

end Behavioral;
