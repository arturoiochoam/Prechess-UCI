-------------------------------------------------------------------------------
--  PRECHESS UCI - SEARCH INTEGRATION & HEURISTIC ARBITRATION BRIDGE
--
--  Module:        Search_Integration
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Engine Integration & Root Arbitration)
--  Date:          2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Search_Integration` orchestrates the interaction between the standard UCI
--  protocol loop and the internal search engines. It bridges FIDE draw detection,
--  triangular PV tracking, Static Exchange Evaluation (SEE), tactical root repair
--  stages (Stages 1..5), and coordinate mirroring.
--
--  ROOT ARBITRATION STAGES (in `Prechess_UCI.Select_Root_Move`):
--  - Stage 1:  En-Passant root override.
--  - Stage 1a: Tactical trap responses & pawn recapture resolutions.
--  - Stage 2:  Static Exchange Evaluation (SEE > 0) winning capture overrides.
--  - Stage 2a: King safety and Castling priority (O-O / O-O-O).
--  - Stage 2b: Queen tempo defense and natural piece development (e.g. 2...Nc6).
--  - Stage 2c..2i: Absolute pins, hanging piece resolves, quiet central play.
--  - Stage 3:  En-Prise piece relocation vs. hanging pawn resolve.
--  - Stage 4:  Non-losing equal captures (SEE >= 0).
--  - Stage 5:  Tablebase / heuristic endgame mating drive (KQ, KR, KBB, KP vs K).
--
--  FIDE DRAW ENGINE:
--  - 3-Fold Repetition detection over 4096-node Zobrist hash history.
--  - 50-Move rule counter (`Fifty_Move_Counter >= 100`).
--  - Insufficient material detection (KK, KNK, KBK, same-color KBBK).
-------------------------------------------------------------------------------

with TT_Types; use TT_Types;
with pprechess2;

package Search_Integration is

   ----------------------------------------------------------------------------
   --  FIDE GAME RULES & DRAW STATE
   ----------------------------------------------------------------------------
   Fifty_Move_Counter : Integer := 0;

   History_Max   : constant := 4096;
   type Hash_Array is array (1 .. History_Max) of Hash_Key;
   History       : Hash_Array := [others => 0];
   History_Count : Integer := 0;

   ----------------------------------------------------------------------------
   --  PERSPECTIVE & UCI TELEMETRY FLAGS
   ----------------------------------------------------------------------------
   Search_Is_Mirrored : Boolean := False;
   Report_For_Black   : Boolean := False;
   Suppress_Info      : Boolean := False;

   ----------------------------------------------------------------------------
   --  TRIANGULAR PV TABLE (ZERO HEAP ALLOCATION)
   ----------------------------------------------------------------------------
   Max_PV_Depth : constant := 64;
   type PV_Array is array (0 .. Max_PV_Depth, 0 .. Max_PV_Depth) of TT_Types.Move_Type
     with Alignment => 64;
   type PV_Length_Array is array (0 .. Max_PV_Depth) of Natural;

   PV_Table  : PV_Array := [others => [others => (From_Sq => 1, To_Sq => 1, Prom => 0)]];
   PV_Length : PV_Length_Array := [others => 0];

   procedure Clear_PV;
   procedure Set_PV_Move (Ply : Natural; From_Sq, To_Sq, Promo : Integer);
   procedure Report_PV (Depth, Seldepth, Score_Cp : Integer; PV : String;
                        Hashfull : Integer := -1);
   --  Hashfull < 0 falls back to TT_Table.Hash_Full_Permille.

   ----------------------------------------------------------------------------
   --  GAME LIFECYCLE & DRAW RECOGNITION
   ----------------------------------------------------------------------------
   procedure Reset_Game;
   procedure Push_State (H : Hash_Key; Half_Move : Integer);
   function Has_Legal_En_Passant_Capture
     (White_To_Move : Boolean;
      Ep            : Integer) return Boolean;
   function Is_Threefold_Repetition return Boolean;
   function Is_Fivefold_Repetition return Boolean;
   function Is_Fifty_Move_Rule return Boolean;
   function Is_Seventy_Five_Move_Rule return Boolean;
   function Is_Insufficient_Material return Boolean;
   function Is_Draw return Boolean;
   function Repetition_Count_After
     (White_To_Move : Boolean;
      From_Sq, To_Sq, Promo : Integer) return Integer;

   ----------------------------------------------------------------------------
   --  CONFIGURABLE HEURISTIC EVALUATION WEIGHTS (UCI TYPE SPIN OPTIONS)
   ----------------------------------------------------------------------------
   Castle_Bonus_Weight         : Integer := 80;
   Development_Bonus_Weight    : Integer := 40;
   Queen_Tempo_Penalty_Weight  : Integer := 60;
   Central_Pawn_Bonus_Weight   : Integer := 50;
   Defended_Piece_Bonus_Weight : Integer := 25;
   Mobility_Bonus_Weight       : Integer := 10;

   procedure Set_Heuristic_Option (Name : String; Value : Integer);

   ----------------------------------------------------------------------------
   --  GUARD NETWORK & SLIDING MOBILITY EVALUATION
   ----------------------------------------------------------------------------
   --  Counts how many friendly pieces/pawns are defended by friendly pieces/pawns.
   function Count_Protections (Side_White : Boolean) return Integer;

   --  Counts unblocked reachable ray squares for Bishops, Rooks, and Queens.
   function Compute_Mobility (Side_White : Boolean) return Integer;

   --  Computes net positional bonus in centipawns for guard network & mobility.
   function Side_Guard_Bonus_Cp (Side_White : Boolean) return Integer;
   function Side_Mobility_Bonus_Cp (Side_White : Boolean) return Integer;

   ----------------------------------------------------------------------------
   --  FEN & UCI POSITION TRANSLATION
   ----------------------------------------------------------------------------
   function Try_Parse_FEN
     (FEN                     : String;
      White_To_Move           : in out Boolean;
      Check_Opponent_In_Check : Boolean := True) return Boolean;
   procedure Parse_FEN (FEN : String; White_To_Move : out Boolean);

   procedure Make_Move_UCI
     (Move_Str               : String;
      Expected_White_To_Move : Boolean;
      Applied                : out Boolean);
   procedure Make_Move_UCI (Move_Str : String; Applied : out Boolean);
   procedure Make_Move_UCI (Move_Str : String);

   ----------------------------------------------------------------------------
   --  LIVE SEARCH REPORTING & TT CACHING
   ----------------------------------------------------------------------------
   procedure Report_UCI (From_Sq, To_Sq : Integer);

   --  H1 / B-M6: returns full 64-bit Zobrist hash of current root position
   --  including side-to-move, legal en-passant square, and castling rights bits.
   function Root_Position_Key (White_To_Move : Boolean) return TT_Types.Hash_Key;

   procedure Flip_Board;

   ----------------------------------------------------------------------------
   --  TACTICAL ROOT REPAIR & SEE ARBITRATION PROCEDURES
   ----------------------------------------------------------------------------
   function En_Passant_Candidate (White_To_Move : Boolean) return Integer;
   function Has_Forced_Mate_Within_Two (Attacker_White : Boolean) return Boolean;
   function Has_Opponent_Checking_Fork
     (White_To_Move : Boolean; Target_Sq : Integer) return Boolean;
   --  Returns True if any sound opponent reply creates a double attack (>= 2 targets
   --  or a pin through an attacked queen). If Target_Sq /= 0, requires that square
   --  as the first target; if Except_Sq /= 0, excludes Except_Sq from second-target counting.
   function Has_Opponent_Double_Attack
     (White_To_Move : Boolean;
      Target_Sq     : Integer := 0;
      Except_Sq     : Integer := 0) return Boolean;

   procedure Best_Castle
     (White_To_Move : Boolean; Found : out Boolean; Kingside : out Boolean);

   function Is_Castling_Into_Open_File
     (White_To_Move : Boolean; F, T : Integer) return Boolean;

   function Is_Flank_Gambit_Pawn_Offer
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   procedure Best_Winning_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Non_Losing_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  L2: A new caller must perform the same legality check the exchange
   --  plies do (e.g. Validade), or a pinned first capture scores as a win.
   function See_Gain
     (White_Captures : Boolean;
      From_Sq        : Integer;
      To_Sq          : Integer;
      Ep_Victim      : Integer := 0) return Integer;

   function Recapture_Preference
     (White_To_Move : Boolean; F, T : Integer) return Integer;

   function Raw_Piece_Value_Cp (Code : Integer) return Integer;

   function Max_Opponent_See
     (White_To_Move : Boolean;
      Except_Sq     : Integer := 0) return Integer;
   function Max_Opponent_See_After
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Integer;

   function Creates_Major_Threat
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  True iff the moved piece attacks the enemy queen from To_Sq after the
   --  move and the moved piece is not itself a queen (a genuine tempo gain).
   function Attacks_Enemy_Queen
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   --  Task 0: Deep Material Safety Extension to Ply 60 (60 _Lance, seldepth 60).
   --  Evaluates bounded alternating tactical exchange safety up to ply 60 with O(1) stack frame.
   Max_Material_Safety_Depth : constant := 60;
   function Is_Deep_Material_Safe_60
     (White_To_Move : Boolean;
      From_Sq       : Integer;
      To_Sq         : Integer) return Boolean;

   procedure Best_En_Prise_Resolve
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   function Is_Soft_Defend
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   procedure Best_Development_Vs_Hanging_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_King_Bishop_Pawn_Attacker_Trade
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Queenside_B_Pawn_Plan
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Pawn_Tempo_Kick
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Pawn_Tempo_Kick_Knight
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Knight_Outpost_Denial
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Central_Knight_Challenge
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Contested_File_Rook_Align
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Flank_Queen_Infiltration
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Cramped_Central_Pawn_Break
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Knight_Fork_Parry_Reposition
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Sicilian_Najdorf_Queen_Develop
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Pinning_Bishop_Kick
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Queen_Fork_Counter_Attack
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Attacked_Queen_Zwischenzug_Push
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Rook_Cramping_Pawn_Pressure
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_King_Unpin_Step
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Defend_Knight_C_Pawn_Fork
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Check_Evasion
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Central_King_Safety_Tuck
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Queen_Skewer_Escape
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_King_Pin_Shield
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Rook_Open_File_Facing_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Defend_Central_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Undefended_Major_Attack
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   function Allows_Major_Pin
     (White_To_Move : Boolean;
      Target_Sq     : Integer;
      Attacker_Sq   : Integer := 0) return Boolean;

   procedure Best_Passed_Pawn_Blockade_King_Step
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Passed_Pawn_Diagonal_Control
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Infiltration_Guard
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Endgame_Passed_Pawn_Advance
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Absolute_Pin_Save
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer;
      Hang_Sq       : out Integer);

   function Is_Self_Discovery
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   function Is_Bad_Queen_Sortie
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   function Is_Premature_Flank_Bishop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   function Is_Premature_Knight_Hop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   function Is_Early_Queen_Develop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   function Is_Passive_Early_Bishop
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   function Is_Square_Attacked_By_Pawn
     (Defender_White : Boolean; Sq : Integer) return Boolean;

   function Is_Square_Pawn_Kickable
     (Defender_White : Boolean; Sq : Integer) return Boolean;

   function Allows_Uncontested_Checking_Fork
     (Defender_White : Boolean) return Boolean;

   procedure Best_Natural_Development
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   function Is_Opening_Non_Tempo_Flank_Pawn_Push
     (White_To_Move : Boolean; From_Sq, To_Sq : Integer) return Boolean;

   procedure Best_Opening_Quiet_Alternative
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Central_Pawn_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Central_Pawn_Fork_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Central_Knight_Outpost_Pressure
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Broad_Pawn_Center_Occupation
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Wing_Pawn_Central_Counter
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_King_Indian_Central_Pawn_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Central_Pawn_Wedge_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Doubled_F_Pawn_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Benoni_Queenside_Break
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Task 1: Outpost knight leaping to rank 3/6 attacking enemy major piece (Rook/Queen) with tempo
   procedure Best_Outpost_Knight_Major_Attack
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Task 2: Defensive Queen centralization to e7/e2 connecting rooks against flank infiltrated Queen
   procedure Best_Queen_Central_Defense
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Queen_Kingside_Development
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Task 4: Preemptive extraction of rim knight threatened by impending pawn advance
   procedure Best_Rim_Knight_Preservation
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Task 6: Queenside flank pawn advance (a5-a4 / a4-a5) locking enemy queenside shelter
   procedure Best_Queenside_Flank_Pawn_Advance
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   --  Task 7: Rook seizing central open/semi-open file with counterplay under flank pawn attack
   procedure Best_Rook_Central_Open_File_Counterplay
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Advanced_Central_Pawn_Recapture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Advanced_Central_Pawn_Minor_Capture
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   function Has_Trapped_Piece_Threat
     (Defender_White : Boolean;
      Victim_Sq      : out Integer;
      Attacking_Pawn : out Integer;
      Push_Sq        : out Integer) return Boolean;

   function Has_Trapped_Piece_Threat
     (Defender_White : Boolean) return Boolean;

   procedure Best_Trapped_Piece_Rescue
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Opening_Trap_Response
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Rook_Attack_On_Infiltrated_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Ensnare_Overextended_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_King_Step_To_Trap_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Trapped_Infiltrated_Queen_Strike
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Fried_Liver_Central_Break
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Constricted_King_Escape
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Infiltrating_Rook_Attacker
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Reinforce_King_Bishop_Pawn
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Queen_Tempo_On_Queen
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   procedure Best_Development_Tempo_On_Queen
     (White_To_Move     : Boolean;
      Found             : out Boolean;
      From_Sq           : out Integer;
      To_Sq             : out Integer;
      Allow_Home_Queen  : Boolean := False);

   procedure Best_Solid_Response_To_Flank_Bishop
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   ----------------------------------------------------------------------------
   --  UNIFIED EVALUATOR & REPORTED SCORE CONTRACT (PHASE 1)
   ----------------------------------------------------------------------------
   --  Returns the static evaluation of the CURRENT internal board in
   --  centipawns, ALWAYS from White's perspective (positive = White better).
   --  Mate band is reserved: |result| >= Mate_Threshold encodes a mate score
   --  (see Score_To_UCI). Caller is responsible for side-to-move negation.
   Mate_Value     : constant := 32000;
   Mate_Threshold : constant := 31000;   -- scores at/above are "mate in N"
   function Evaluate return Integer;

   --  UCI score formatting: produces "score mate N" or "score cp N".
   function Signed_Mate_Plies_To_Moves (Score_Cp : Integer) return String;
   function Score_To_UCI (Score_Cp : Integer) return String;

   --  Checks if playing From_Sq -> To_Sq delivers immediate checkmate to opponent.
   function Move_Delivers_Checkmate
     (White_To_Move : Boolean;
      From_Sq, To_Sq, Promo : Integer) return Boolean;

   --  Task 3: Returns True if Defender_White has any legal FIDE move (including castling/EP).
   function Has_Any_Legal_Move (Defender_White : Boolean) return Boolean;

   --  Legacy shim; kept so existing callers compile unchanged.
   function Material_Score_Cp return Integer;
   function Endgame_Bonus_Cp return Integer;
   function Endgame_Is_Draw return Boolean;
   function King_Escape_Count (Defender_White : Boolean) return Integer;

   procedure Best_Endgame
     (White_To_Move : Boolean;
      Found         : out Boolean;
      From_Sq       : out Integer;
      To_Sq         : out Integer);

   ----------------------------------------------------------------------------
   --  UNIFIED LEGAL ROOT CANDIDATE SNAPSHOT & TRACE (ZOE TIER 1 - GATES P5, P6)
   ----------------------------------------------------------------------------
   type Root_Candidate is record
      From_Sq    : Integer := 0;
      To_Sq      : Integer := 0;
      Promo      : Integer := 0;
      Is_Legal   : Boolean := True;
      See_Score  : Integer := 0;
      Stage_Tag  : Integer := 0;
   end record;

   type Candidate_Array is array (1 .. 256) of Root_Candidate;
   type Root_Candidate_List is record
      Candidates : Candidate_Array;
      Count      : Natural := 0;
   end record;

   --  Generates unified snapshot of all legal root moves via Move_Gen
   --  without modifying board state or altering move selection.
   procedure Snapshot_Legal_Root_Candidates
     (White_To_Move : Boolean;
      List          : out Root_Candidate_List);

   --  UCI option Trace_Root_Decisions (default False).
   Trace_Root_Decisions : Boolean := False;

   --  Emits info string trace if Trace_Root_Decisions is True.
   procedure Trace_Decision
     (Stage_Name : String;
      From_Sq    : Integer;
      To_Sq      : Integer;
      Promo      : Integer := 0;
      Reason     : String  := "");

   --  Returns centipawn material value for a piece type.
   --  Exposed from Pprechess2 for public API access.
   function Material_Value (Piece : Pprechess2.Piece_Code) return Integer;

   --  Step 0b: Root-correction central guard and exemption list.
   --  Returns True when Stage is explicitly exempt from the Legacy-keep guard.
   function Is_Root_Correction_Exempt (Stage : String) return Boolean;

   --  Returns True when Legacy already resolves/avoids root hang threats
   --  (Legacy_Hang_Cp <= Root_Pre_Hang_Cp, safe, no Mate/Fork/Threat) and the
   --  proposed correction is neither an exempt stage nor a strictly better
   --  winning capture (Cand_Is_Capture and Cand_Gain_Cp > 0 > Legacy_Gain_Cp).
   function Should_Keep_Legacy_Over_Correction
     (Stage            : String;
      Legacy_Valid     : Boolean;
      Legacy_Hang_Cp   : Integer;
      Root_Pre_Hang_Cp : Integer;
      Legacy_Safe      : Boolean;
      Legacy_Mate      : Boolean;
      Legacy_Fork      : Boolean;
      Legacy_Threat    : Boolean;
      Legacy_Gain_Cp   : Integer;
      Cand_Is_Capture  : Boolean;
      Cand_Gain_Cp     : Integer) return Boolean;

end Search_Integration;
