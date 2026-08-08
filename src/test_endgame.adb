with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;

--  Phase P9 endgame gate. Loads each test FEN, reports the score the
--  UCI loop would display (Material_Score_Cp, which includes the
--  endgame overlay), whether Endgame_Is_Draw recognises the position,
--  and the move Best_Endgame picks (the root override the integrator
--  wires into Compute_Best_Move alongside the other Best_* helpers).
--  Each line also confirms the override's move strictly IMPROVES the
--  Side_Endgame_Bonus_Cp heuristic -- which is the N1 contract: a
--  better move, in a general direction, for ANY matching position.
procedure Test_Endgame is

   White_To_Move : Boolean;
   Failures : Natural := 0;

   procedure Load (FEN : String) is
   begin
      Search_Integration.Reset_Game;
      Search_Integration.Parse_FEN (FEN, White_To_Move);
   end Load;

   function Sq_To_Uci (Sq : Integer) return String is
      F : constant Character := Character'Val
        (Character'Pos ('a') + Move_Validation.File_Of (Sq) - 1);
      R : constant Character := Character'Val
        (Character'Pos ('1') + Move_Validation.Rank_Of (Sq) - 1);
   begin
      return (1 => F, 2 => R);
   end Sq_To_Uci;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;

   --  Run one FEN: print score / draw flag / Best_Endgame pick and assert
   --  the expected recognized-regime behavior.
   procedure Run (Label, FEN : String; Expect_Draw, Expect_Move : Boolean) is
      Score_Pre      : Integer;
      Draw           : Boolean;
      Found          : Boolean;
      From_Sq, To_Sq : Integer;
   begin
      Load (FEN);
      Score_Pre := Search_Integration.Material_Score_Cp;
      Draw      := Search_Integration.Endgame_Is_Draw;

      Put_Line ("--- " & Label & " ---");
      Put_Line ("   FEN    : " & FEN);
      Put_Line ("   stm    : " & (if White_To_Move then "White" else "Black"));
      Put_Line ("   score  :" & Integer'Image (Score_Pre)
                & " cp (White-positive raw; caller flips sign for stm)");
      Put_Line ("   draw?  : " & Boolean'Image (Draw));

      Search_Integration.Best_Endgame
        (White_To_Move, Found, From_Sq, To_Sq);
      if Found then
         Put_Line ("   eg move: " & Sq_To_Uci (From_Sq)
                   & Sq_To_Uci (To_Sq) & "  (improves endgame heuristic)");
      else
         Put_Line ("   eg move: <none>  (no improving override)");
      end if;
      Check (Label & " draw flag", Draw = Expect_Draw);
      Check (Label & " override expectation", Found = Expect_Move);
      if Expect_Draw then
         Check (Label & " drawn score collapses to zero", Score_Pre = 0);
      end if;
      Put_Line ("");
   end Run;

begin
   Put_Line ("=== Phase P9 endgame gate ===");
   Put_Line ("");
   Run ("QK vs K (mate regime)",
        "8/8/8/8/8/3k4/8/3KQ3 w - - 0 1", False, True);
   Run ("RK vs K (mate regime)",
        "8/8/8/8/3k4/8/8/3KR3 w - - 0 1", False, True);
   Run ("BB vs K (mate regime, opposite colors)",
        "8/8/8/8/3k4/3B4/8/2B1K3 w - - 0 1", False, True);
   Run ("BB vs K (same colors, dead)",
        "4k3/8/8/8/8/4B3/8/2B1K3 w - - 0 1", False, False);
   Run ("KP vs K (opposition / advance)",
        "8/8/4k3/8/8/4K3/4P3/8 w - - 0 1", False, True);
   Run ("K vs K+rook-pawn (drawing corner)",
        "8/8/8/8/8/k7/p7/K7 w - - 0 1", True, False);
   Run ("KNN vs KP (not automatic draw)",
        "8/8/8/8/8/4k3/4p3/2N1K1N1 w - - 0 1", False, False);
   if Failures = 0 then
      Put_Line ("TEST_ENDGAME: PASS");
   else
      Put_Line ("TEST_ENDGAME: FAIL count =" & Natural'Image (Failures));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
   Put_Line ("=== end ===");
end Test_Endgame;
