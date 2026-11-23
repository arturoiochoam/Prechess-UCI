-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.28 INFINITE VERIFIER & DYNAMIC HASH SUITE
--
--  Unit:          Test_V0991728_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Tactical_Search;
with TT_Table;

procedure Test_V0991728_Suite is

   Failures : Natural := 0;
   Dummy_White : Boolean;

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
   Put_Line ("  Prechess 0.9.9.17.28 - Infinite Verifier & Hash Suite");
   Put_Line ("========================================================");

   --  1. Dynamic Hash resizing: Set_Hash_MB adjusts verifier table entries.
   Put_Line ("[1/3] Verifier Set_Hash_MB allocation and entry count scaling...");
   Tactical_Search.Set_Hash_MB (16);
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", Dummy_White);
   declare
      R1 : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move => True,
           Chosen_From   => Sq ('g', '1'), Chosen_To => Sq ('f', '1'), Chosen_Promo => 0,
           Budget_Ms     => 500,
           Max_Depth     => 4);
      Entries_16MB : constant Natural := Tactical_Search.Current_Hash_Entries;
   begin
      Check ("16 MB Verify completed", R1.Valid);
      Check ("16 MB entries allocated", Entries_16MB > 0);

      Tactical_Search.Set_Hash_MB (32);
      declare
         R2 : constant Tactical_Search.Verify_Result :=
           Tactical_Search.Verify
             (White_To_Move => True,
              Chosen_From   => Sq ('g', '1'), Chosen_To => Sq ('f', '1'), Chosen_Promo => 0,
              Budget_Ms     => 500,
              Max_Depth     => 4);
         Entries_32MB : constant Natural := Tactical_Search.Current_Hash_Entries;
      begin
         Check ("32 MB Verify completed", R2.Valid);
         Check ("32 MB entries > 16 MB entries", Entries_32MB > Entries_16MB);
      end;
   end;

   --  2. Max_Verify_Depth 20 support: Verify executes with depth cap up to 20.
   Put_Line ("[2/3] Verify with Max_Depth 20 on forced mating sequence...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", Dummy_White);
   declare
      R : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move => True,
           Chosen_From   => Sq ('g', '1'), Chosen_To => Sq ('f', '1'), Chosen_Promo => 0,
           Budget_Ms     => 2000,
           Max_Depth     => 20);
   begin
      Check ("Result valid", R.Valid);
      Check ("Cascade move replaced by Rd8#", R.Replaced);
      Check ("Best move is d1d8", R.Best.From = Sq ('d', '1') and then R.Best.To = Sq ('d', '8'));
      Check ("Mate score reported", R.Best_Score >= Tactical_Search.Mate_Threshold);
      Check ("Depth within range 1 .. 20", R.Depth in 1 .. 20);
   end;

   --  3. Timed search stays within bounds under Max_Depth 20.
   Put_Line ("[3/3] Verify budget capping in complex middlegame under Max_Depth 20...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 9", Dummy_White);
   declare
      R : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move => True,
           Chosen_From   => Sq ('f', '1'), Chosen_To => Sq ('d', '3'), Chosen_Promo => 0,
           Budget_Ms     => 1000,
           Max_Depth     => 20);
   begin
      Check ("Middlegame search valid", R.Valid);
      Check ("Completed depth in 1 .. 20", R.Depth in 1 .. 20);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991728_Suite;
