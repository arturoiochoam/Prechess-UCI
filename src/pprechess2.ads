-------------------------------------------------------------------------------
--  PRECHESS UCI - QUALITATIVE CASCADE & 40-PLY MATERIAL EVALUATION ENGINE
--
--  Module:        Pprechess2
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        José Lauro Strapasson (Original 2001 Qualitative Engine)
--                 Arthur Matheus (40-Ply Extensions, Tapered Evaluation, UCI Bridge)
--  Date:          2001-2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Pprechess2` implements the core heuristic decision cascade of the Prechess
--  engine. Unlike traditional minimax alpha-beta engines, Prechess utilizes a
--  domain-specific qualitative cascade spanning 3 primary plies of tactical
--  foresight, coupled with a 40-ply alternating minimax material safety chain
--  (`Quarto_Lance` .. `Sexagesimo_Lance`, `seldepth 60`).
--
--  SEARCH HIERARCHY & STAGED TIERS:
--  - Ply 1: Computer trial root moves (64x64 matrix).
--  - Ply 2: Opponent immediate tactical and mate responses (`Mate`).
--  - Ply 3: Computer tactical counters, winning captures, and threats (`Mate_Ele2`).
--  - Plies 4..40: Deep alternating minimax material exchange verification.
--
--  SAFETY INVARIANTS:
--  - Zero Heap Allocation: 100% static BSS array and integer registers (`Storage_Error` immune).
--  - Deterministic Evaluation: Completely recursion-free, deterministic execution.
-------------------------------------------------------------------------------

package pprechess2 is

   ----------------------------------------------------------------------------
   --  TACTICAL THREAT & GAIN MATRICES (PLY 1..3)
   ----------------------------------------------------------------------------
   --  Exequemate: True if move forces immediate checkmate.
   Exequemate : array (1 .. 64, 1 .. 64) of Boolean;

   --  Pawn tactical matrices: Captures (Pega), Threats (Ameaca), Losses (Perde)
   Jogada_PegaP,   Jogada_AmeacaP,   Jogada_PerdeP   : array (1 .. 64, 1 .. 64) of Boolean;
   --  Bishop tactical matrices
   Jogada_PegaB,   Jogada_AmeacaB,   Jogada_PerdeB   : array (1 .. 64, 1 .. 64) of Boolean;
   --  Knight tactical matrices
   Jogada_PegaC,   Jogada_AmeacaC,   Jogada_PerdeC   : array (1 .. 64, 1 .. 64) of Boolean;
   --  Rook tactical matrices
   Jogada_PegaT,   Jogada_AmeacaT,   Jogada_PerdeT   : array (1 .. 64, 1 .. 64) of Boolean;
   --  Queen tactical matrices
   Jogada_PegaD,   Jogada_AmeacaD,   Jogada_PerdeD   : array (1 .. 64, 1 .. 64) of Boolean;
   --  King tactical matrices
   Jogada_PegaR,   Jogada_AmeacaR,   Jogada_PerdeR   : array (1 .. 64, 1 .. 64) of Boolean;

   --  Promotion prediction matrices
   Jogada_Promove_Maquina, Jogada_Promove_Humano     : array (1 .. 64, 1 .. 64) of Boolean;

   --  King check exposure & sliding ray alignment matrices
   Expoem_A_Xeque, Alinha                            : array (1 .. 64, 1 .. 64) of Boolean;

   ----------------------------------------------------------------------------
   --  SCRATCH REGISTERS (ZERO HEAP ALLOCATION)
   ----------------------------------------------------------------------------
   Posicao_Do_Rei        : Integer := 0;
   Posicao_Do_Rei_Dele   : Integer := 0;

   Temporario1,  Temporario2  : Integer;
   Temporario3,  Temporario4  : Integer;
   Temporario5,  Temporario6  : Integer;
   Temporario7,  Temporario8  : Integer;
   Temporario9,  Temporario10 : Integer;
   Temporario11, Temporario12 : Integer;
   Temporario13, Temporario14 : Integer;
   Temporario15, Temporario16 : Integer;
   Temporario17, Temporario18 : Integer;
   Temporario19, Temporario20 : Integer;
   Temporario21, Temporario22 : Integer;
   Temporario23, Temporario24 : Integer;
   Temporario25, Temporario26 : Integer;
   Temporario27, Temporario28 : Integer;
   Temporario29, Temporario30 : Integer;
   Temporario31, Temporario32 : Integer;
   Temporario33, Temporario34 : Integer;
   Temporario35, Temporario36 : Integer;
   Temporario37, Temporario38 : Integer;
   Temporario39, Temporario40 : Integer;
   Temporario41, Temporario42 : Integer;
   Temporario43, Temporario44 : Integer;
   Temporario45, Temporario46 : Integer;
   Temporario47, Temporario48 : Integer;
   Temporario49, Temporario50 : Integer;
   Temporario51, Temporario52 : Integer;
   Temporario53, Temporario54 : Integer;
   Temporario55, Temporario56 : Integer;
   Temporario57, Temporario58 : Integer;
   Temporario59, Temporario60 : Integer;
   Temporario61, Temporario62 : Integer;
   Temporario63, Temporario64 : Integer;
   Temporario65, Temporario66 : Integer;
   Temporario67, Temporario68 : Integer;
   Temporario69, Temporario70 : Integer;
   Temporario71, Temporario72 : Integer;
   Temporario73, Temporario74 : Integer;
   Temporario75, Temporario76 : Integer;
   Temporario77, Temporario78 : Integer;
   Temporario79, Temporario80 : Integer;
   Temporario81,  Temporario82  : Integer;
   Temporario83,  Temporario84  : Integer;
   Temporario85,  Temporario86  : Integer;
   Temporario87,  Temporario88  : Integer;
   Temporario89,  Temporario90  : Integer;
   Temporario91,  Temporario92  : Integer;
   Temporario93,  Temporario94  : Integer;
   Temporario95,  Temporario96  : Integer;
   Temporario97,  Temporario98  : Integer;
   Temporario99,  Temporario100 : Integer;
   Temporario101, Temporario102 : Integer;
   Temporario103, Temporario104 : Integer;
   Temporario105, Temporario106 : Integer;
   Temporario107, Temporario108 : Integer;
   Temporario109, Temporario110 : Integer;
   Temporario111, Temporario112 : Integer;
   Temporario113, Temporario114 : Integer;
   Temporario115, Temporario116 : Integer;
   Temporario117, Temporario118 : Integer;
   Temporario119, Temporario120 : Integer;

   Soma0L,  Soma1L,  Soma2L,  Soma3L  : Integer;
   Soma4L,  Soma5L,  Soma6L,  Soma7L  : Integer;
   Soma8L,  Soma9L,  Soma10L, Soma11L : Integer;
   Soma12L, Soma13L, Soma14L, Soma15L : Integer;
   Soma16L, Soma17L, Soma18L, Soma19L : Integer;
   Soma20L, Soma21L, Soma22L, Soma23L : Integer;
   Soma24L, Soma25L, Soma26L, Soma27L : Integer;
   Soma28L, Soma29L, Soma30L, Soma31L : Integer;
   Soma32L, Soma33L, Soma34L, Soma35L : Integer;
   Soma36L, Soma37L, Soma38L, Soma39L : Integer;
   Soma40L, Soma41L, Soma42L, Soma43L : Integer;
   Soma44L, Soma45L, Soma46L, Soma47L : Integer;
   Soma48L, Soma49L, Soma50L, Soma51L : Integer;
   Soma52L, Soma53L, Soma54L, Soma55L : Integer;
   Soma56L, Soma57L, Soma58L, Soma59L : Integer;
   Soma60L : Integer;

   ----------------------------------------------------------------------------
   --  DEEP 60-PLY SAFETY VERDICT MATRIX
   ----------------------------------------------------------------------------
   --  True iff an opponent recapture at ply 4 cannot be recovered by any
   --  computer tactical sequence extending up to ply 60.
   Jogada_Perde_Profunda : array (1 .. 64, 1 .. 64) of Boolean;

   ----------------------------------------------------------------------------
   --  DRAW PREVENTION & COUNTERS
   ----------------------------------------------------------------------------
   Contagem_Empate       : Integer := 0;
   Perigo_Empate         : Boolean;
   Zerar_Contagem_Empate : Boolean;
   Somar_Contagem_Empate : Boolean;
   BackupPeao            : Boolean;

   MataEle2              : array (1 .. 64, 1 .. 64) of Boolean;
   Lance_Do_Jogo         : Integer := 0;
   Numero_B_Inimigo      : Integer;

   --  Static root threat filter: protects against redundant threat-shuffling
   Raiz_Ja_Ameacado      : array (1 .. 64) of Boolean;

   --  Root move veto matrix: populated when short forced mates are detected
   Jogada_Vetada         : array (1 .. 64, 1 .. 64) of Boolean := (others => (others => False));

   --  Resulting chosen move indices (CC -> DD)
   cc, dd                : Integer := 1;

   ----------------------------------------------------------------------------
   --  LEGACY DATA HYGIENE & LEGALITY HELPERS (GATE G9)
   ----------------------------------------------------------------------------
   Casc_Pawn   : constant Integer := 100;
   Casc_Bishop : constant Integer := 300;
   Casc_Knight : constant Integer := 400;
   Casc_Rook   : constant Integer := 500;
   Casc_Queen  : constant Integer := 900;
   Casc_King   : constant Integer := 99900;

   function Move_Viable (White : Boolean) return Boolean;
   function Defender_Is_Legal (Def_Sq, Target_Sq : Integer; White : Boolean) return Boolean;
   function Protegida (B, Piece_Threshold : Integer) return Boolean;
   function Person_Defends (Sq : Integer) return Boolean;

   ----------------------------------------------------------------------------
   --  TAPERED POSITIONAL EVALUATION (PeSTO MG/EG Interpolation)
   ----------------------------------------------------------------------------
   --  Returns the non-linear game phase [0 .. 256] based on remaining non-pawn material.
   function Positional_Game_Phase return Integer
     with Post => Positional_Game_Phase'Result in 0 .. 256;

   --  Interpolates between Middlegame and Endgame scores given `Phase`.
   function Positional_Interpolate (MG, EG, Phase : Integer) return Integer
     with Pre => Phase in 0 .. 256;

   --  Evaluates the PeSTO piece-square table delta for `Piece` at `Sq`.
   function Positional_Test_Score (Piece, Sq, Phase : Integer) return Integer
     with Pre => Sq in 1 .. 64 and then Phase in 0 .. 256;

   --  Type declarations for external positional evaluation
   subtype Square_Index is Integer range 1 .. 64;
   subtype Phase_256 is Integer range 0 .. 256;
   type Piece_Code is (Pawn, Bishop, Knight, Rook, Queen, King);

   --  Returns the tapered piece-square score for `Piece` at `Sq`
   --  using the current root game phase. White-relative: positive for White pieces,
   --  negative for Black pieces. This is the main entry point for unified evaluation.
   function Positional_Score (Piece : Piece_Code; Sq : Square_Index) return Integer;

   --  Whole-board tapered PST sum. White_Relative = True returns the sum
   --  from White's perspective (own pieces +, enemy -), phase-blended via
   --  Positional_Game_Phase, in the SAME board frame Material uses. The
   --  caller (search_integration.Evaluate) adds this before the single
   --  Phase-4 side-to-move negation.
   function Positional_Sum (White_Relative : Boolean) return Integer;

   ----------------------------------------------------------------------------
   --  SEARCH EXECUTION ENTRY POINT
   ----------------------------------------------------------------------------
   --  Returns centipawn material value for a piece type.
   --  P=100, N=320, B=330, R=500, Q=900. King returns 0.
   function Material_Value (Piece : Piece_Code) return Integer;

   --  Executes the full 3-ply qualitative cascade + 32-ply material verification.
   --  Stores the optimal move in global variables `(cc, dd)`.
   procedure Prechess2;

   --  Executes only the decision cascade tiers using previously-computed tactical
   --  and safety flags, respecting updated Jogada_Vetada exclusions (S2).
   procedure Prechess2_Cascade_Only;

   --  0.9.9.17.20: drop the cached 64x64 move-geometry sweep. Call after any
   --  board mutation or color-frame flip; veto re-asks on an unchanged board
   --  then reuse the sweep instead of paying ~4096 Validade probes again.
   procedure Invalidate_Cascade_Cache;

end pprechess2;
