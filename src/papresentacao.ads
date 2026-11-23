-------------------------------------------------------------------------------
--  PRECHESS UCI - LEGACY BOARD SETUP & PRESENTATION SPECIFICATION
--
--  Module:        Papresentacao
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        José Lauro Strapasson (Original 2001 Console Presentation)
--                 Arthur Matheus (UCI Integration & Modernization)
--  Date:          2001-2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Papresentacao` initializes the standard starting chess position (startpos)
--  into the global mailbox array `Pvalidade.Tabuleiro` and resets move telemetry
--  and game-state variables for the legacy console and WinBoard interfaces.
-------------------------------------------------------------------------------

package Papresentacao is

   Lances_Da_Pessoa : Integer;
   Usaingles        : Character;
   Tabuleironormal  : Boolean := True;
   Usa_Tabuleiro    : Character;
   Resposta         : Character;
   Winboard         : Boolean := True;

   ----------------------------------------------------------------------------
   --  STARTPOS INITIALIZATION ENTRY POINT
   ----------------------------------------------------------------------------
   --  Populates `Pvalidade.Tabuleiro` with the standard 32 chess pieces on their
   --  home squares (Ranks 1, 2 for White; Ranks 7, 8 for Black) and zeroes all
   --  remaining squares. Resets `pprechess2.Lance_Do_Jogo` and bishop counters.
   ----------------------------------------------------------------------------
   procedure Apresentacao;

end Papresentacao;
