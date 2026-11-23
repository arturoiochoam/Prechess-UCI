-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.34 FIX REGRESSION SUITE
--
--  Unit:          Test_V0991734_Fixes
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Gen;
with Search_Integration;
with Tactical_Search;
with Time_Management;
with TT_Table;
with TT_Types;   use TT_Types;

procedure Test_V0991734_Fixes is
   Failures    : Natural := 0;
   White_Move  : Boolean := True;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;
begin
   Put_Line ("=== Phase 2: FIDE Draw Rules & FEN Validation ===");

   --  1. KBB vs KB (all bishops on dark squares: c1, f4, f8) -> dead position
   Search_Integration.Reset_Game;
   Check ("Parse KBB vs KB same-color FEN",
          Search_Integration.Try_Parse_FEN
            ("4kb2/8/8/8/5B2/8/8/2B1K3 w - - 0 1", White_Move));
   Check ("KBB vs KB same-color bishops is insufficient material",
          Search_Integration.Is_Insufficient_Material);

   --  2. KBBB vs K (all bishops on light squares: a2, b1, c2) -> dead position
   Search_Integration.Reset_Game;
   Check ("Parse KBBB vs K same-color FEN",
          Search_Integration.Try_Parse_FEN
            ("4k3/8/8/8/8/8/B1B5/1B2K3 w - - 0 1", White_Move));
   Check ("KBBB vs K same-color bishops is insufficient material",
          Search_Integration.Is_Insufficient_Material);

   --  3. KBB vs KB with mixed bishop colors -> NOT dead (helpmate exists)
   Search_Integration.Reset_Game;
   Check ("Parse KBB vs KB mixed-color FEN",
          Search_Integration.Try_Parse_FEN
            ("4k1b1/8/8/8/5B2/8/8/2B1K3 w - - 0 1", White_Move));
   Check ("KBB vs KB mixed-color bishops is sufficient",
          not Search_Integration.Is_Insufficient_Material);

   --  4. Checkmate takes precedence over 50-move / 75-move draw
   Search_Integration.Reset_Game;
   Check ("Parse mate-on-100th-ply FEN",
          Search_Integration.Try_Parse_FEN
            ("7k/6Q1/6K1/8/8/8/8/8 b - - 100 60", White_Move));
   Check ("Checkmate takes precedence over Is_Fifty_Move_Rule",
          not Search_Integration.Is_Fifty_Move_Rule);
   Check ("Checkmate takes precedence over Is_Draw",
          not Search_Integration.Is_Draw);

   --  5. Try_Parse_FEN rejects FEN where non-side-to-move king is in check
   Search_Integration.Reset_Game;
   Check ("Try_Parse_FEN rejects FEN with non-active king in check",
          not Search_Integration.Try_Parse_FEN
            ("4k3/8/8/8/8/8/4R3/4K3 w - - 0 1", White_Move));

   --  6. Threefold / Fivefold / 50-move / 75-move thresholds
   Search_Integration.Reset_Game;
   Check ("Parse non-mate 100-ply FEN",
          Search_Integration.Try_Parse_FEN
            ("4k3/8/8/8/8/8/R7/4K3 w - - 100 60", White_Move));
   Check ("50-move rule true at halfmove 100 when not mate",
          Search_Integration.Is_Fifty_Move_Rule);
   Check ("75-move rule false at halfmove 100",
          not Search_Integration.Is_Seventy_Five_Move_Rule);

   Search_Integration.Reset_Game;
   Check ("Parse non-mate 150-ply FEN",
          Search_Integration.Try_Parse_FEN
            ("4k3/8/8/8/8/8/R7/4K3 w - - 150 90", White_Move));
   Check ("75-move rule true at halfmove 150",
          Search_Integration.Is_Seventy_Five_Move_Rule);
   Check ("Is_Draw true via 75-move rule",
          Search_Integration.Is_Draw);

   Search_Integration.Reset_Game;
   Check ("Parse mate-on-150th-ply FEN",
          Search_Integration.Try_Parse_FEN
            ("7k/6Q1/6K1/8/8/8/8/8 b - - 150 90", White_Move));
   Check ("Checkmate takes precedence over Is_Seventy_Five_Move_Rule",
          not Search_Integration.Is_Seventy_Five_Move_Rule);

   --  Fivefold repetition (current occurrence counts as 5th)
   Search_Integration.Reset_Game;
   Check ("Parse fivefold test FEN",
          Search_Integration.Try_Parse_FEN
            ("4k3/8/8/8/8/8/R7/4K3 w - - 0 1", White_Move));
   for Cycle in 1 .. 4 loop
      Search_Integration.Make_Move_UCI ("e1e2");
      Search_Integration.Make_Move_UCI ("e8e7");
      Search_Integration.Make_Move_UCI ("e2e1");
      Search_Integration.Make_Move_UCI ("e7e8");
      if Cycle < 4 then
         Check ("Not fivefold before 5th occurrence",
                not Search_Integration.Is_Fivefold_Repetition);
      end if;
   end loop;
   Check ("Fivefold repetition detected at 5th occurrence",
          Search_Integration.Is_Fivefold_Repetition);

   --  7. TT resize stress (100 cycles across 1..32 MB), power-of-two clusters & Hashfull
   for Cycle in 1 .. 100 loop
      TT_Table.Resize_TT (((Cycle * 7) mod 32) + 1);
   end loop;
   Check ("TT stays allocated after 100 resize cycles",
          TT_Table.Current_Size_MB > 0);
   Check ("TT Hashfull is 0 right after Resize_TT",
          TT_Table.Hash_Full_Permille = 0);
   declare
      C : constant Hash_Key := TT_Table.Cluster_Count;
   begin
      Check ("TT Cluster_Count is power of two",
             C >= 1 and then (C and (C - 1)) = 0);
   end;

   --  Exact hashfull check on 1 MB TT (fill half, then all slots)
   TT_Table.Resize_TT (1);
   declare
      C          : constant Hash_Key := TT_Table.Cluster_Count;
      Dummy_Move : constant Move_Type := (From_Sq => 1, To_Sq => 1, Prom => 0);
   begin
      for Idx in 0 .. C - 1 loop
         TT_Table.Store_TT (Idx, 1, 0, Exact, Dummy_Move);
         TT_Table.Store_TT (Idx + C, 1, 0, Exact, Dummy_Move);
      end loop;
      Check ("TT Hashfull = 500 when 2/4 slots per cluster filled",
             TT_Table.Hash_Full_Permille = 500);
      for Idx in 0 .. C - 1 loop
         TT_Table.Store_TT (Idx + 2 * C, 1, 0, Exact, Dummy_Move);
         TT_Table.Store_TT (Idx + 3 * C, 1, 0, Exact, Dummy_Move);
      end loop;
      Check ("TT Hashfull = 1000 when 4/4 slots per cluster filled",
             TT_Table.Hash_Full_Permille = 1000);
   end;

   Put_Line ("=== Phase 3: Time Management Safety & Combined Limits ===");

   --  8. Anti-flagging when increment >> remaining clock (wtime 100, winc 2000)
   Time_Management.Start_Search
     (WTime => 100, BTime => 100, WInc => 2000, BInc => 2000,
      Moves_To_Go => 0, Move_Time => 0, Depth => 0,
      Is_White => True, Infinite => False);
   Check ("wtime 100 winc 2000 never exceeds WTime - MoveOverhead (<= 70 ms)",
          Time_Management.Allocated_Ms <= 70 and then Time_Management.Allocated_Ms >= 1);

   --  9. Combined limits: depth + movetime honours BOTH limits
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 500, Depth => 12,
      Is_White => True, Infinite => False);
   Check ("Combined depth 12 + movetime 500 keeps Requested_Depth = 12",
          Time_Management.Requested_Depth = 12);
   Check ("Combined depth 12 + movetime 500 honours time budget (<= 480 ms)",
          Time_Management.Allocated_Ms <= 480 and then Time_Management.Allocated_Ms >= 460);

   --  10. Combined limits: depth + wtime honours BOTH limits
   Time_Management.Start_Search
     (WTime => 60000, BTime => 60000, WInc => 0, BInc => 0,
      Moves_To_Go => 0, Move_Time => 0, Depth => 12,
      Is_White => True, Infinite => False);
   Check ("Combined depth 12 + wtime 60000 keeps Requested_Depth = 12",
          Time_Management.Requested_Depth = 12);
   Check ("Combined depth 12 + wtime 60000 honours blitz clock (~800 ms)",
          Time_Management.Allocated_Ms >= 700 and then Time_Management.Allocated_Ms <= 900);

   --  11. Elapsed_Ms stays >= 0 & Move Overhead clamping
   Check ("Elapsed_Ms >= 0 right after Start_Search",
          Time_Management.Elapsed_Ms >= 0);
   Time_Management.Set_Move_Overhead (100);
   Check ("Set_Move_Overhead (100) updates overhead to 100",
          Time_Management.Move_Overhead = 100);
   Time_Management.Set_Move_Overhead (1);
   Check ("Set_Move_Overhead clamps below min to 10",
          Time_Management.Move_Overhead = Time_Management.Min_Move_Overhead_Ms);
   Time_Management.Set_Move_Overhead (999);
   Check ("Set_Move_Overhead clamps above max to 500",
          Time_Management.Move_Overhead = Time_Management.Max_Move_Overhead_Ms);
   Time_Management.Set_Move_Overhead (Time_Management.Default_Move_Overhead_Ms);

   Put_Line ("=== Phase 4: Tactical_Search Draw, Hash Power-of-2 & Correctness ===");

   --  12. 50-move rule respected inside Tactical_Search tree
   --  At halfmove 99, quiet Ke1-d1 pushes halfmove to 100 (draw score 0),
   --  while Re2-e8# would checkmate on the 100th ply. Put no-mate FEN:
   --  Wait: Qe5-a5 at halfmove 99 must return 0 (50-move draw), whereas Re2-e8+ on mate-in-1 scores mate.
   Search_Integration.Reset_Game;
   Check ("Parse 99-ply non-mate queen endgame FEN",
          Search_Integration.Try_Parse_FEN
            ("4k3/8/8/Q7/8/8/8/4K3 w - - 99 60", White_Move));
   Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 4, True, False);
   declare
      Res : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move   => True,
           Chosen_From     => 33,  --  a5
           Chosen_To       => 41,  --  a6
           Chosen_Promo    => 0,
           Budget_Ms       => 2000,
           Max_Depth       => 4,
           Report_Progress => False);
   begin
      Check ("Quiet move reaching halfmove 100 evaluates to 0 draw in Search",
             Res.Valid and then Res.Chosen_Score = 0);
   end;

   --  13. Verifier TT size is a power of two after Set_Hash_MB (16)
   Tactical_Search.Set_Hash_MB (16);
   Search_Integration.Reset_Game;
   Check ("Parse startpos for verifier hash resize",
          Search_Integration.Try_Parse_FEN
            ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_Move));
   Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 2, True, False);
   declare
      Dummy_R : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify (True, 13, 29, 0, 500, Max_Depth => 2);
      N_Ent   : constant Natural := Tactical_Search.Current_Hash_Entries;
      H_Pow2  : constant Hash_Key := Hash_Key (N_Ent);
   begin
      Check ("Verifier TT entry count is power of two after Set_Hash_MB (16)",
             Dummy_R.Valid and then N_Ent >= 1024
             and then (H_Pow2 and (H_Pow2 - 1)) = 0);
   end;
   Tactical_Search.Set_Hash_MB (8);

   --  14. Searchmoves_Filter restricts root choice strictly to listed moves
   Search_Integration.Reset_Game;
   Check ("Parse startpos for searchmoves filter test",
          Search_Integration.Try_Parse_FEN
            ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_Move));
   Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 3, True, False);
   declare
      Filter : Move_Gen.Move_List;
      Res    : Tactical_Search.Verify_Result;
   begin
      Filter.N := 1;
      Filter.V (1) := (From => 9, To => 17, Promo => 0); -- a2a3 only
      Res := Tactical_Search.Verify
        (White_To_Move      => True,
         Chosen_From        => 13, -- e2
         Chosen_To          => 29, -- e4 (not in Filter)
         Chosen_Promo       => 0,
         Budget_Ms          => 1500,
         Max_Depth          => 3,
         Searchmoves_Filter => Filter);
      Check ("Searchmoves_Filter returns only move inside filter (a2a3)",
             Res.Valid and then Res.Best.From = 9 and then Res.Best.To = 17);
   end;

   --  15. Mate_Target stops on Mate-in-1 without wasting unnecessary iterations
   Search_Integration.Reset_Game;
   Check ("Parse mate-in-1 FEN",
          Search_Integration.Try_Parse_FEN
            ("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", White_Move));
   Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 8, True, False);
   declare
      Res : constant Tactical_Search.Verify_Result :=
        Tactical_Search.Verify
          (White_To_Move => True,
           Chosen_From   => 1,  -- a1
           Chosen_To     => 57, -- a8#
           Chosen_Promo  => 0,
           Budget_Ms     => 2000,
           Max_Depth     => 8,
           Mate_Target   => 1);
   begin
      Check ("Mate_Target=1 stops promptly once M1 proved",
             Res.Valid and then Res.Best_Score = Tactical_Search.Mate_Value - 1
             and then Res.Depth <= 3);
   end;
   Tactical_Search.Clear_TT;
   Check ("Clear_TT preserves valid table allocation",
          Tactical_Search.Current_Hash_Entries >= 1024);

   Put_Line ("=== Phase 6: Mirrored Symmetry & Perft Parity ===");

   --  16. Perft_Fast matches Move_Gen.Perft on Startpos Depth 4 (197281)
   Search_Integration.Reset_Game;
   Check ("Parse startpos for perft parity",
          Search_Integration.Try_Parse_FEN
            ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_Move));
   Check ("Perft_Fast(4) matches Move_Gen.Perft(4) = 197281",
          Tactical_Search.Perft_Fast (4, True) = 197_281
          and then Move_Gen.Perft (4, True) = 197_281);

   --  17. Black-mirrored symmetry: Evaluate_White negates identically & mate-in-1 mirrors cleanly
   declare
      W_Eval, B_Eval : Integer;
      W_Res, B_Res   : Tactical_Search.Verify_Result;
   begin
      Search_Integration.Reset_Game;
      Check ("Parse White tactical position",
             Search_Integration.Try_Parse_FEN
               ("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", White_Move));
      W_Eval := Tactical_Search.Evaluate_White;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 4, True, False);
      W_Res := Tactical_Search.Verify (True, 1, 57, 0, 1000, Max_Depth => 4);

      Search_Integration.Reset_Game;
      Check ("Parse Black-mirrored twin position",
             Search_Integration.Try_Parse_FEN
               ("r5k1/8/8/8/8/8/5PPP/6K1 b - - 0 1", White_Move));
      B_Eval := Tactical_Search.Evaluate_White;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 4, False, False);
      B_Res := Tactical_Search.Verify (False, 57, 1, 0, 1000, Max_Depth => 4);

      Check ("Black-mirrored Evaluate_White negates identically",
             W_Eval = -B_Eval);
      Check ("Black-mirrored Verify finds symmetric mate-in-1 and equal score",
             W_Res.Valid and then B_Res.Valid
             and then W_Res.Best_Score = B_Res.Best_Score
             and then W_Res.Best.From = 1 and then W_Res.Best.To = 57
             and then B_Res.Best.From = 57 and then B_Res.Best.To = 1);
   end;

   if Failures = 0 then
      Put_Line ("TEST_V0991734_FIXES: PASS");
   else
      Put_Line ("TEST_V0991734_FIXES: FAIL (" & Natural'Image (Failures) & ")");
   end if;
end Test_V0991734_Fixes;
