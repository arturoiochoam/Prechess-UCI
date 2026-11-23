-------------------------------------------------------------------------------
--  PRECHESS UCI - DIAGNOSTICS, HEURISTIC OPTIONS, GUARD & RAY HARNESS
--
--  Harness:       Test_Diagnostics_And_Eval
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Author:        Arthur Matheus (UCI Engine Integration & Test Harness)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Precalculated Ray Obstruction Matrix (`Ray_Between` & `Is_Ray_Clear`):
--     - Collinear orthogonal rays (Rank/File), diagonal rays, and obstructions.
--  2. Guard Network Evaluator (`Count_Protections`):
--     - Startpos pawn protections, knight guards, and defended piece counting.
--  3. Sliding Piece Mobility (`Compute_Mobility`):
--     - Reachable square counting across opening and open positions.
--  4. Configurable Heuristic Spin Options (`Set_Heuristic_Option`):
--     - Dynamic parameter mutation verification.
--  5. Legal Move Generator Verification:
--     - Legal move enumeration on startpos (20 moves) and tactical positions.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Move_Validation;
with Search_Integration;
with Move_Gen;
with Pvalidade;

procedure Test_Diagnostics_And_Eval is
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

   White_To_Move : Boolean;
   Black_To_Move : Boolean;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.12 - Diagnostics & Evaluation Test Gate");
   Put_Line ("========================================================");

   -- 1. Test Ray_Between & Is_Ray_Clear
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_To_Move);

   -- a1 (Sq 1) to a8 (Sq 57): Collinear vertical ray
   Check ("Ray_Between a1..a8 is non-zero",
          Move_Validation.Ray_Between (1, 57) /= 0);

   -- In startpos, a1..a8 is blocked by pawns on a2 and a7
   Check ("Ray a1..a8 is obstructed in startpos",
          not Move_Validation.Is_Ray_Clear (1, 57));

   -- Non-collinear knight leap e1 (Sq 5) to f3 (Sq 22) has Ray_Between = 0
   Check ("Ray_Between e1..f3 (knight leap) is zero",
          Move_Validation.Ray_Between (5, 22) = 0);

   -- 2. Test Guard Network (Count_Protections)
   -- In startpos, pawns on rank 2 are protected by back-rank pieces / pawns
   declare
      White_Guards : constant Integer := Search_Integration.Count_Protections (True);
      Black_Guards : constant Integer := Search_Integration.Count_Protections (False);
   begin
      Check ("Startpos White Guard count > 0", White_Guards > 0);
      Check ("Startpos Black Guard count > 0", Black_Guards > 0);
      Check ("Startpos Guard counts are symmetric", White_Guards = Black_Guards);
   end;

   -- 3. Test Mobility (Compute_Mobility)
   declare
      White_Mob : constant Integer := Search_Integration.Compute_Mobility (True);
      Black_Mob : constant Integer := Search_Integration.Compute_Mobility (False);
   begin
      Check ("Startpos White Mobility is 0 (all sliding pieces blocked)", White_Mob = 0);
      Check ("Startpos Black Mobility is 0 (all sliding pieces blocked)", Black_Mob = 0);
   end;

   -- Open board test for Mobility (King on c1 and h1 away from e5 rays)
   Search_Integration.Parse_FEN
     ("8/8/8/4Q3/8/8/8/2K4k w - - 0 1", White_To_Move);
   declare
      Queen_Mob : constant Integer := Search_Integration.Compute_Mobility (True);
   begin
      -- A lone queen on e5 with unblocked rays has 27 reachable squares on an 8x8 board
      Check ("Lone Queen on e5 has 27 mobility squares", Queen_Mob = 27);
   end;

   -- 4. Test Configurable Heuristic Options
   Search_Integration.Set_Heuristic_Option ("Castle_Bonus", 120);
   Check ("Castle_Bonus updated to 120", Search_Integration.Castle_Bonus_Weight = 120);

   Search_Integration.Set_Heuristic_Option ("Development_Bonus", 55);
   Check ("Development_Bonus updated to 55", Search_Integration.Development_Bonus_Weight = 55);

   Search_Integration.Set_Heuristic_Option ("Mobility_Weight", 15);
   Check ("Mobility_Weight updated to 15", Search_Integration.Mobility_Bonus_Weight = 15);

   -- Restore defaults
   Search_Integration.Set_Heuristic_Option ("Castle_Bonus", 80);
   Search_Integration.Set_Heuristic_Option ("Development_Bonus", 40);
   Search_Integration.Set_Heuristic_Option ("Mobility_Weight", 10);

   -- 5. Test Legal Move Generator on startpos
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_To_Move);
   declare
      L : Move_Gen.Move_List;
   begin
      Move_Gen.Generate_Legal_Moves (True, L);
      Check ("Startpos legal moves count is 20", L.N = 20);
   end;

   -- 6. Test Strict FEN King Cardinality (v0.9.9.13 Gate P5)
   declare
      Dummy_White : Boolean := True;
   begin
      -- Kingless FEN must be rejected
      Check ("Kingless FEN rejected (8/8/8/8/8/8/P7/8)",
             not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/8/P7/8 w - - 0 1", Dummy_White));
      -- Missing Black King must be rejected
      Check ("Missing Black King FEN rejected",
             not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/8/4K3/8 w - - 0 1", Dummy_White));
      -- Two White Kings must be rejected
      Check ("Two White Kings FEN rejected",
             not Search_Integration.Try_Parse_FEN ("8/8/8/8/8/4K3/4K3/7k w - - 0 1", Dummy_White));
      -- Legal FEN with 1 White King and 1 Black King must be accepted
      Check ("Legal standard FEN accepted",
             Search_Integration.Try_Parse_FEN ("8/8/8/8/8/4K3/8/7k w - - 0 1", Dummy_White));
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_DIAGNOSTICS_AND_EVAL: PASS");
   else
      Put_Line ("TEST_DIAGNOSTICS_AND_EVAL: FAIL (" & Natural'Image (Failures) & " failures)");
      raise Program_Error;
   end if;
   Put_Line ("========================================================");
end Test_Diagnostics_And_Eval;
