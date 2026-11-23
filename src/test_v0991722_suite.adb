-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.22 TACTICAL REPAIR & EN-PRISE TEST SUITE
--
--  Unit:          Test_V0991722_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;

procedure Test_V0991722_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.22 - Tactical & En-Prise Suite      ");
   Put_Line ("========================================================");

   -- 1. Test Game 2 Move 6: En-prise pawn resolve must capture attacker (c4xd5),
   --    not push past it (c4-c5??) when capturing is safe.
   Put_Line ("[1/4] Testing Game 2 Move 6: En-prise pawn resolve (c4xd5 vs c4-c5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqk2r/ppp2ppp/2n1pn2/3p4/QbPP4/2N5/PP2PPPP/R1B1KBNR w KQkq - 2 6", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C4 : constant Integer := Sq ('c', '4');
      Sq_D5 : constant Integer := Sq ('d', '5');
      Sq_C5 : constant Integer := Sq ('c', '5');
   begin
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Game 2 Move 6: Best_En_Prise_Resolve finds move", Found);
      Check ("Game 2 Move 6: Source square must be c4", F = Sq_C4);
      Check ("Game 2 Move 6: Target square must be d5 (capture), NOT c5 (push)", T = Sq_D5 and then T /= Sq_C5);
   end;

   -- 2. Test Game 2 Move 10: Infiltrated trapped queen strike (10. Qxb4!)
   --    unpinning Nc3 so 11. Nd1 traps Black's Queen on f2.
   Put_Line ("[2/4] Testing Game 2 Move 10: Trapped Queen strike (10. Qxb4!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1b1k2r/ppp2ppp/2n1p3/2Pp4/Qb1P4/2N2N2/PP1KPqPP/R4B1R w kq - 0 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_A4 : constant Integer := Sq ('a', '4');
      Sq_B4 : constant Integer := Sq ('b', '4');
   begin
      Search_Integration.Best_Trapped_Infiltrated_Queen_Strike (True, Found, F, T);
      Check ("Game 2 Move 10: Best_Trapped_Infiltrated_Queen_Strike finds move", Found);
      Check ("Game 2 Move 10: Source square must be a4 (Queen)", F = Sq_A4);
      Check ("Game 2 Move 10: Target square must be b4 (capturing pinning bishop)", T = Sq_B4);
   end;

   -- 3. Test Black-side symmetry for trapped queen strike:
   --    White Queen on f7, Black King on d7, Black Knight on c6 pinned along b5-c6-d7 by White Bishop on b5.
   --    Black Queen on a5 plays 10... Qxb5! unpinning c6 so 11... Nd8 traps White Queen on f7.
   Put_Line ("[3/4] Testing Trapped Queen strike symmetry (Black to move: Qxb5!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r4b1r/pp1kpQpp/2n2n2/qB1p4/2pP4/2P1P3/PP3PPP/R1B1K2R b - - 0 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_A5 : constant Integer := Sq ('a', '5');
      Sq_B5 : constant Integer := Sq ('b', '5');
   begin
      Search_Integration.Best_Trapped_Infiltrated_Queen_Strike (False, Found, F, T);
      Check ("Black-side: Best_Trapped_Infiltrated_Queen_Strike finds move", Found);
      Check ("Black-side: Source square must be a5 (Queen)", F = Sq_A5);
      Check ("Black-side: Target square must be b5 (capturing pinning bishop)", T = Sq_B5);
   end;

   -- 4. Test Game 1 Move 9: Two Knights Fried Liver castling legality & protection (9. O-O)
   Put_Line ("[4/4] Testing Two Knights Fried Liver castling legality (9. O-O)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/2n1k3/3np3/2B5/5Q2/PPPP1PPP/RNB1K2R w KQ - 2 9", Dummy_White);

   declare
      Can_Castle_K : constant Boolean :=
        Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => True);
   begin
      Check ("Fried Liver Move 9: White Kingside castling must be legally available", Can_Castle_K);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991722_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991722_Suite;
