-------------------------------------------------------------------------------
--  PRECHESS UCI - LEGACY BOARD SETUP & PRESENTATION IMPLEMENTATION
--
--  Module:        Papresentacao (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        José Lauro Strapasson (Original 2001 Console Presentation)
--                 Arthur Matheus (UCI Integration & Modernization)
--  Date:          2001-2026
-------------------------------------------------------------------------------

with pprechess2; use pprechess2;
with Pvalidade;  use Pvalidade;

package body Papresentacao is

   ----------------------------------------------------------------------------
   --  STARTPOS INITIALIZATION IMPLEMENTATION
   ----------------------------------------------------------------------------
   procedure Apresentacao is
   begin
      Lance_Do_Jogo    := 0;
      Lances_Da_Pessoa := 0;
      Resposta         := 's';

      -- Clear all 64 board squares
      for A in 1 .. 64 loop
         Tabuleiro (A) := 0;
      end loop;

      Numero_B_Inimigo := 2; -- Default 2 opponent bishops

      -- White Pieces (Rank 1: R=7, N=4, B=3, Q=20, K=999)
      Tabuleiro (1) := 7;
      Tabuleiro (2) := 4;
      Tabuleiro (3) := 3;
      Tabuleiro (4) := 20;
      Tabuleiro (5) := 999;
      Tabuleiro (6) := 3;
      Tabuleiro (7) := 4;
      Tabuleiro (8) := 7;

      -- White Pawns (Rank 2: P=1)
      for Sq in 9 .. 16 loop
         Tabuleiro (Sq) := 1;
      end loop;

      -- Black Pawns (Rank 7: P=-1)
      for Sq in 49 .. 56 loop
         Tabuleiro (Sq) := -1;
      end loop;

      -- Black Pieces (Rank 8: R=-7, N=-4, B=-3, Q=-20, K=-999)
      Tabuleiro (57) := -7;
      Tabuleiro (58) := -4;
      Tabuleiro (59) := -3;
      Tabuleiro (60) := -20;
      Tabuleiro (61) := -999;
      Tabuleiro (62) := -3;
      Tabuleiro (63) := -4;
      Tabuleiro (64) := -7;

   end Apresentacao;

end Papresentacao;
