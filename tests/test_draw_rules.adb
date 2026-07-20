with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Pvalidade;

--  Rule-focused test suite for the FIDE draw rules and their edge
--  cases: threefold repetition (including what must NOT count as the
--  "same position": different castling rights, different en-passant
--  availability, different king placement), the 50-move rule's reset
--  conditions, and exhaustive insufficient-material combinations.
--  Throwaway harness in the spirit of test_moves.adb: drives
--  Search_Integration directly and prints PASS/FAIL per case.
procedure Test_Draw_Rules is

   White_To_Move : Boolean;
   Failures : Natural := 0;

   procedure Check (Label : String; Got, Expected : Boolean) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label & " (got " & Boolean'Image (Got)
                   & ", expected " & Boolean'Image (Expected) & ")");
         Failures := Failures + 1;
      end if;
   end Check;

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White_To_Move);
   end Load;

   procedure Play (Moves : String) is
      Start : Positive := Moves'First;
   begin
      for I in Moves'Range loop
         if Moves (I) = ' ' then
            Search_Integration.Make_Move_UCI (Moves (Start .. I - 1));
            Start := I + 1;
         end if;
      end loop;
      if Start <= Moves'Last then
         Search_Integration.Make_Move_UCI (Moves (Start .. Moves'Last));
      end if;
   end Play;

   function Insufficient (FEN : String) return Boolean is
   begin
      Load (FEN);
      return Search_Integration.Is_Insufficient_Material;
   end Insufficient;

begin
   Put_Line ("=== Threefold repetition: what counts as the same position ===");

   --  Genuine repetition: kings cycle home twice; the start position
   --  recurs three times with identical rights/EP/side.
   Load ("4k3/8/8/8/8/8/R7/4K3 w - - 0 1");
   Play ("e1e2 e8e7 e2e1 e7e8 e1e2 e8e7 e2e1 e7e8");
   Check ("genuine repetition (kings cycle x2) is threefold",
          Search_Integration.Is_Threefold_Repetition, True);

   --  Different KING placement is a different position (this was the
   --  king-hashing bug: six distinct positions used to count as one).
   Load ("4k3/8/8/8/8/8/R7/4K3 w - - 0 1");
   Play ("e1d1 e8d8 d1c1 d8c8 c1b1 c8b8");
   Check ("kings on different squares never repeat",
          Search_Integration.Is_Threefold_Repetition, False);

   --  Different CASTLING RIGHTS make a different position: after the
   --  rooks step out and back, the layout matches the start but the
   --  rights differ, so only the rights-less recurrences may count.
   Load ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
   Play ("a1a2 a8a7 a2a1 a7a8 a1a2 a8a7 a2a1 a7a8");
   Check ("same layout, changed castling rights: 2 equal + 1 different is NOT threefold",
          Search_Integration.Is_Threefold_Repetition, False);
   Play ("a1a2 a8a7 a2a1 a7a8");
   Check ("...but a third rights-less recurrence IS threefold",
          Search_Integration.Is_Threefold_Repetition, True);

   --  Different EN-PASSANT availability makes a different position:
   --  right after the double step the EP square is set; the identical
   --  layout reached later by king shuffling has no EP square.
   Load ("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1");
   Play ("e2e4 e8e7 e1e2 e7e8 e2e1");
   --  Layout now equals the post-e2e4 position, but EP e3 vs none:
   --  1 occurrence with EP + 1 without = no repetition at all yet.
   Check ("same layout, EP availability differs: not threefold",
          Search_Integration.Is_Threefold_Repetition, False);
   Play ("e8e7 e1e2 e7e8 e2e1 e8e7 e1e2 e7e8 e2e1");
   --  The EP-less version has now genuinely recurred three times.
   Check ("...but three EP-less recurrences ARE threefold",
          Search_Integration.Is_Threefold_Repetition, True);

   Put_Line ("=== 50-move rule: boundary and reset conditions ===");

   Load ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 98 60");
   Play ("e1g1"); -- castling: king move, no capture, no pawn -> +1
   Check ("halfmove 98 + castle = 99: not yet 50-move",
          Search_Integration.Is_Fifty_Move_Rule, False);
   Play ("a8b8"); -- quiet rook move -> 100
   Check ("halfmove 100 reached by quiet moves: 50-move rule fires",
          Search_Integration.Is_Fifty_Move_Rule, True);

   Load ("4k3/8/8/8/8/8/4P3/4K3 w - - 99 60");
   Play ("e2e3"); -- pawn move resets
   Check ("pawn move resets the 50-move counter",
          Search_Integration.Is_Fifty_Move_Rule, False);

   Load ("4k3/8/8/8/2r5/8/8/R3K3 w - - 99 60");
   Play ("a1a4"); -- wait: capture? a4 is empty; use a rook capture below
   Check ("quiet move at 99 -> 100: fires",
          Search_Integration.Is_Fifty_Move_Rule, True);
   Load ("4k3/8/8/8/r7/8/8/R3K3 w - - 99 60");
   Play ("a1a4"); -- RxR: capture resets
   Check ("capture resets the 50-move counter",
          Search_Integration.Is_Fifty_Move_Rule, False);

   Load ("4k3/8/8/pP6/8/8/8/4K3 w - a6 99 60");
   Play ("b5a6"); -- en passant: pawn move AND capture -> resets
   Check ("en-passant capture resets the 50-move counter",
          Search_Integration.Is_Fifty_Move_Rule, False);

   Put_Line ("=== Insufficient material: exhaustive combinations ===");

   Check ("K vs K",
          Insufficient ("4k3/8/8/8/8/8/8/4K3 w - - 0 1"), True);
   Check ("KB vs K (white bishop)",
          Insufficient ("4k3/8/8/8/8/8/2B5/4K3 w - - 0 1"), True);
   Check ("K vs KB (black bishop)",
          Insufficient ("2b1k3/8/8/8/8/8/8/4K3 w - - 0 1"), True);
   Check ("KN vs K (white knight)",
          Insufficient ("4k3/8/8/8/8/8/1N6/4K3 w - - 0 1"), True);
   Check ("K vs KN (black knight)",
          Insufficient ("1n2k3/8/8/8/8/8/8/4K3 w - - 0 1"), True);
   Check ("KNN vs K (white knights; per project spec)",
          Insufficient ("4k3/8/8/8/8/8/1N1N4/4K3 w - - 0 1"), True);
   Check ("K vs KNN (black knights; per project spec)",
          Insufficient ("1n1nk3/8/8/8/8/8/8/4K3 w - - 0 1"), True);
   Check ("KN vs KN (per project spec)",
          Insufficient ("1n2k3/8/8/8/8/8/1N6/4K3 w - - 0 1"), True);
   --  c1 is a dark square; f8 is a dark square: same color -> dead.
   Check ("KB vs KB, same-colored bishops",
          Insufficient ("4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1"), True);
   --  c1 dark, g8 light: opposite colors -> helpmate exists, NOT dead.
   Check ("KB vs KB, opposite-colored bishops",
          Insufficient ("4k1b1/8/8/8/8/8/8/2B1K3 w - - 0 1"), False);
   Check ("KQ vs K is sufficient",
          Insufficient ("4k3/8/8/8/8/8/8/3QK3 w - - 0 1"), False);
   Check ("KR vs K is sufficient",
          Insufficient ("4k3/8/8/8/8/8/8/R3K3 w - - 0 1"), False);
   Check ("KP vs K is sufficient (pawn can promote)",
          Insufficient ("4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"), False);
   Check ("KNN vs KN is sufficient (outside the drawn set)",
          Insufficient ("1n2k3/8/8/8/8/8/1N1N4/4K3 w - - 0 1"), False);
   Check ("KBB vs K is sufficient (two bishops mate)",
          Insufficient ("4k3/8/8/8/8/8/2B1B3/4K3 w - - 0 1"), False);
   Check ("KBN vs K is sufficient (bishop+knight mate)",
          Insufficient ("4k3/8/8/8/8/8/1NB5/4K3 w - - 0 1"), False);

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL DRAW-RULE TESTS PASSED");
   else
      Put_Line ("FAILURES:" & Natural'Image (Failures));
   end if;
end Test_Draw_Rules;
