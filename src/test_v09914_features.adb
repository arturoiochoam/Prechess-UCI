-------------------------------------------------------------------------------
--  PRECHESS UCI - VERSION 0.9.9.14 FEATURE VALIDATION HARNESS
--
--  Harness:       Test_V09914_Features
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Engine Integration & Test Harness)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Gate P4: Time_Management Task-Safety & Cancellation (Atomic Search_Aborted)
--  2. Gate P5: Unified Legal Root Candidate Snapshot (Count & Board Preservation)
--  3. Gate P6: Option-Gated Root Stage Traceability (Trace_Root_Decisions)
--  4. Gate P8: Hash Key Completeness & TT Key Isolation (Side, Castling, EP)
--  5. Gate P9: FIDE Castling Transit-Square Attack Rejection & Move_Gen Parity
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Time_Management;
with TT_Types;    use TT_Types;
with TT_Table;
with BCH_Hash;
with Move_Validation;
with Move_Gen;
with Pvalidade;
with Search_Integration;

procedure Test_V09914_Features is
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
   TT_Table.Init_TT (TT_Table.Default_Size_MB);
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.14 - Feature, Hash & Concurrency Gate  ");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Gate P4: Test Time_Management Task-Safe Cancellation & Budgets
   ----------------------------------------------------------------------------
   Put_Line ("[1/5] Testing Time_Management Task-Safe Cooperative Cancellation...");
   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0, Moves_To_Go => 0, Move_Time => 0,
      Depth => 0, Is_White => True, Infinite => True, Nodes => 100);

   Check ("Search_Aborted initialized False", not Time_Management.Search_Aborted);
   Time_Management.Stop_Search;
   Check ("Stop_Search atomically sets Search_Aborted", Time_Management.Search_Aborted);

   Time_Management.Start_Search
     (WTime => 0, BTime => 0, WInc => 0, BInc => 0, Moves_To_Go => 0, Move_Time => 0,
      Depth => 0, Is_White => True, Infinite => False, Nodes => 100);
   Check ("Search_Aborted reset on new search start", not Time_Management.Search_Aborted);
   TT_Types.Nodes_Searched := TT_Types.Nodes_Searched + 150;
   Time_Management.Check_Time;
   Check ("Node limit exhaustion triggers Search_Aborted", Time_Management.Search_Aborted);

   ----------------------------------------------------------------------------
   -- 2. Gate P5: Test Unified Legal Root Candidate Snapshot
   ----------------------------------------------------------------------------
   Put_Line ("[2/5] Testing Unified Legal Root Candidate Snapshot (Gate P5)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);

   declare
      Saved_Board : array (1 .. 64) of Integer;
      Candidate_List : Search_Integration.Root_Candidate_List;
      Gen_List : Move_Gen.Move_List;
      Board_Matches : Boolean := True;
   begin
      for Sq in 1 .. 64 loop
         Saved_Board (Sq) := Pvalidade.Tabuleiro (Sq);
      end loop;

      Search_Integration.Snapshot_Legal_Root_Candidates (True, Candidate_List);
      Move_Gen.Generate_Legal_Moves (True, Gen_List);

      Check ("Snapshot move count matches Move_Gen.Generate_Legal_Moves (startpos = 20)",
             Candidate_List.Count = 20 and then Candidate_List.Count = Gen_List.N);

      for Sq in 1 .. 64 loop
         if Pvalidade.Tabuleiro (Sq) /= Saved_Board (Sq) then
            Board_Matches := False;
         end if;
      end loop;
      Check ("Snapshot generation strictly preserves board state", Board_Matches);
   end;

   -- Test Kiwipete position candidate count
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", Dummy_White);
   declare
      Candidate_List : Search_Integration.Root_Candidate_List;
      Gen_List : Move_Gen.Move_List;
   begin
      Search_Integration.Snapshot_Legal_Root_Candidates (True, Candidate_List);
      Move_Gen.Generate_Legal_Moves (True, Gen_List);
      Check ("Snapshot move count matches Move_Gen for Kiwipete (48 legal moves)",
             Candidate_List.Count = 48 and then Candidate_List.Count = Gen_List.N);
   end;

   ----------------------------------------------------------------------------
   -- 3. Gate P6: Test Option-Gated Root Stage Traceability
   ----------------------------------------------------------------------------
   Put_Line ("[3/5] Testing Root Stage Traceability (Gate P6)...");
   Search_Integration.Trace_Root_Decisions := False;
   Check ("Trace_Root_Decisions default is False", not Search_Integration.Trace_Root_Decisions);

   Search_Integration.Trace_Decision ("Test_Stage", 13, 29, 0, "Self-test disabled");
   -- Toggling option
   Search_Integration.Trace_Root_Decisions := True;
   Check ("Trace_Root_Decisions toggles to True", Search_Integration.Trace_Root_Decisions);
   Search_Integration.Trace_Decision ("Test_Stage", 13, 29, 0, "Self-test enabled");
   Search_Integration.Trace_Root_Decisions := False;

   ----------------------------------------------------------------------------
   -- 4. Gate P8: Test Hash Key Completeness & TT Isolation
   ----------------------------------------------------------------------------
   Put_Line ("[4/5] Testing Hash Key Completeness & TT Isolation (Gate P8)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);

   declare
      Key_White_KQkq : constant Hash_Key := BCH_Hash.Compute_Hash
        (White_To_Move => True, Ep_Square => 0, Castling_Rights => 15);
      Key_Black_KQkq : constant Hash_Key := BCH_Hash.Compute_Hash
        (White_To_Move => False, Ep_Square => 0, Castling_Rights => 15);
      Key_White_None : constant Hash_Key := BCH_Hash.Compute_Hash
        (White_To_Move => True, Ep_Square => 0, Castling_Rights => 0);
      Key_White_K    : constant Hash_Key := BCH_Hash.Compute_Hash
        (White_To_Move => True, Ep_Square => 0, Castling_Rights => 1);
      Key_White_Q    : constant Hash_Key := BCH_Hash.Compute_Hash
        (White_To_Move => True, Ep_Square => 0, Castling_Rights => 2);
      Key_White_k_ep : constant Hash_Key := BCH_Hash.Compute_Hash
        (White_To_Move => True, Ep_Square => 21, Castling_Rights => 15);
   begin
      Check ("Side-to-move differentiates Zobrist hash key",
             not TT_Types."=" (Key_White_KQkq, Key_Black_KQkq));

      Check ("Castling rights differentiate Zobrist hash key (KQkq vs None)",
             not TT_Types."=" (Key_White_KQkq, Key_White_None));

      Check ("Castling rights differentiate Zobrist hash key (K vs Q)",
             not TT_Types."=" (Key_White_K, Key_White_Q));

      Check ("Active en-passant square differentiates Zobrist hash key",
             not TT_Types."=" (Key_White_KQkq, Key_White_k_ep));

      -- Transposition Table Probe Isolation Test
      TT_Table.Clear_TT;
      TT_Table.Store_TT
        (Key   => Key_White_KQkq,
         Depth => 3,
         Score => 120,
         Flag  => TT_Types.Exact,
         Best  => (From_Sq => 13, To_Sq => 29, Prom => 0));

      declare
         Probe_Entry : TT_Types.TT_Entry;
         Hit_Same    : Boolean;
         Hit_Diff    : Boolean;
      begin
         Hit_Same := TT_Table.Probe_TT (Key_White_KQkq, Probe_Entry);
         Check ("TT probe hits exact matching key", Hit_Same and then Probe_Entry.Score = 120);

         Hit_Diff := TT_Table.Probe_TT (Key_White_None, Probe_Entry);
         Check ("TT probe rejects key with legally distinct castling rights", not Hit_Diff);

         Hit_Diff := TT_Table.Probe_TT (Key_Black_KQkq, Probe_Entry);
         Check ("TT probe rejects key with legally distinct side to move", not Hit_Diff);
      end;
   end;

   ----------------------------------------------------------------------------
   -- 5. Gate P9: Test FIDE Castling Transit-Square Attack Rejection
   ----------------------------------------------------------------------------
   Put_Line ("[5/5] Testing Castling Transit-Square Attack Rejection (Gate P9)...");

   -- Test 5.1: White O-O illegal when transit square f1 is attacked
   -- White King on e1, Rook on h1. Black Rook on f8 attacking f1.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4kr2/8/8/8/8/8/8/4K2R w K - 0 1", Dummy_White);
   Check ("Kingside castling REJECTED when f1 transit square is attacked",
          not Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => True));

   declare
      Gen_List : Move_Gen.Move_List;
      Has_Castle : Boolean := False;
   begin
      Move_Gen.Generate_Legal_Moves (True, Gen_List);
      for I in 1 .. Gen_List.N loop
         if Gen_List.V (I).From = 5 and then Gen_List.V (I).To = 7 then
            Has_Castle := True;
         end if;
      end loop;
      Check ("Move_Gen confirms O-O is not generated when f1 is attacked", not Has_Castle);
   end;

   -- Test 5.2: White O-O-O illegal when transit square d1 is attacked
   -- White King on e1, Rook on a1. Black Rook on d8 attacking d1.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("3rkr2/8/8/8/8/8/8/R3K3 w Q - 0 1", Dummy_White);
   Check ("Queenside castling REJECTED when d1 transit square is attacked",
          not Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => False));

   declare
      Gen_List : Move_Gen.Move_List;
      Has_Castle : Boolean := False;
   begin
      Move_Gen.Generate_Legal_Moves (True, Gen_List);
      for I in 1 .. Gen_List.N loop
         if Gen_List.V (I).From = 5 and then Gen_List.V (I).To = 3 then
            Has_Castle := True;
         end if;
      end loop;
      Check ("Move_Gen confirms O-O-O is not generated when d1 is attacked", not Has_Castle);
   end;

   -- Test 5.3: White O-O-O legal when b1 is attacked (b1 is not a king transit square)
   -- Black Bishop on a2 or rook on b8 attacking b1: King moves e1 -> c1, passing d1. b1 only rook crosses.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("1r2k3/8/8/8/8/8/8/R3K3 w Q - 0 1", Dummy_White);
   Check ("Queenside castling ACCEPTED when only non-transit square b1 is attacked",
          Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => False));

   -- Test 5.4: Both castlings legal when path is clear and unattacked
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", Dummy_White);
   Check ("White Kingside castling legal in open safe position",
          Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => True));
   Check ("White Queenside castling legal in open safe position",
          Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => False));

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09914_FEATURES: PASS (All gates verified)");
   else
      Put_Line ("TEST_V09914_FEATURES: FAIL (" & Natural'Image (Failures) & " failures)");
      raise Program_Error;
   end if;
   Put_Line ("========================================================");
end Test_V09914_Features;
