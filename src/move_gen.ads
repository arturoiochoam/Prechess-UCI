--  Move_Gen: a complete, legal move generator + perft, kept strictly
--  separate from the legacy cascade (pprechess2) so the cascade's
--  move-selection semantics are untouched (N2). Its sole consumer is the
--  `go perft N` test facility in prechess_uci.adb.
--
--  Why it exists (P6): Pvalidade.Validade is a per-piece geometry oracle
--  with no castling branch, no en-passant (it routes empty targets to the
--  pawn-push branch), and no promotion concept. Perft needs all of those,
--  generated legally, so it gets its own generator + make/unmake here.
package Move_Gen is

   --  Leaf-count to Depth from the position in Pvalidade.Tabuleiro, side to
   --  move = White_To_Move. Uses its own copy-make on the global board and
   --  on Move_Validation's castling-rights/EP-square state; it does NOT
   --  touch the legacy search, the TT, or the repetition/draw history.
   function Perft (Depth : Natural; White_To_Move : Boolean) return Long_Long_Integer;

   --  Stockfish-style divide for `go perft N`: one "<ucimove> <count>" line
   --  per legal root move, then "perft <Depth> <total>". For debugging.
   procedure Perft_Divide (Depth : Positive; White_To_Move : Boolean);

end Move_Gen;
