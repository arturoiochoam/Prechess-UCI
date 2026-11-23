-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.20 SEARCH-STACK & VERIFIER AUDIT TEST SUITE
--
--  Unit:          Test_V0991720_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Gen;
with Move_Validation;
with Search_Integration;
with Tactical_Search;
with Pvalidade;

procedure Test_V0991720_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.20 - Search-Stack & Verifier Suite  ");
   Put_Line ("========================================================");

   -- 1. Test Startpos Legal Move Generation & Perft Depth 1 & 2:
   Put_Line ("[1/4] Testing Startpos Move Generation and Perft Depth 1 & 2...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);

   declare
      N1_Gen  : constant Long_Long_Integer := Move_Gen.Perft (1, True);
      N1_Fast : constant Long_Long_Integer := Tactical_Search.Perft_Fast (1, True);
      N2_Gen  : constant Long_Long_Integer := Move_Gen.Perft (2, True);
      N2_Fast : constant Long_Long_Integer := Tactical_Search.Perft_Fast (2, True);
   begin
      Check ("Startpos Perft(1) = 20 (Move_Gen)", N1_Gen = 20);
      Check ("Startpos Perft_Fast(1) = 20 (Tactical_Search)", N1_Fast = 20);
      Check ("Startpos Perft(2) = 400 (Move_Gen)", N2_Gen = 400);
      Check ("Startpos Perft_Fast(2) = 400 (Tactical_Search)", N2_Fast = 400);
   end;

   -- 2. Test Tactical Static Evaluation:
   Put_Line ("[2/4] Testing Tactical Static Evaluation on Startpos...");
   declare
      Eval : constant Integer := Tactical_Search.Evaluate_White;
   begin
      -- Initial position static evaluation must be balanced (within +/- 30 cp)
      Check ("Initial position static evaluation is near zero", abs Eval <= 30);
   end;

   -- 3. Test Ray Obstruction Matrix & Pin Alignment:
   Put_Line ("[3/4] Testing Precalculated Ray Obstruction Matrix...");
   declare
      Sq_A1 : constant Integer := Sq ('a', '1');
      Sq_A2 : constant Integer := Sq ('a', '2');
      Sq_A3 : constant Integer := Sq ('a', '3');
      Sq_A4 : constant Integer := Sq ('a', '4');
      Sq_A8 : constant Integer := Sq ('a', '8');
   begin
      -- Ray from a1 to a8 is blocked by pawn on a2
      Check ("Ray from a1 to a8 is obstructed by pawn on a2", not Move_Validation.Is_Ray_Clear (Sq_A1, Sq_A8));
      -- Ray from a2 to a4 is clear when a3 is empty
      Check ("Ray from a2 to a4 is clear through empty a3", Move_Validation.Is_Ray_Clear (Sq_A2, Sq_A4));
   end;

   -- 4. Test Check Detection and Evading Moves:
   Put_Line ("[4/4] Testing In-Check Detection and King Move Generation...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnb1kbnr/pppp1ppp/8/4p3/5PPq/8/PPPPP2P/RNBQKBNR w KQkq - 1 3", Dummy_White);

   declare
      In_Check  : constant Boolean := Move_Validation.Is_In_Check (White_King => True);
      Move_List : Move_Gen.Move_List;
   begin
      Check ("Fool's Mate position: White is in check", In_Check);
      Move_Gen.Generate_Legal_Moves (White_To_Move => True, List => Move_List);
      -- In Fool's Mate (1. f4 e5 2. g4 Qh4#), White has 0 legal moves (checkmate)
      Check ("Fool's Mate: White has 0 legal moves (checkmate)", Move_List.N = 0);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991720_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991720_Suite;
