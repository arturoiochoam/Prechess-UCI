-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.24 TACTICAL REPAIR & FORK PREVENTION TEST SUITE
--
--  Unit:          Test_V0991724_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V0991724_Suite is

   Failures : Natural := 0;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   Dummy_White : Boolean;

   function Sq (File_Char : Character; Rank_Char : Character) return Integer is
      F : constant Integer := Character'Pos (File_Char) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Char) - Character'Pos ('0');
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.24 - Tactical & Fork Prevention Suite");
   Put_Line ("========================================================");

   -- 1. Test Game 1 Move 12: Best_Trapped_Piece_Rescue must capture the attacking
   --    pawn (12. dxc5!) rather than playing a passive flank push (a2-a3).
   Put_Line ("[1/5] Testing French Chatard-Alekhine Move 12: Direct capture of attacking pawn...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1k2r/3nqppp/p3p3/1pppP3/3P4/1BN2N2/PPP2PP1/R2QK2R w KQkq - 0 12", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D4 : constant Integer := Sq ('d', '4');
      Sq_C5 : constant Integer := Sq ('c', '5');
   begin
      Search_Integration.Best_Trapped_Piece_Rescue (True, Found, F, T);
      Check ("French Move 12: Best_Trapped_Piece_Rescue finds move", Found);
      Check ("French Move 12: Source square must be d4", F = Sq_D4);
      Check ("French Move 12: Target square must be c5 (dxc5!)", T = Sq_C5);
   end;

   -- 2. Test Game 2 Move 19: Has_Opponent_Double_Attack must flag 19. Na3?? as allowing
   --    the fork 19... Bb2! against the rook on c1 and knight on a3.
   Put_Line ("[2/5] Testing Semi-Slav Move 19: Double attack (fork) detection on 19. Na3...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b2rk1/1p3pp1/p4q1p/1NpQb3/2B5/1P2P3/P4PPP/2R2RK1 w - - 0 19", Dummy_White);

   declare
      Sq_A3    : constant Integer := Sq ('a', '3');
      Sq_B5    : constant Integer := Sq ('b', '5');
      Has_Fork : Boolean;
      Saved_T  : Integer;
   begin
      -- Move Knight to a3 on trial board to query double attack
      Pvalidade.Tabuleiro (Sq_B5) := 0;
      Pvalidade.Tabuleiro (Sq_A3) := 4;
      Has_Fork := Search_Integration.Has_Opponent_Double_Attack (White_To_Move => True, Target_Sq => Sq_A3);
      Pvalidade.Tabuleiro (Sq_A3) := 0;
      Pvalidade.Tabuleiro (Sq_B5) := 4;
      Check ("Semi-Slav Move 19: Na3 must be flagged for allowing opponent fork (Bb2)", Has_Fork);
   end;

   -- 3. Test Game 2 Move 19: Best_En_Prise_Resolve must NOT return 19. Na3.
   Put_Line ("[3/5] Testing Semi-Slav Move 19: Best_En_Prise_Resolve rejects Na3...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b2rk1/1p3pp1/p4q1p/1NpQb3/2B5/1P2P3/P4PPP/2R2RK1 w - - 0 19", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_A3 : constant Integer := Sq ('a', '3');
   begin
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Semi-Slav Move 19: Best_En_Prise_Resolve must not pick Na3", not (Found and then T = Sq_A3));
   end;

   -- 4. Test Game 1 Move 13: Best_Natural_Development must NOT return 13. Qe2
   --    because removing the queen's guard leaves d4 hanging (Max_Opponent_See > 0).
   Put_Line ("[4/5] Testing French Move 13: Natural development must preserve central guards...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b1k2r/3nqppp/p1n1p3/1pppP3/3P4/PBN2N2/1PP2PP1/R2QK2R w KQkq - 1 13", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D1 : constant Integer := Sq ('d', '1');
      Sq_E2 : constant Integer := Sq ('e', '2');
   begin
      Search_Integration.Best_Natural_Development (True, Found, F, T);
      Check ("French Move 13: Natural development must not choose Qe2 (leaving d4 hanging)", not (Found and then F = Sq_D1 and then T = Sq_E2));
   end;

   -- 5. Test Black symmetry for trapped piece rescue capture:
   Put_Line ("[5/5] Testing Black symmetry: Direct capture of attacking pawn...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk2r/ppp2pp1/1bn2n2/3p4/1PPPp3/P3P3/3NQPPP/RNB1K2R b KQkq - 0 12", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D5 : constant Integer := Sq ('d', '5');
      Sq_C4 : constant Integer := Sq ('c', '4');
   begin
      Search_Integration.Best_Trapped_Piece_Rescue (False, Found, F, T);
      Check ("Black-side: Best_Trapped_Piece_Rescue finds move", Found);
      Check ("Black-side: Source square must be d5", F = Sq_D5);
      Check ("Black-side: Target square must be c4 (d5xc4)", T = Sq_C4);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991724_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
      raise Program_Error with "Test_V0991724_Suite failed";
   end if;

end Test_V0991724_Suite;
