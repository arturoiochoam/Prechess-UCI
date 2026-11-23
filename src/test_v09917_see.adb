-------------------------------------------------------------------------------
--  PRECHESS UCI - RECURSIVE CENTIPAWN STATIC EXCHANGE EVALUATION (SEE) HARNESS
--
--  Harness:       Test_V09917_See
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (Prechess UCI 0.9.9.17 Centipawn SEE Suite)
--  Date:          2026
--
--  SCOPE & TEST MATRICES (Assessment Finding B-C2 / Phase 1):
--  1. Simple winning captures: Q(+900), R(+500), B(+330), N(+320), P(+100).
--  2. Pinned defender rejection: An absolute-pinned piece cannot legally
--     recapture, so the attacked piece is scored as undefended (clean win).
--  3. Stand-pat cutoff: Minimax halts exchanges when recapturing loses material.
--  4. Equal trades: Defended piece trades of equal value return exactly 0 cp.
--  5. Losing sacrifices: Sacrificing a higher piece into a defended square returns
--     negative centipawns.
--  6. King-as-defender: King cannot recapture into check (defended piece);
--     King recaptures if the square is undefended.
--  7. X-ray battery: Removing a piece reveals sliding ray attackers behind it.
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Interfaces;  use Interfaces;
with Search_Integration;
with Move_Validation;
with Pvalidade;

