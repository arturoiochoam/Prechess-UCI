-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.26 BACK-RANK ESCAPE GUARD & HASHFULL SUITE
--
--  Unit:          Test_V0991726_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with TT_Table;
with TT_Types; use TT_Types;

procedure Test_V0991726_Suite is

   Failures : Natural := 0;
   Dummy_White : Boolean;
   Move_None   : constant Move_Type := (From_Sq => 1, To_Sq => 1, Prom => 0);

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   function Sq (File_Char : Character; Rank_Char : Character) return Integer is
      F : constant Integer := Character'Pos (File_Char) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Char) - Character'Pos ('0');
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.26 - Back-Rank Guard & Hashfull Suite");
   Put_Line ("========================================================");

   --  1. Constricted-king escape is inactive while the king is on its back
   --     rank (boxed only by its own undeveloped pieces).
   Put_Line ("[1/3] Back-rank guard for Best_Constricted_King_Escape...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3", Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
   begin
      Search_Integration.Best_Constricted_King_Escape (True, Found, F, T);
      Check ("White king on e1 (rank 1): no escape suggested", not Found);
   end;

   Put_Line ("[2/3] Back-rank guard, Black side (king on e8)...");
   Search_Integration.Parse_FEN
     ("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 3 3", Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
   begin
      Search_Integration.Best_Constricted_King_Escape (False, Found, F, T);
      Check ("Black king on e8 (rank 8): no escape suggested", not Found);
   end;

   --  2. Hashfull reflects current-generation stores immediately (the value
   --     Report_UCI now reads after the root candidate store).
   Put_Line ("[3/3] Hashfull counts a store made in the current generation...");
   TT_Table.Init_TT (1);
   TT_Table.New_Generation;
   Check ("Fresh generation reads 0", TT_Table.Hash_Full_Permille = 0);
   for I in 0 .. 9999 loop
      TT_Table.Store_TT (Key => Hash_Key (I) * 7919 + 1, Depth => 3, Score => 0,
                         Flag => Exact, Best => Move_None);
   end loop;
   Check ("Hashfull > 0 right after stores", TT_Table.Hash_Full_Permille > 0);
   TT_Table.New_Generation;
   Check ("New generation resets hashfull to 0", TT_Table.Hash_Full_Permille = 0);

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991726_Suite;
