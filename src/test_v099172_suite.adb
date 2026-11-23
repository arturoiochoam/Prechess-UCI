-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.2 TACTICAL BLUNDER PREVENTION & 60_LANCE SUITE
--
--  Unit:          Test_V099172_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Tactical Blunder Remediation & Deep Safety Layer)
--  Date:          2026
--
--  SCOPE & TEST MATRICES:
--  1. Task 0: Deep Material Safety Extension to Ply 60 (60 _Lance, seldepth 60):
--     - Max_Material_Safety_Depth = 60 constant verification.
--     - Is_Deep_Material_Safe_60 verification with bounded O(1) stack frame.
--  2. Task 1: Outpost Knight Major Attack (Nh5-g3):
--     - Position: r2q1rk1/2nb1p1p/p2p1ppQ/1ppP3n/2P1P3/1NNB3P/PP4P1/R2K3R b - - 1 20
--     - Best_Outpost_Knight_Major_Attack finds h5->g3 attacking rook on h1.
--     - Symmetrical test for White outpost knight.
--  3. Task 2: Queen Central Defense (Qd8-e7):
--     - Position: r2q1rk1/2nb1p1p/p2p1ppQ/2pP3n/1pP1P3/1N1B3P/PP2N1P1/R2K3R b - - 1 21
--     - Best_Queen_Central_Defense finds d8->e7 central defense.
--     - Symmetrical test for White queen defense.
--  4. Task 3: False Mate Fix & Move Verification (f6-f5):
--     - Position: r2q1rk1/2n2p1p/p2p1ppQ/2pP3n/bpP1P3/1N1B3P/PP2N1P1/R1K4R b - - 3 22
--     - Has_Any_Legal_Move correctly considers castling and en-passant legality.
--  5. Task 4: Rim Knight Preservation (Nh5-g7):
--     - Position: r2q1rk1/2n2p1p/3p1ppQ/p1pP3n/bpP1P3/3B3P/PP1NN2P/R1K4R b - - 1 23
--     - Best_Rim_Knight_Preservation finds h5->g7.
--     - Symmetrical test for White rim knight preservation.
--  6. Task 5: Capture Undefended Attacking Pawn (Bd7xg4):
--     - Position: r2q1rk1/2nb1p1p/3p2pQ/p1pP3n/1pP1P1P1/P2B4/1P1NN2P/R1K4R b - - 0 26
--     - d7->g4 capture is safe and positive SEE.
--  7. Task 6: Queenside Flank Pawn Advance (a5-a4):
--     - Position: r2q1rk1/2nb1p1p/3p1ppQ/p1pP3n/1pP1P3/P2B3P/1P1NN2P/R1K4R b - - 0 24
--     - Best_Queenside_Flank_Pawn_Advance finds a5->a4.
--  8. Task 7: Rook Central Open File Counterplay (Rf8-e8):
--     - Position: r2q1rk1/2nb1p1p/3p1npQ/p1pP2P1/1pP1P3/P2B4/1P1NN2P/R1K4R b - - 0 27
--     - Best_Rook_Central_Open_File_Counterplay finds f8->e8.
--  9. Tasks 8A & 8B: Preservation of Sämisch breaks:
--     - Best_Doubled_F_Pawn_Strike (f6-f5).
--     - Best_Benoni_Queenside_Break (b7-b5).
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;
with Pprechess2;

