-------------------------------------------------------------------------------
--  Gate G9 / Phase 8 - core positional terms for the unified evaluation.
--
--  Search_Integration.Evaluate is material + tapered PST only (G2).  Phase 8
--  adds the classic positional terms here, one per gate step, each returning
--  a WHITE-RELATIVE score in centipawns that has already been interpolated
--  between its middlegame and endgame tables by the shared PeSTO game phase
--  (Pprechess2.Positional_Game_Phase), so a caller only has to add it.
--
--  Every term is symmetric by construction: a black feature subtracts exactly
--  what the mirrored white feature adds.
-------------------------------------------------------------------------------

package Eval_Terms is

   ---------------------------------------------------------------------------
   --  G10 / Phase 9: Evaluation Magnitudes & Parameterized Tuning Weights
   ---------------------------------------------------------------------------
   --  Display material values (centipawns)
   Pawn_Value_Cp        : constant Integer := 100;
   Knight_Value_Cp      : constant Integer := 320;
   Bishop_Value_Cp      : constant Integer := 330;
   Rook_Value_Cp        : constant Integer := 500;
   Queen_Value_Cp       : constant Integer := 900;
   Bishop_Pair_Bonus_Cp : constant Integer := 30;

   --  Default contempt (centipawns)
   Default_Contempt_Cp  : constant Integer := 0;

   --  Positional term weight tables
   Passed_MG : constant array (1 .. 8) of Integer := [0, 5, 10, 20, 35, 60, 100, 0];
   Passed_EG : constant array (1 .. 8) of Integer := [0, 10, 20, 40, 70, 120, 180, 0];

   Doubled_MG  : constant Integer := -12;
   Doubled_EG  : constant Integer := -24;
   Isolated_MG : constant Integer := -14;
   Isolated_EG : constant Integer := -18;

   Open_MG      : constant Integer := 25;
   Open_EG      : constant Integer := 12;
   Semi_Open_MG : constant Integer := 12;
   Semi_Open_EG : constant Integer := 6;

   Shield_MG   : constant Integer := 12;
   Shield_EG   : constant Integer := 2;
   Pressure_MG : constant Integer := 12;
   Pressure_EG : constant Integer := 2;

   --  Term 1 - passed pawns.  Rank-scaled bonus: the further advanced the
   --  passer the larger the bonus, and the endgame table is the larger of the
   --  two because passers decide endgames.
   function Passed_Pawns return Integer;

   --  Term 2 - doubled and isolated pawns.  Penalties: each extra pawn on a
   --  file is doubled, a pawn with no friendly pawn on either adjacent file is
   --  isolated.  Both are structural and hurt more once the pieces come off,
   --  so the endgame penalty is the larger one.
   function Doubled_Isolated_Pawns return Integer;

   --  Term 3 - rooks on open and semi-open files.  A rook's file with no
   --  pawn of either colour on it is open; with no friendly pawn but at
   --  least one enemy pawn it is semi-open.  Open is worth more than
   --  semi-open, and both are worth more in the middlegame.
   function Rook_Files return Integer;

   --  Term 5 - king safety (cheap version).  Per king: +1 for each friendly
   --  pawn on the king file or an adjacent file one or two ranks in front of
   --  it (the shield), and -1 for each of the four squares in front of the
   --  king (king square included) that the enemy attacks (the pressure).
   --  Shield and pressure are both middlegame-weighted; a bare king in the
   --  ending is normal and must not be scored.
   function King_Safety return Integer;

end Eval_Terms;