procedure Test_V09917_See is

   Failures : Natural := 0;

   procedure Check (Label : String; Condition : Boolean; Actual : Integer := Integer'First) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         if Actual /= Integer'First then
            Put_Line ("FAIL: " & Label & " (actual=" & Integer'Image (Actual) & ")");
         else
            Put_Line ("FAIL: " & Label);
         end if;
         Failures := Failures + 1;
      end if;
   end Check;

   Dummy_White : Boolean;
   Val         : Integer;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17 - Recursive Centipawn SEE Gate      ");
   Put_Line ("========================================================");

   ----------------------------------------------------------------------------
   -- 1. Simple winning captures
   ----------------------------------------------------------------------------
   Put_Line ("[1/7] Testing simple undefended winning captures...");

   -- Queen takes Queen (+900)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/3q4/8/8/3Q4/4K2k w - - 0 1", Dummy_White);
   -- d2 (Sq 12) -> d5 (Sq 36)
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Undefended Queen capture returns +900", Val = 900);

   -- Queen takes Rook (+500)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/3r4/8/8/3Q4/4K2k w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Undefended Rook capture returns +500", Val = 500);

   -- Queen takes Bishop (+330)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/3b4/8/8/3Q4/4K2k w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Undefended Bishop capture returns +330", Val = 330);

   -- Queen takes Knight (+320)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/3n4/8/8/3Q4/4K2k w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Undefended Knight capture returns +320", Val = 320);

   -- Queen takes Pawn (+100)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/8/3p4/8/8/3Q4/4K2k w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Undefended Pawn capture returns +100", Val = 100);

   ----------------------------------------------------------------------------
   -- 2. Pinned defender does NOT count (Defect B-C2 repair)
   --    White Queen on d2, White Bishop on c4.
   --    Black King on f7, Black Rook on e6 (pinned along c4-e6-f7 diagonal).
   --    Black Pawn on d5.
   --    Rook on e6 geometrically attacks d5, but is pinned to the King on f7.
   --    Capturing d5 with Queen is a clean +100 win.
   ----------------------------------------------------------------------------
   Put_Line ("[2/7] Testing pinned defender rejection (Defect B-C2)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/5k2/4r3/3p4/2B5/8/3Q4/4K3 w - - 0 1", Dummy_White);
   -- White Qd2 (Rank 2, File 4) takes d5 (Rank 5, File 4)
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Pinned defender cannot recapture: pawn capture returns +100", Val = 100);

   ----------------------------------------------------------------------------
   -- 3. Equal trades (SEE = 0)
   --    White Pawn d4 takes Black Pawn e5, defended by Black Pawn d6.
   ----------------------------------------------------------------------------
   Put_Line ("[3/7] Testing equal trades (SEE = 0)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/3p4/4p3/3P4/8/8/4K2k w - - 0 1", Dummy_White);
   -- d4 (Rank 4, File 4) takes e5 (Rank 5, File 5)
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (4, 4), Move_Validation.Square_Of (5, 5));
   Check ("Defended pawn trade d4xe5 returns 0", Val = 0);

   ----------------------------------------------------------------------------
   -- 4. Losing sacrifice into defended square
   --    White Queen on e2 captures defended Black Pawn on e5.
   --    Black Pawn on d6 defends e5.
   ----------------------------------------------------------------------------
   Put_Line ("[4/7] Testing losing sacrifice into defended square...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/3p4/4p3/8/8/4Q3/4K2k w - - 0 1", Dummy_White);
   -- e2 (Rank 2, File 5) takes e5 (Rank 5, File 5)
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 5), Move_Validation.Square_Of (5, 5));
   Check ("Queen takes defended pawn returns -800 (100 - 900)", Val = -800);

   ----------------------------------------------------------------------------
   -- 5. Stand-pat cutoff
   --    White Bishop on c4, White Queen on d1.
   --    Black Pawn on d5, Black Queen on d8.
   --    White Bishop takes d5 (+100). If Black Queen takes d5 (+330 - 100 = 230),
   --    White Queen recaptures d1xd5 (+900 - 230 = 670 for White).
   --    Black stands pat rather than losing their Queen.
   --    Net result for White: +100 (win of the pawn).
   ----------------------------------------------------------------------------
   Put_Line ("[5/7] Testing stand-pat cutoff...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("3q3k/8/8/3p4/2B5/8/8/3Q2K1 w - - 0 1", Dummy_White);
   -- c4 (Rank 4, File 3) takes d5 (Rank 5, File 4)
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (4, 3), Move_Validation.Square_Of (5, 4));
   Check ("Stand-pat cuts off losing queen recapture: returns +100", Val = 100, Val);

   ----------------------------------------------------------------------------
   -- 6. King as defender
   ----------------------------------------------------------------------------
   Put_Line ("[6/7] Testing King-as-defender semantics...");

   -- King cannot recapture into check:
   -- White Queen on d2, White Pawn on e4. Black King on c6, Black Pawn on d5.
   -- Queen takes d5 (d5 defended by Pawn on e4). Black King cannot take Queen on d5.
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/2k5/3p4/4P3/8/3Q4/4K3 w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("King cannot recapture defended piece: returns +100", Val = 100);

   -- King CAN recapture if piece is undefended:
   -- White Queen on d2. Black King on c6, Black Pawn on d5.
   -- Queen takes d5 (undefended). Black King takes Queen (+900 - 100 = -800 for White).
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("8/8/2k5/3p4/8/8/3Q4/4K3 w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (5, 4));
   Check ("Undefended Queen on d5: King recaptures, returns -800", Val = -800);

   ----------------------------------------------------------------------------
   -- 7. X-ray attack unblocked during exchange
   --    White Rook on d1, White Rook on d2.
   --    Black Knight on d7, Black Rook on d8.
   --    d2xd7: White Rook takes Knight (+320). If Black Rook recaptures d8xd7 (+500 - 320 = 180),
   --    White Rook d1 (unblocked X-ray!) recaptures d1xd7 (+500 - 180 = +320).
   --    Without the unblocked X-ray rook on d1, White would lose material: 320 - 500 = -180.
   --    With the unblocked X-ray rook on d1, White wins the piece: net +320.
   ----------------------------------------------------------------------------
   Put_Line ("[7/7] Testing X-ray battery unblocking...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("3r3k/3n4/8/8/8/8/3R4/3R2K1 w - - 0 1", Dummy_White);
   -- d2 (Rank 2, File 4) takes d7 (Rank 7, File 4)
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (7, 4));
   Check ("X-ray battery unblocked: Rd2xNd7 backed by Rd1 returns +320", Val = 320, Val);

   -- Confirm without X-ray battery, White loses material:
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("3r3k/3n4/8/8/8/8/3R4/6K1 w - - 0 1", Dummy_White);
   Val := Search_Integration.See_Gain (True, Move_Validation.Square_Of (2, 4), Move_Validation.Square_Of (7, 4));
   Check ("Without X-ray battery: Rd2xNd7 returns -180", Val = -180, Val);

   ----------------------------------------------------------------------------
   -- 8. Scoring-side En Passant in SEE (Gate G4, B-C7)
   ----------------------------------------------------------------------------
   Put_Line ("[8/8] Testing scoring-side En Passant in SEE (Gate G4)...");

   -- 8a: Undefended EP capture scores +100
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/8/8/3pP3/8/8/8/6K1 w - d6 0 1", Dummy_White);
   Val := Search_Integration.See_Gain
     (White_Captures => True,
      From_Sq        => Move_Validation.Square_Of (5, 5), -- e5
      To_Sq          => Move_Validation.Square_Of (6, 4), -- d6
      Ep_Victim      => Move_Validation.Square_Of (5, 4)); -- d5
   Check ("Undefended EP capture returns +100", Val = 100, Val);

   -- 8b: EP capture exposing own King along rank is rejected (returns 0)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/8/8/r2pP2K/8/8/8/8 w - d6 0 1", Dummy_White);
   Val := Search_Integration.See_Gain
     (White_Captures => True,
      From_Sq        => Move_Validation.Square_Of (5, 5), -- e5
      To_Sq          => Move_Validation.Square_Of (6, 4), -- d6
      Ep_Victim      => Move_Validation.Square_Of (5, 4)); -- d5
   Check ("EP exposing own king along rank is rejected: returns 0", Val = 0, Val);

   -- 8c: EP target square attacked by enemy pawn recapture (equal trade, returns 0)
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN ("6k1/2p5/8/3pP3/8/8/8/6K1 w - d6 0 1", Dummy_White);
   Val := Search_Integration.See_Gain
     (White_Captures => True,
      From_Sq        => Move_Validation.Square_Of (5, 5), -- e5
      To_Sq          => Move_Validation.Square_Of (6, 4), -- d6
      Ep_Victim      => Move_Validation.Square_Of (5, 4)); -- d5
   Check ("EP with enemy pawn recapture returns 0", Val = 0, Val);

   ----------------------------------------------------------------------------
   -- SUMMARY
   ----------------------------------------------------------------------------
   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09917_SEE: PASS");
   else
      Put_Line ("TEST_V09917_SEE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V09917_See;
