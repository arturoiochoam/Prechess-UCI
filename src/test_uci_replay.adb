-------------------------------------------------------------------------------
--  PRECHESS UCI - UCI MOVE REPLAY & GAME SYNCHRONIZATION TEST SUITE
--
--  Harness:       Test_UCI_Replay
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Author:        Arthur Matheus (UCI Engine Integration & Test Harness)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Position Synchronization:
--     - Handling `position startpos moves ...` and `position fen ... moves ...`.
--  2. Turn-Explicit Move Rejection:
--     - Rejection of illegal / wrong-side tokens preventing board corruption.
--  3. Replay State Maintenance:
--     - Accurate tracking of castling rights, en-passant square, and 50-move counter.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_UCI_Replay is
   White_To_Move : Boolean;
   Applied       : Boolean;
   Failures      : Natural := 0;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White_To_Move);
   end Load;

   procedure Check_Rejected_Unchanged
     (Label                 : String;
      FEN                   : String;
      Move                  : String;
      Expected_White        : Boolean;
      From_Sq, To_Sq        : Integer;
      Expected_From_Piece   : Integer;
      Expected_To_Piece     : Integer)
   is
      Before_History : Integer;
   begin
      Load (FEN);
      Before_History := Search_Integration.History_Count;
      Search_Integration.Make_Move_UCI
        (Move, Expected_White_To_Move => Expected_White, Applied => Applied);
      Check (Label & " is rejected", not Applied);
      Check (Label & " leaves board unchanged",
             Pvalidade.Tabuleiro (From_Sq) = Expected_From_Piece
             and then Pvalidade.Tabuleiro (To_Sq) = Expected_To_Piece);
      Check (Label & " does not push history",
             Search_Integration.History_Count = Before_History);
   end Check_Rejected_Unchanged;

begin
   Put_Line ("=== UCI replay validation ===");

   Load ("4k3/8/8/8/8/8/8/4K3 w KQ - 0 1");
   Search_Integration.Make_Move_UCI ("e1g1", Applied);
   Check ("illegal castle with absent rook is rejected", not Applied);
   Check ("illegal castle does not move king",
          Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 5)) = 999);
   Check ("illegal castle does not invent rook",
          Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 6)) = 0
          and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 7)) = 0);

   Load ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
   Search_Integration.Make_Move_UCI ("e2e5", Applied);
   Check ("illegal pawn jump is rejected", not Applied);
   Check ("illegal pawn jump leaves pawn on e2",
          Pvalidade.Tabuleiro (Move_Validation.Square_Of (2, 5)) = 1
          and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (5, 5)) = 0);

   Load ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
   Search_Integration.Make_Move_UCI ("e7e5", Applied);
   Check ("legacy replay helper infers side and applies", Applied);

   Load ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
   declare
      Before_History : constant Integer := Search_Integration.History_Count;
   begin
      Search_Integration.Make_Move_UCI
        ("e7e5", Expected_White_To_Move => True, Applied => Applied);
      Check ("wrong-side replay token is rejected", not Applied);
      Check ("wrong-side replay leaves board unchanged",
             Pvalidade.Tabuleiro (Move_Validation.Square_Of (7, 5)) = -1
             and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (5, 5)) = 0
             and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (2, 5)) = 1);
      Check ("wrong-side replay does not push history",
             Search_Integration.History_Count = Before_History);
   end;

   Load ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
   Search_Integration.Make_Move_UCI ("e1d1", Applied);
   Check ("own-piece capture is rejected", not Applied);
   Check ("own-piece capture leaves king and queen in place",
          Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 5)) = 999
          and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 4)) = 20);

   Load ("4k3/8/8/8/pP6/8/8/4K3 b - b3 0 1");
   Search_Integration.Make_Move_UCI ("a4b3", Applied);
   Check ("legal en-passant replay is accepted", Applied);
   Check ("legal en-passant removes bypassed pawn",
          Pvalidade.Tabuleiro (Move_Validation.Square_Of (3, 2)) = -1
          and then Pvalidade.Tabuleiro (Move_Validation.Square_Of (4, 2)) = 0);

   Check_Rejected_Unchanged
     ("malformed short token", "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
      "e2", True, Move_Validation.Square_Of (2, 5),
      Move_Validation.Square_Of (4, 5), 1, 0);
   Check_Rejected_Unchanged
     ("malformed file token", "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
      "i2e4", True, Move_Validation.Square_Of (2, 5),
      Move_Validation.Square_Of (4, 5), 1, 0);
   Check_Rejected_Unchanged
     ("malformed rank token", "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
      "e9e4", True, Move_Validation.Square_Of (2, 5),
      Move_Validation.Square_Of (4, 5), 1, 0);
   Check_Rejected_Unchanged
     ("missing promotion suffix", "k7/4P3/8/8/8/8/8/4K3 w - - 0 1",
      "e7e8", True, Move_Validation.Square_Of (7, 5),
      Move_Validation.Square_Of (8, 5), 1, 0);
   Check_Rejected_Unchanged
     ("invalid promotion suffix", "k7/4P3/8/8/8/8/8/4K3 w - - 0 1",
      "e7e8x", True, Move_Validation.Square_Of (7, 5),
      Move_Validation.Square_Of (8, 5), 1, 0);
   Check_Rejected_Unchanged
     ("stray suffix on non-promotion", "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
      "e2e4q", True, Move_Validation.Square_Of (2, 5),
      Move_Validation.Square_Of (4, 5), 1, 0);
   Check_Rejected_Unchanged
     ("wrong-rank en-passant shape", "4k3/8/8/pP6/8/8/8/4K3 b - b4 0 1",
      "a5b4", False, Move_Validation.Square_Of (5, 1),
      Move_Validation.Square_Of (4, 2), -1, 0);

   New_Line;
   if Failures = 0 then
      Put_Line ("TEST_UCI_REPLAY: PASS");
   else
      Put_Line ("FAILURES:" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_UCI_Replay;
