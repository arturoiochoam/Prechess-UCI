-------------------------------------------------------------------------------
--  PRECHESS UCI - THREAT-SIDE & SCORING EN PASSANT SUITE (GATE G8)
--
--  Harness:       Test_V09917_EP
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI 0.9.9.17)
--  Date:          2026
--
--  SCOPE & TEST MATRICES (Assessment Section III-b, B-C7):
--  1. Opponent EP threat is enumerated and detected in Max_Opponent_See (+100 cp).
--  2. Own EP winning capture is enumerated and selected in Best_Winning_Capture.
--  3. Rank-exposure legality: EP that exposes the king to check is illegal on
--     both sides (White and Black) and never enumerated as a valid move or threat.
--  4. Lying FENs (EP target square claimed without bypassed pawn) are safely rejected.
--  5. Perft exactness on EP-heavy positions (Position 3 depth 1..5).
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Search_Integration;
with Move_Validation;
with Move_Gen;
with Pvalidade;

procedure Test_V09917_EP is

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
   Put_Line ("  Prechess 0.9.9.17 - En Passant Threat & Scan Gate     ");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Opponent EP threat is detected in Max_Opponent_See
   ----------------------------------------------------------------------------
   Put_Line ("[1/5] Testing opponent EP threat enumeration...");
   -- Position: White pawn on e5, Black pawn on d5, EP target square d6.
   -- Black is to move (White_To_Move = False). White is the opponent.
   -- White has en-passant threat e5xd6 e.p. winning the d5 pawn (+100 cp).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/3pP3/8/8/8/4K3 b - d6 0 1",
      Dummy_White);
   declare
      Threat : constant Integer := Search_Integration.Max_Opponent_See (White_To_Move => False);
   begin
      Check ("Opponent White EP threat e5xd6 is detected by Max_Opponent_See (+100 cp)",
             Threat = 100);
   end;

   -- Mirror position: Black pawn on e4, White pawn on d4, EP target square d3.
   -- White is to move (White_To_Move = True). Black is the opponent.
   -- Black has en-passant threat e4xd3 e.p. winning the d4 pawn (+100 cp).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/8/3Pp3/8/8/4K3 w - d3 0 1",
      Dummy_White);
   declare
      Threat : constant Integer := Search_Integration.Max_Opponent_See (White_To_Move => True);
   begin
      Check ("Opponent Black EP threat e4xd3 is detected by Max_Opponent_See (+100 cp)",
             Threat = 100);
   end;

   ----------------------------------------------------------------------------
   -- 2. Own EP selected when winning (Best_Winning_Capture)
   ----------------------------------------------------------------------------
   Put_Line ("[2/5] Testing own winning EP capture selection...");
   -- Position: White pawn on b5, Black pawn on a5, EP target a6.
   -- White is to move (White_To_Move = True).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/pP6/8/8/8/4K3 w - a6 0 1",
      Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
      Sq_A6 : constant Integer := Move_Validation.Square_Of (6, 1);
   begin
      Search_Integration.Best_Winning_Capture (True, Found, F, T);
      Check ("Own White winning EP b5xa6 is found by Best_Winning_Capture",
             Found and then F = Sq_B5 and then T = Sq_A6);
   end;

   -- Mirror: Black pawn on b4, White pawn on a4, EP target a3.
   -- Black is to move (White_To_Move = False).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/8/pP6/8/8/4K3 b - b3 0 1",
      Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
      Sq_A4 : constant Integer := Move_Validation.Square_Of (4, 1);
      Sq_B3 : constant Integer := Move_Validation.Square_Of (3, 2);
   begin
      Search_Integration.Best_Winning_Capture (False, Found, F, T);
      Check ("Own Black winning EP a4xb3 is found by Best_Winning_Capture",
             Found and then F = Sq_A4 and then T = Sq_B3);
   end;

   ----------------------------------------------------------------------------
   -- 3. King Rank-Exposure Legality Guard (both sides)
   ----------------------------------------------------------------------------
   Put_Line ("[3/5] Testing EP king rank-exposure legality guards...");
   -- Position: White Ka5, pawn b5, Black pawn c5, Rook g5. EP target c6.
   -- If b5xc6 e.p. is played, rank 5 opens and Rg5 checks Ka5! Illegal!
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("4k3/8/8/KPp3r1/8/8/8/8 w - c6 0 1",
      Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
      Sq_B5 : constant Integer := Move_Validation.Square_Of (5, 2);
      Sq_C6 : constant Integer := Move_Validation.Square_Of (6, 3);
      Gain  : constant Integer := Search_Integration.See_Gain (True, Sq_B5, Sq_C6);
      Opp_Threat : constant Integer := Search_Integration.Max_Opponent_See (False);
   begin
      Search_Integration.Best_Winning_Capture (True, Found, F, T);
      Check ("Rank-exposing White EP rejected in See_Gain (returns 0)", Gain = 0);
      Check ("Rank-exposing White EP rejected in Best_Winning_Capture", not Found);
      Check ("Rank-exposing White EP not counted as threat by Max_Opponent_See", Opp_Threat /= 100);
   end;

   -- Mirror: Black Ka4, pawn b4, White pawn c4, Rook g4. EP target c3.
   -- If b4xc3 e.p. is played, rank 4 opens and Rg4 checks Ka4! Illegal!
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/8/8/8/kpP3R1/8/8/4K3 b - c3 0 1",
      Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
      Sq_B4 : constant Integer := Move_Validation.Square_Of (4, 2);
      Sq_C3 : constant Integer := Move_Validation.Square_Of (3, 3);
      Gain  : constant Integer := Search_Integration.See_Gain (False, Sq_B4, Sq_C3);
      Opp_Threat : constant Integer := Search_Integration.Max_Opponent_See (True);
   begin
      Search_Integration.Best_Winning_Capture (False, Found, F, T);
      Check ("Rank-exposing Black EP rejected in See_Gain (returns 0)", Gain = 0);
      Check ("Rank-exposing Black EP rejected in Best_Winning_Capture", not Found);
      Check ("Rank-exposing Black EP not counted as threat by Max_Opponent_See", Opp_Threat /= 100);
   end;

   ----------------------------------------------------------------------------
   -- 4. Lying FEN Rejection
   ----------------------------------------------------------------------------
   Put_Line ("[4/5] Testing lying FEN rejection...");
   -- Lying FEN: EP square claimed (a6) but no bypassed pawn on a5!
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("n3k3/8/8/1P6/8/8/8/4K3 w - a6 0 1",
      Dummy_White);
   declare
      Found : Boolean;
      F, T  : Integer;
   begin
      Search_Integration.Best_Winning_Capture (True, Found, F, T);
      Check ("Lying FEN EP without bypassed pawn is rejected", not Found);
   end;

   ----------------------------------------------------------------------------
   -- 5. Perft Exactness on EP-Heavy Position 3
   ----------------------------------------------------------------------------
   Put_Line ("[5/5] Testing perft on EP-heavy position 3...");
   -- Standard CPW Position 3: 8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
      Dummy_White);
   declare
      Nodes_D1 : constant Long_Long_Integer := Move_Gen.Perft (1, True);
      Nodes_D2 : constant Long_Long_Integer := Move_Gen.Perft (2, True);
      Nodes_D3 : constant Long_Long_Integer := Move_Gen.Perft (3, True);
      Nodes_D4 : constant Long_Long_Integer := Move_Gen.Perft (4, True);
      Nodes_D5 : constant Long_Long_Integer := Move_Gen.Perft (5, True);
   begin
      Check ("Perft EP pos3 depth 1 = 14", Nodes_D1 = 14);
      Check ("Perft EP pos3 depth 2 = 191", Nodes_D2 = 191);
      Check ("Perft EP pos3 depth 3 = 2812", Nodes_D3 = 2812);
      Check ("Perft EP pos3 depth 4 = 43238", Nodes_D4 = 43238);
      Check ("Perft EP pos3 depth 5 = 674624", Nodes_D5 = 674624);
   end;

   ----------------------------------------------------------------------------
   -- SUMMARY
   ----------------------------------------------------------------------------
   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09917_EP: PASS");
   else
      Put_Line ("TEST_V09917_EP: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V09917_EP;
