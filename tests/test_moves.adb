with Ada.Text_IO; use Ada.Text_IO;
with Pvalidade;
with Move_Validation;
with Search_Integration;

--  Throwaway unit-test harness (not part of the shipped engine): drives
--  Search_Integration.Make_Move_UCI directly and dumps board/rights
--  state so castling, en passant and rights bookkeeping can be checked
--  without going through the UCI text protocol.
procedure Test_Moves is
   White_To_Move : Boolean;

   procedure Dump is
   begin
      for R in reverse 1 .. 8 loop
         for F in 1 .. 8 loop
            Put (Integer'Image (Pvalidade.Tabuleiro (Move_Validation.Square_Of (R, F))) & ASCII.HT);
         end loop;
         New_Line;
      end loop;
      Put_Line ("WK=" & Boolean'Image (Move_Validation.White_Castling_K)
                & " WQ=" & Boolean'Image (Move_Validation.White_Castling_Q)
                & " BK=" & Boolean'Image (Move_Validation.Black_Castling_K)
                & " BQ=" & Boolean'Image (Move_Validation.Black_Castling_Q)
                & " EP=" & Integer'Image (Move_Validation.En_Passant_Sq)
                & " Fifty=" & Integer'Image (Search_Integration.Fifty_Move_Counter)
                & " HistCount=" & Integer'Image (Search_Integration.History_Count));
   end Dump;

begin
   Put_Line ("=== Castling rook hop (White O-O) + rights revoked ===");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", White_To_Move);
   Search_Integration.Make_Move_UCI ("e1g1");
   Dump;
   Put_Line ("Expect: f1(=Square_Of(1,6)) holds rook(7), h1 empty, g1 holds king(999), WK=False WQ=False");
   New_Line;

   Put_Line ("=== En passant capture removes the passed pawn ===");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/8/8/3pP3/8/8/4K3 b - e3 0 1", White_To_Move);
   Search_Integration.Make_Move_UCI ("d4e3");
   Dump;
   Put_Line ("Expect: e3 holds black pawn(-1), e4 empty (captured pawn removed), d4 empty");
   New_Line;

   Put_Line ("=== Rook move alone revokes only that side's right ===");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", White_To_Move);
   Search_Integration.Make_Move_UCI ("h1h2"); -- kingside rook moves off its home square
   Dump;
   Put_Line ("Expect: WK=False WQ=True BK=True BQ=True");
   New_Line;

   Put_Line ("=== Underpromotion (input parsing) ===");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/4P3/8/8/8/8/8/4K3 w - - 0 1", White_To_Move);
   Search_Integration.Make_Move_UCI ("e7e8n");
   Dump;
   Put_Line ("Expect: e8 holds knight(4)");
   New_Line;

   Put_Line ("=== Threefold repetition (Ke1-e2-e1 / Ke8-e7-e8 x3) ===");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/8/8/8/8/8/4K3 w - - 0 1", White_To_Move);
   for Rep in 1 .. 2 loop
      Search_Integration.Make_Move_UCI ("e1e2");
      Search_Integration.Make_Move_UCI ("e8e7");
      Search_Integration.Make_Move_UCI ("e2e1");
      Search_Integration.Make_Move_UCI ("e7e8");
   end loop;
   Put_Line ("Is_Threefold_Repetition = " & Boolean'Image (Search_Integration.Is_Threefold_Repetition));
   Put_Line ("Expect: TRUE (start position has now recurred 3 times)");
   New_Line;

   Put_Line ("=== Fifty-move rule from a FEN halfmove clock near the limit ===");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("4k3/8/8/8/8/8/8/4K3 w - - 99 60", White_To_Move);
   Put_Line ("Is_Fifty_Move_Rule (halfmove=99) = " & Boolean'Image (Search_Integration.Is_Fifty_Move_Rule));
   Search_Integration.Make_Move_UCI ("e1e2"); -- king move: halfmove clock -> 100
   Put_Line ("Is_Fifty_Move_Rule (after one more non-pawn, non-capture move) = "
             & Boolean'Image (Search_Integration.Is_Fifty_Move_Rule));
   Put_Line ("Expect: FALSE then TRUE");

end Test_Moves;