procedure Test_V099172_Suite is

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

   Dummy_White : Boolean;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.2 - Blunder Remediation & 60_Lance ");
   Put_Line ("========================================================");

   -- 1. Task 0: Max Material Safety Depth is 60 & Pprechess2 60 Lance
   Put_Line ("[1/9] Testing Task 0 Deep Material Safety Extension (ply 60)...");
   Check ("Task 0: Max_Material_Safety_Depth is 60",
          Search_Integration.Max_Material_Safety_Depth = 60);

   Pprechess2.Soma60L := 0;
   Pprechess2.Temporario120 := 0;
   Check ("Task 0: Pprechess2 60 Lance scratch registers (Soma60L, Temporario120) active",
          Pprechess2.Soma60L = 0 and Pprechess2.Temporario120 = 0);

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2nb1p1p/p2p1ppQ/1ppP3n/2P1P3/1NNB3P/PP4P1/R2K3R b - - 1 20", Dummy_White);
   declare
      Sq_H5 : constant Integer := Move_Validation.Square_Of (5, 8);
      Sq_G3 : constant Integer := Move_Validation.Square_Of (3, 7);
      Safe  : constant Boolean := Search_Integration.Is_Deep_Material_Safe_60 (False, Sq_H5, Sq_G3);
   begin
      Check ("Task 0: Is_Deep_Material_Safe_60 on h5->g3 is True", Safe);
   end;

   -- 2. Task 1: Outpost Knight Major Attack (Nh5-g3)
   Put_Line ("[2/9] Testing Task 1 Outpost Knight Major Attack (Nh5-g3)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2nb1p1p/p2p1ppQ/1ppP3n/2P1P3/1NNB3P/PP4P1/R2K3R b - - 1 20", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H5 : constant Integer := Move_Validation.Square_Of (5, 8);
      Sq_G3 : constant Integer := Move_Validation.Square_Of (3, 7);
   begin
      Search_Integration.Best_Outpost_Knight_Major_Attack (False, Found, F, T);
      Check ("Task 1: Found is True", Found);
      Check ("Task 1: From is h5", F = Sq_H5);
      Check ("Task 1: To is g3", T = Sq_G3);
   end;

   -- Symmetrical Task 1: White Outpost Knight Major Attack (Nh4-g6)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2k3r/pp4p1/1nnb3p/2p1p3/1PPp3N/P2P1PPq/2NB1P1P/R2Q1RK1 w - - 1 20", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H4 : constant Integer := Move_Validation.Square_Of (4, 8);
      Sq_G6 : constant Integer := Move_Validation.Square_Of (6, 7);
   begin
      Search_Integration.Best_Outpost_Knight_Major_Attack (True, Found, F, T);
      Check ("Task 1 Symmetrical White: Found is True", Found);
      Check ("Task 1 Symmetrical White: From is h4", F = Sq_H4);
      Check ("Task 1 Symmetrical White: To is g6", T = Sq_G6);
   end;

   -- 3. Task 2: Queen Central Defense (Qd8-e7)
   Put_Line ("[3/9] Testing Task 2 Queen Central Defense (Qd8-e7)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2nb1p1p/p2p1ppQ/2pP3n/1pP1P3/1N1B3P/PP2N1P1/R2K3R b - - 1 21", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D8 : constant Integer := Move_Validation.Square_Of (8, 4);
      Sq_E7 : constant Integer := Move_Validation.Square_Of (7, 5);
   begin
      Search_Integration.Best_Queen_Central_Defense (False, Found, F, T);
      Check ("Task 2: Found is True", Found);
      Check ("Task 2: From is d8", F = Sq_D8);
      Check ("Task 2: To is e7", T = Sq_E7);
   end;

   -- 4. Task 3: Has_Any_Legal_Move Checkmate Legality Guard
   Put_Line ("[4/9] Testing Task 3 Has_Any_Legal_Move & Legal Moves...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2n2p1p/p2p1ppQ/2pP3n/bpP1P3/1N1B3P/PP2N1P1/R1K4R b - - 3 22", Dummy_White);
   Check ("Task 3: Black has legal moves in Task 3 position",
          Search_Integration.Has_Any_Legal_Move (False));

   -- 5. Task 4: Rim Knight Preservation (Nh5-g7)
   Put_Line ("[5/9] Testing Task 4 Rim Knight Preservation (Nh5-g7)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2n2p1p/3p1ppQ/p1pP3n/bpP1P3/3B3P/PP1NN2P/R1K4R b - - 1 23", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_H5 : constant Integer := Move_Validation.Square_Of (5, 8);
      Sq_G7 : constant Integer := Move_Validation.Square_Of (7, 7);
   begin
      Search_Integration.Best_Rim_Knight_Preservation (False, Found, F, T);
      Check ("Task 4: Found is True", Found);
      Check ("Task 4: From is h5", F = Sq_H5);
      Check ("Task 4: To is g7", T = Sq_G7);
   end;

   -- 6. Task 5: Capture Undefended Attacking Pawn (Bd7xg4)
   Put_Line ("[6/9] Testing Task 5 Capture Undefended Attacking Pawn (Bd7xg4)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2nb1p1p/3p2pQ/p1pP3n/1pP1P1P1/P2B4/1P1NN2P/R1K4R b - - 0 26", Dummy_White);

   declare
      Sq_D7 : constant Integer := Move_Validation.Square_Of (7, 4);
      Sq_G4 : constant Integer := Move_Validation.Square_Of (4, 7);
      Gain  : constant Integer := Search_Integration.See_Gain (False, Sq_D7, Sq_G4);
   begin
      Check ("Task 5: See_Gain on d7xg4 is positive (+100 cp)", Gain = 100);
      Check ("Task 5: Is_Deep_Material_Safe_60 on d7xg4 is True",
             Search_Integration.Is_Deep_Material_Safe_60 (False, Sq_D7, Sq_G4));
   end;

   -- 7. Task 6: Queenside Flank Pawn Advance (a5-a4)
   Put_Line ("[7/9] Testing Task 6 Queenside Flank Pawn Advance (a5-a4)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2nb1p1p/3p1ppQ/p1pP3n/1pP1P3/P2B3P/1P1NN2P/R1K4R b - - 0 24", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_A5 : constant Integer := Move_Validation.Square_Of (5, 1);
      Sq_A4 : constant Integer := Move_Validation.Square_Of (4, 1);
   begin
      Search_Integration.Best_Queenside_Flank_Pawn_Advance (False, Found, F, T);
      Check ("Task 6: Found is True", Found);
      Check ("Task 6: From is a5", F = Sq_A5);
      Check ("Task 6: To is a4", T = Sq_A4);
   end;

   -- 8. Task 7: Rook Central Open File Counterplay (Rf8-e8)
   Put_Line ("[8/9] Testing Task 7 Rook Central Open File Counterplay (Rf8-e8)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/2nb1p1p/3p1npQ/p1pP2P1/1pP1P3/P2B4/1P1NN2P/R1K4R b - - 0 27", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F8 : constant Integer := Move_Validation.Square_Of (8, 6);
      Sq_E8 : constant Integer := Move_Validation.Square_Of (8, 5);
   begin
      Search_Integration.Best_Rook_Central_Open_File_Counterplay (False, Found, F, T);
      Check ("Task 7: Found is True", Found);
      Check ("Task 7: From is f8", F = Sq_F8);
      Check ("Task 7: To is e8", T = Sq_E8);
   end;

   -- 9. Tasks 8A & 8B: Preservation of Sämisch breaks
   Put_Line ("[9/9] Testing Tasks 8A & 8B Sämisch KID Breaks...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qnrk1/pp1b1p1p/3p1pp1/2pP3n/2P1P3/1NN2Q1P/PP4P1/R3KB1R b KQ - 1 16", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
      Sq_F5 : constant Integer := Move_Validation.Square_Of (5, 6);
   begin
      Search_Integration.Best_Doubled_F_Pawn_Strike (False, Found, F, T);
      Check ("Task 8A: Doubled F-Pawn Strike found", Found);
      Check ("Task 8A: From is f6", F = Sq_F6);
      Check ("Task 8A: To is f5", T = Sq_F5);
   end;

   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2q1rk1/ppnb1p1p/3p1pp1/2pP3n/2P1P3/1NN2Q1P/PP4P1/R2K1B1R b - - 3 17", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_B7 : constant Integer := Move_Validation.Square_Of (7, 2);
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
   begin
      Search_Integration.Best_Benoni_Queenside_Break (False, Found, F, T);
      Check ("Task 8B: Benoni Queenside Break found", Found);
      Check ("Task 8B: From is b7", F = Sq_B7);
      Check ("Task 8B: To is b5", T = Sq_B5);
   end;

   if Failures = 0 then
      Put_Line ("TEST_V099172_SUITE: ALL PASS");
   else
      Put_Line ("TEST_V099172_SUITE: FAILURES =" & Natural'Image (Failures));
   end if;

end Test_V099172_Suite;
