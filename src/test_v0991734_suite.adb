-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.34 EXHAUSTIVE ENGINE VERIFICATION SUITE
--
--  Unit:          Test_V0991734_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Move_Gen;
with Tactical_Search;
with TT_Table;
with Time_Management;
with Pvalidade;

procedure Test_V0991734_Suite is

   Failures    : Natural := 0;
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
   Put_Line ("  Prechess 0.9.9.17.34 - Exhaustive Verification Suite");
   Put_Line ("========================================================");

   --  1. Startpos Perft baseline validation
   Put_Line ("[1/15] Validating Startpos Perft baselines (D1=20, D2=400, D3=8902)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);
   declare
      N1 : constant Long_Long_Integer := Move_Gen.Perft (1, True);
      N2 : constant Long_Long_Integer := Move_Gen.Perft (2, True);
      N3 : constant Long_Long_Integer := Move_Gen.Perft (3, True);
   begin
      Check ("Startpos Perft D1 = 20", N1 = 20);
      Check ("Startpos Perft D2 = 400", N2 = 400);
      Check ("Startpos Perft D3 = 8902", N3 = 8902);
   end;

   --  2. Kiwipete Perft baseline validation
   Put_Line ("[2/15] Validating Kiwipete Perft baselines (D1=48, D2=2039)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", Dummy_White);
   declare
      K1 : constant Long_Long_Integer := Move_Gen.Perft (1, True);
      K2 : constant Long_Long_Integer := Move_Gen.Perft (2, True);
   begin
      Check ("Kiwipete Perft D1 = 48", K1 = 48);
      Check ("Kiwipete Perft D2 = 2039", K2 = 2039);
   end;

   --  3. Threefold Repetition detection
   Put_Line ("[3/15] Validating Threefold Repetition detection...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);
   Search_Integration.Make_Move_UCI ("g1f3");
   Search_Integration.Make_Move_UCI ("g8f6");
   Search_Integration.Make_Move_UCI ("f3g1");
   Search_Integration.Make_Move_UCI ("f6g8");
   Search_Integration.Make_Move_UCI ("g1f3");
   Search_Integration.Make_Move_UCI ("g8f6");
   Search_Integration.Make_Move_UCI ("f3g1");
   Search_Integration.Make_Move_UCI ("f6g8");
   Check ("Threefold repetition correctly identified", Search_Integration.Is_Threefold_Repetition);

   --  4. Fifty-Move Rule counter and reset
   Put_Line ("[4/15] Validating 50-Move rule counter increments and capture resets...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);
   Search_Integration.Make_Move_UCI ("g1f3");
   Search_Integration.Make_Move_UCI ("g8f6");
   Check ("Fifty move counter advanced on quiet moves", Search_Integration.Fifty_Move_Counter = 2);
   Search_Integration.Make_Move_UCI ("e2e4");
   Check ("Fifty move counter reset on pawn move", Search_Integration.Fifty_Move_Counter = 0);

   --  5. Dead Position / Insufficient Material (KK, KNK, KBK)
   Put_Line ("[5/15] Validating FIDE insufficient material recognition...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/4k3/8/8/4K3/8 w - - 0 1", Dummy_White);
   Check ("Bare kings is dead position", Search_Integration.Is_Insufficient_Material);
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/4k3/8/5N2/4K3/8 w - - 0 1", Dummy_White);
   Check ("King + Knight vs King is dead position", Search_Integration.Is_Insufficient_Material);
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/4k3/8/5B2/4K3/8 w - - 0 1", Dummy_White);
   Check ("King + Bishop vs King is dead position", Search_Integration.Is_Insufficient_Material);

   --  6. Transposition Table Dynamic Allocation & Clamping
   Put_Line ("[6/15] Validating TT table allocation and size clamping...");
   TT_Table.Init_TT (64);
   Check ("TT table allocated successfully for 64 MB", TT_Table.Current_Size_MB = 64);
   TT_Table.Resize_TT (0);
   Check ("TT table clamps below-minimum (0 MB) to 1 MB",
          TT_Table.Current_Size_MB = TT_Table.Min_Size_MB);
   TT_Table.Resize_TT (TT_Table.Max_Size_MB + 1024);
   Check ("TT table clamps above-maximum (>4096 MB) to <= Max_Size_MB",
          TT_Table.Current_Size_MB = TT_Table.Max_Size_MB
          or else TT_Table.Current_Size_MB = 0);
   TT_Table.Resize_TT (128);
   Check ("TT table restored to 128 MB", TT_Table.Current_Size_MB = 128);

   --  7. Time Management Budgeting & Panic Floor
   Put_Line ("[7/15] Validating Time Management allocation safety...");
   Time_Management.Start_Search
     (WTime       => 180000,
      BTime       => 180000,
      WInc        => 3000,
      BInc        => 3000,
      Moves_To_Go => 0,
      Move_Time   => 0,
      Depth       => 0,
      Is_White    => True,
      Infinite    => False);
   declare
      Alloc : constant Integer := Time_Management.Allocated_Budget_Ms;
   begin
      Check ("Time allocation within sane range for 180+3", Alloc >= 1000 and then Alloc <= 30000);
   end;

   --  8. Absolute Self-Pin Detection (Allows_Major_Pin)
   Put_Line ("[8/15] Validating Allows_Major_Pin self-pin defense...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/5k2/6p1/Rpn5/8/8/PPP4P/1K6 b - - 2 39", Dummy_White);
   declare
      Nb7_Pins : constant Boolean :=
        Search_Integration.Allows_Major_Pin
          (White_To_Move => False, Target_Sq => Sq ('b', '7'), Attacker_Sq => Sq ('a', '5'));
      Ne4_Pins : constant Boolean :=
        Search_Integration.Allows_Major_Pin
          (White_To_Move => False, Target_Sq => Sq ('e', '4'), Attacker_Sq => Sq ('a', '5'));
   begin
      Check ("Allows_Major_Pin flags 39... Nb7?? as walking into pin", Nb7_Pins);
      Check ("Allows_Major_Pin clears safe centralizing move 39... Ne4!", not Ne4_Pins);
   end;

   --  9. Passed Pawn Blockade King Step (36. Kc1!)
   Put_Line ("[9/15] Validating Best_Passed_Pawn_Blockade_King_Step (36. Kc1!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("6k1/p3r1p1/8/8/1pp1r3/1P6/3Rp3/3KR3 w - - 0 36", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Passed_Pawn_Blockade_King_Step
        (White_To_Move => True, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Blockade King Step found for White", Found);
      Check ("From square is d1", F_Sq = Sq ('d', '1'));
      Check ("To square is c1 (36. Kc1!)", T_Sq = Sq ('c', '1'));
   end;

   --  10. Pinning Bishop Flank Expulsion (13... f6!)
   Put_Line ("[10/15] Validating Best_Pinning_Bishop_Kick (13... f6!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k1nr/1b1p1p1p/p2bp1p1/2p3B1/4P3/2N2N2/PPP2PPP/R3R1K1 b kq - 1 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Pinning_Bishop_Kick
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Pinning bishop kick found for Black", Found);
      Check ("Pawn kicks bishop from f7", F_Sq = Sq ('f', '7'));
      Check ("Pawn arrives on f6 (13... f6!)", T_Sq = Sq ('f', '6'));
   end;

   --  11. Queen Fork Counter-Attack Dual-Threat Battery (13... Qb6!)
   Put_Line ("[11/15] Validating Best_Queen_Fork_Counter_Attack (13... Qb6!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1rk1/pp1np1bp/2p1P1p1/6B1/2P3n1/2N2N2/PP4PP/R2QKB1R b KQ - 0 13", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Queen_Fork_Counter_Attack
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Queen counter-attacking battery found for Black", Found);
      Check ("Queen moves from d8", F_Sq = Sq ('d', '8'));
      Check ("Queen attacks on b6 (13... Qb6!)", T_Sq = Sq ('b', '6'));
   end;

   --  12. Outpost Knight Challenge (24... Nbc6!)
   Put_Line ("[12/15] Validating Best_Central_Knight_Challenge (24... Nbc6!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1nb3R1/1pk5/p3p3/3pnB2/3N4/2N5/PPP1KP2/8 b - - 4 24", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_Central_Knight_Challenge
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Outpost knight challenge found for Black", Found);
      Check ("Home knight moves from b8", F_Sq = Sq ('b', '8'));
      Check ("Knight challenges on c6 (24... Nbc6!)", T_Sq = Sq ('c', '6'));
   end;

   --  13. Safe Flank Queen Central Retreat (8... Qe7!)
   Put_Line ("[13/15] Validating Best_En_Prise_Resolve flank queen retreat (8... Qe7!)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1nb1k2r/pppn1ppp/4p3/3pP1q1/3P4/2N2N2/PPP2PP1/R2QKB1R b KQkq - 1 8", Dummy_White);
   declare
      Found : Boolean;
      F_Sq, T_Sq : Integer;
   begin
      Search_Integration.Best_En_Prise_Resolve
        (White_To_Move => False, Found => Found, From_Sq => F_Sq, To_Sq => T_Sq);
      Check ("Queen en-prise resolution found for Black", Found);
      Check ("Queen retreats from g5", F_Sq = Sq ('g', '5'));
      Check ("Queen retreats to central e7 (8... Qe7!)", T_Sq = Sq ('e', '7'));
   end;

   --  14. Uncontested Checking Fork Veto
   Put_Line ("[14/15] Validating Allows_Uncontested_Checking_Fork move veto...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1nb3R1/1pk5/p3p3/3pnB2/3N4/2N5/PPP1KP2/8 b - - 4 24", Dummy_White);
   declare
      Before_Exf5 : constant Boolean :=
        Search_Integration.Allows_Uncontested_Checking_Fork (Defender_White => False);
      After_Exf5  : Boolean;
   begin
      Check ("Baseline position check for fork condition", not Before_Exf5);
      Search_Integration.Make_Move_UCI ("e6f5");
      After_Exf5 :=
        Search_Integration.Allows_Uncontested_Checking_Fork (Defender_White => False);
      Check ("Allows_Uncontested_Checking_Fork detects fork after 24... exf5??", After_Exf5);
   end;

   --  15. FEN King Cardinality and Round-Trip Validation
   Put_Line ("[15/15] Validating FEN King cardinality and position round-trip...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);
   Check ("White king present on e1", Move_Validation.Find_King (True) = Sq ('e', '1'));
   Check ("Black king present on e8", Move_Validation.Find_King (False) = Sq ('e', '8'));

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST SUITE FAILED WITH" & Natural'Image (Failures) & " FAILURES");
   end if;

end Test_V0991734_Suite;
