with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

--  Task-6 gate suite: legal move generation & special moves.
--  Castling (full FIDE conditions, positive and negative), en passant
--  (availability, pin exposure, lying-FEN guards), promotions and
--  underpromotions (input round-trips, capture-promotion, rights
--  revocation by promotion-capture on a rook home square), and the
--  pawn double-step blocking / legacy en-passant-avoidance rules in
--  the search's own move generator (Pvalidade.Validade).
procedure Test_Special_Moves is

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

   procedure Check_Int (Label : String; Got, Expected : Integer) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label & " (got" & Integer'Image (Got)
                   & ", expected" & Integer'Image (Expected) & ")");
         Failures := Failures + 1;
      end if;
   end Check_Int;

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White_To_Move);
   end Load;

begin
   Put_Line ("=== Castling: full FIDE legality ===");

   Load ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
   Check ("all clear: White O-O legal",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), True);
   Check ("all clear: White O-O-O legal",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), True);
   Check ("all clear: Black O-O legal",
          Move_Validation.Is_Castle_Legal (False, Kingside => True), True);
   Check ("all clear: Black O-O-O legal",
          Move_Validation.Is_Castle_Legal (False, Kingside => False), True);

   Load ("r3k2r/8/8/8/4r3/8/8/R3K2R w KQkq - 0 1");
   Check ("king in check: O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), False);
   Check ("king in check: O-O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), False);

   Load ("r3k2r/8/8/8/5r2/8/8/R3K2R w KQkq - 0 1");
   Check ("f1 attacked (through check): O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), False);
   Check ("f1 attacked does not affect O-O-O",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), True);

   Load ("r3k2r/8/8/8/6r1/8/8/R3K2R w KQkq - 0 1");
   Check ("g1 attacked (into check): O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), False);

   Load ("r3k2r/8/8/8/3r4/8/8/R3K2R w KQkq - 0 1");
   Check ("d1 attacked: O-O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), False);

   Load ("r3k2r/8/8/8/1r6/8/8/R3K2R w KQkq - 0 1");
   Check ("b1 attacked but empty: O-O-O STILL legal (FIDE subtlety)",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), True);

   Load ("r3k2r/8/8/8/8/8/8/RN2K2R w KQkq - 0 1");
   Check ("b1 occupied: O-O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), False);
   Check ("b1 occupied does not affect O-O",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), True);

   Load ("r3k2r/8/8/8/8/8/8/R3KB1R w KQkq - 0 1");
   Check ("f1 occupied: O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), False);

   Load ("4k3/8/8/8/8/8/8/4K3 w KQkq - 0 1");
   Check ("rights claimed but rooks absent: O-O forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), False);

   Load ("r6r/3k4/8/8/8/3K4/8/R6R w KQkq - 0 1");
   Check ("rights claimed but king displaced (lying FEN): forbidden",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), False);
   Check ("...queenside likewise",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), False);

   Load ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1");
   Search_Integration.Make_Move_UCI ("a1a2");
   Check ("Ra1-a2 revokes only White O-O-O",
          Move_Validation.Is_Castle_Legal (True, Kingside => False), False);
   Check ("...White O-O survives",
          Move_Validation.Is_Castle_Legal (True, Kingside => True), True);

   Put_Line ("=== En passant ===");

   Load ("4k3/8/8/pP6/8/8/8/4K3 w - a6 0 1");
   Check_Int ("EP available: candidate is the b5 pawn",
              Search_Integration.En_Passant_Candidate (True),
              Move_Validation.Square_Of (5, 2));

   Load ("4k3/8/8/p7/8/8/8/4K3 w - a6 0 1");
   Check_Int ("no adjacent friendly pawn: no candidate",
              Search_Integration.En_Passant_Candidate (True), 0);

   --  The classic horizontal-pin trap: after bxc6 e.p. BOTH pawns
   --  leave rank 5 and the g5 rook hits the a5 king.
   Load ("4k3/8/8/KPp3r1/8/8/8/8 w - c6 0 1");
   Check_Int ("EP exposing own king (horizontal pin): rejected",
              Search_Integration.En_Passant_Candidate (True), 0);

   Load ("4k3/8/8/8/pP6/8/8/4K3 b - b3 0 1");
   Check_Int ("Black EP available: candidate is the a4 pawn",
              Search_Integration.En_Passant_Candidate (False),
              Move_Validation.Square_Of (4, 1));

   --  Lying FENs must not corrupt the board (guards in the candidate).
   Load ("n3k3/8/8/1P6/8/8/8/4K3 w - a6 0 1");
   Check_Int ("lying FEN: EP square with no bypassed pawn: rejected",
              Search_Integration.En_Passant_Candidate (True), 0);

   Put_Line ("=== Promotions & underpromotions ===");

   Load ("4k3/4P3/8/8/8/8/8/4K3 w - - 0 1");
   Search_Integration.Make_Move_UCI ("e7e8q");
   Check_Int ("promotion to queen lands code 20",
              Pvalidade.Tabuleiro (Move_Validation.Square_Of (8, 5)), 20);

   Load ("4k3/4P3/8/8/8/8/8/4K3 w - - 0 1");
   Search_Integration.Make_Move_UCI ("e7e8r");
   Check_Int ("underpromotion to rook lands code 7",
              Pvalidade.Tabuleiro (Move_Validation.Square_Of (8, 5)), 7);

   Load ("4k3/4P3/8/8/8/8/8/4K3 w - - 0 1");
   Search_Integration.Make_Move_UCI ("e7e8b");
   Check_Int ("underpromotion to bishop lands code 3",
              Pvalidade.Tabuleiro (Move_Validation.Square_Of (8, 5)), 3);

   Load ("4k3/8/8/8/8/8/4p3/4K3 b - - 0 1");
   Search_Integration.Make_Move_UCI ("e2e1n");
   Check_Int ("Black underpromotion to knight lands code -4",
              Pvalidade.Tabuleiro (Move_Validation.Square_Of (1, 5)), -4);

   Load ("5r2/4P3/8/8/8/8/8/4K2k w - - 0 1");
   Search_Integration.Make_Move_UCI ("e7f8q");
   Check_Int ("capture-promotion: exf8=Q lands the queen",
              Pvalidade.Tabuleiro (Move_Validation.Square_Of (8, 6)), 20);
   Check_Int ("...and the captured rook is gone from e7",
              Pvalidade.Tabuleiro (Move_Validation.Square_Of (7, 5)), 0);

   Load ("r3k3/1P6/8/8/8/8/8/4K3 w q - 0 1");
   Search_Integration.Make_Move_UCI ("b7a8q");
   Check ("capture-promotion onto a8 revokes Black O-O-O right",
          Move_Validation.Castling_Rights_Bits = 0, True);

   Put_Line ("=== Search generator: pawn double-step rules ===");

   for I in 1 .. 64 loop Pvalidade.Tabuleiro (I) := 0; end loop;
   Pvalidade.Tabuleiro (5)  := 999;
   Pvalidade.Tabuleiro (61) := -999;
   Pvalidade.Tabuleiro (13) := 1; -- Pe2
   Check ("double step over empty e3: allowed",
          Pvalidade.Validade (13, 29), True);
   Pvalidade.Tabuleiro (21) := 4; -- own Ne3
   Check ("double step through own piece: forbidden",
          Pvalidade.Validade (13, 29), False);
   Pvalidade.Tabuleiro (21) := -4; -- enemy Ne3
   Check ("double step through enemy piece: forbidden",
          Pvalidade.Validade (13, 29), False);
   Pvalidade.Tabuleiro (21) := 0;
   Pvalidade.Tabuleiro (30) := -1; -- enemy Pf4, adjacent to e4
   Check ("legacy EP-avoidance: computer refuses capturable double step",
          Pvalidade.Validade (13, 29), False);

   New_Line;
   if Failures = 0 then
      Put_Line ("ALL SPECIAL-MOVE TESTS PASSED");
   else
      Put_Line ("FAILURES:" & Natural'Image (Failures));
   end if;
end Test_Special_Moves;
