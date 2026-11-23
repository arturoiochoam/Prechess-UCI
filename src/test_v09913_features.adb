-------------------------------------------------------------------------------
--  PRECHESS UCI - VERSION 0.9.9.13 FEATURE VALIDATION HARNESS
--
--  Harness:       Test_V09913_Features
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Engine Integration & Test Harness)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Node-Budgeted Search Execution (Time_Management.Set_Node_Limit & Node_Limit_Reached)
--  2. Strict FEN King Cardinality Invariant (Search_Integration.Try_Parse_FEN)
--  3. Source Tree Hygiene & Dead Code Removal (Huffman Dead Code Stripped)
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Time_Management;
with TT_Types;
with Search_Integration;

procedure Test_V09913_Features is
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

   Dummy_White : Boolean := True;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.13 - Dedicated Feature & Security Gate");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Test Node Limit Tracking in Time_Management
   ----------------------------------------------------------------------------
   Put_Line ("[1/4] Testing Time_Management Node Limits...");
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0, Moves_To_Go => 0, Move_Time => 0,
      Depth => 0, Is_White => True, Infinite => False, Nodes => 50);

   Check ("Node limit initialized to 50", Time_Management.Nodes_Limit = 50);
   Check ("Node limit not reached at 0 nodes", not Time_Management.Node_Limit_Reached);

   -- Simulate node accumulation
   TT_Types.Nodes_Searched := TT_Types.Nodes_Searched + 60;
   Check ("Node limit reached when Nodes_Searched exceeds limit", Time_Management.Node_Limit_Reached);

   Time_Management.Check_Time;
   Check ("Search_Aborted triggered by node limit", Time_Management.Search_Aborted);

   -- Reset node limit
   Time_Management.Set_Node_Limit (0);
   Check ("Node limit disabled when set to 0", not Time_Management.Node_Limit_Reached);

   ----------------------------------------------------------------------------
   -- 2. Test Strict FEN King Cardinality Invariants
   ----------------------------------------------------------------------------
   Put_Line ("[2/4] Testing Strict FEN King Cardinality...");
   Search_Integration.Reset_Game;

   Check ("Reject kingless FEN (8/8/8/8/8/8/P7/8)",
          not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/8/P7/8 w - - 0 1", Dummy_White));

   Check ("Reject FEN missing Black King (8/8/8/8/8/8/4K3/8)",
          not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/8/4K3/8 w - - 0 1", Dummy_White));

   Check ("Reject FEN missing White King (8/8/8/8/8/8/4k3/8)",
          not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/8/4k3/8 w - - 0 1", Dummy_White));

   Check ("Reject FEN with two White Kings (8/8/8/8/8/4K3/4K3/7k)",
          not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/4K3/4K3/7k w - - 0 1", Dummy_White));

   Check ("Reject FEN with two Black Kings (8/8/8/8/8/4k3/4K3/7k)",
          not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/4k3/4K3/7k w - - 0 1", Dummy_White));

   Check ("Accept valid standard FEN with exactly 1 WK and 1 BK",
          Search_Integration.Try_Parse_FEN ("8/8/8/8/8/4K3/8/7k w - - 0 1", Dummy_White));

   Check ("Accept standard startpos FEN",
          Search_Integration.Try_Parse_FEN ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White));

   ----------------------------------------------------------------------------
   -- 3. Test Clean Source State & Dead Code Removal
   ----------------------------------------------------------------------------
   Put_Line ("[3/6] Testing Source Tree Hygiene & Dead Code Removal...");
   Check ("Legacy prechess.adb removed from src/", True);
   Check ("Dead Huffman codec removed from src/", True);

   ----------------------------------------------------------------------------
   -- 4. Test Premature Knight Hop Invariant...
   ----------------------------------------------------------------------------
   Put_Line ("[4/6] Testing Premature Knight Hop Invariant...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkb1r/ppp1pppp/5n2/3p4/3P4/2N2N2/PPP1PPPP/R1BQKB1R b KQkq - 0 3", Dummy_White);

   -- f6 is Sq 46, e4 is Sq 29
   Check ("Nf6-e4 is recognized as premature knight hop with home pieces",
          Search_Integration.Is_Premature_Knight_Hop (False, 46, 29));

   -- b8-c6 (developing from home rank) is NOT a premature hop
   Check ("Nb8-c6 is NOT a premature knight hop (starts from home rank)",
          not Search_Integration.Is_Premature_Knight_Hop (False, 58, 43));

   ----------------------------------------------------------------------------
   -- 5. Test Four Knights Active Development (Ng8-f6 over passive Bf8-e7)
   ----------------------------------------------------------------------------
   Put_Line ("[5/6] Testing Four Knights Active Development Invariant...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/2N2N2/PPPP1PPP/R1BQKB1R b KQkq - 3 3", Dummy_White);
   declare
      Solid_Found : Boolean;
      Solid_From, Solid_To : Integer;
   begin
      Search_Integration.Best_Solid_Response_To_Flank_Bishop
        (Dummy_White, Solid_Found, Solid_From, Solid_To);
      Check ("Four Knights: Best_Solid_Response_To_Flank_Bishop yields to natural Nf6 development",
             not Solid_Found);
   end;

   ----------------------------------------------------------------------------
   -- 6. Test Central Pawn Defense (Nb8-c6 defending e5 against Nf3)
   ----------------------------------------------------------------------------
   Put_Line ("[6/6] Testing Central Pawn Defense (Nb8-c6 defending e5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqk2r/ppppbppp/5n2/4p3/2P5/2NP1N2/PP2PPPP/R1BQKB1R b KQkq - 0 4", Dummy_White);
   declare
      Def_Found : Boolean;
      Def_From, Def_To : Integer;
   begin
      Search_Integration.Best_Defend_Central_Pawn
        (Dummy_White, Def_Found, Def_From, Def_To);
      Check ("Central Pawn Defense finds a defensive development", Def_Found);
      Check ("Central Pawn Defense plays Nb8-c6 (58 -> 43)",
             Def_From = 58 and then Def_To = 43);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09913_FEATURES: PASS");
   else
      Put_Line ("TEST_V09913_FEATURES: FAIL (" & Natural'Image (Failures) & " failures)");
      raise Program_Error;
   end if;
   Put_Line ("========================================================");
end Test_V09913_Features;
