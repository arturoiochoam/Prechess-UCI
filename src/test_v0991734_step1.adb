-------------------------------------------------------------------------------
--  PRECHESS UCI - STEP 1 VERIFY_MARGIN & MARGIN_CP PARAMETER SUITE
--
--  Unit:          Test_V0991734_Step1
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Validation;
with Search_Integration;
with Tactical_Search;
with Time_Management;

procedure Test_V0991734_Step1 is
   Failures   : Natural := 0;
   White_Move : Boolean := True;

   function Sq (File_Ch, Rank_Ch : Character) return Integer is
      F : constant Integer := Character'Pos (File_Ch) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Ch) - Character'Pos ('1') + 1;
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

   procedure Check (Label : String; Condition : Boolean) is
   begin
      if Condition then
         Put_Line ("PASS: " & Label);
      else
         Put_Line ("FAIL: " & Label);
         Failures := Failures + 1;
      end if;
   end Check;
   pragma Compile_Time_Error
     (Tactical_Search.Veto_Margin_Cp /= 25,
      "Veto_Margin_Cp default constant must be 25 (Step 4 sweep winner)");
begin
   Put_Line ("=== Step 1: Verify Margin_Cp Parameterization & Boundary Checks ===");

   --  1. Free pawn capture gap (~100 cp, < 250 cp):
   --     White passive Kf1 keeps chosen move at Margin_Cp => 250,
   --     but replaces at default Margin_Cp => 25.
   declare
      Res_Default : Tactical_Search.Verify_Result;
      Res_Strict  : Tactical_Search.Verify_Result;
      Res_Max_Opt : Tactical_Search.Verify_Result;
      Res_Huge    : Tactical_Search.Verify_Result;
      Res_Low     : Tactical_Search.Verify_Result;
   begin
      Search_Integration.Reset_Game;
      Check ("Parse Step 1 pawn-capture gap FEN",
             Search_Integration.Try_Parse_FEN
               ("8/5pk1/6p1/7p/3p4/8/2R2PPP/6K1 w - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_Default := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('g', '1'),
         Chosen_To     => Sq ('f', '1'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6);

      Search_Integration.Reset_Game;
      Check ("Parse Step 1 FEN for Margin_Cp => 250",
             Search_Integration.Try_Parse_FEN
               ("8/5pk1/6p1/7p/3p4/8/2R2PPP/6K1 w - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_Strict := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('g', '1'),
         Chosen_To     => Sq ('f', '1'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 250);

      Search_Integration.Reset_Game;
      Check ("Parse Step 1 FEN for Margin_Cp => 300 (max option)",
             Search_Integration.Try_Parse_FEN
               ("8/5pk1/6p1/7p/3p4/8/2R2PPP/6K1 w - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_Max_Opt := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('g', '1'),
         Chosen_To     => Sq ('f', '1'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 300);

      Search_Integration.Reset_Game;
      Check ("Parse Step 1 FEN for Margin_Cp => 10_000 (overflow guard)",
             Search_Integration.Try_Parse_FEN
               ("8/5pk1/6p1/7p/3p4/8/2R2PPP/6K1 w - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_Huge := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('g', '1'),
         Chosen_To     => Sq ('f', '1'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 10_000);

      Search_Integration.Reset_Game;
      Check ("Parse Step 1 FEN for Margin_Cp => 0",
             Search_Integration.Try_Parse_FEN
               ("8/5pk1/6p1/7p/3p4/8/2R2PPP/6K1 w - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_Low := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('g', '1'),
         Chosen_To     => Sq ('f', '1'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 0);

      Put_Line ("  Gap diagnostic: Chosen=" & Integer'Image (Res_Default.Chosen_Score) &
                " Best=" & Integer'Image (Res_Default.Best_Score) &
                " Depth=" & Integer'Image (Res_Default.Depth));
      Check ("Default Margin_Cp (25) replaces passive Kf1 when gap >= 25",
             Res_Default.Valid and then Res_Default.Replaced
             and then Res_Default.Best_Score - Res_Default.Chosen_Score >=
                        Tactical_Search.Veto_Margin_Cp);
      Check ("Strict Margin_Cp => 250 keeps Kf1 when gap < 250",
             Res_Strict.Valid and then not Res_Strict.Replaced);
      Check ("Max option Margin_Cp => 300 keeps Kf1 when gap < 300",
             Res_Max_Opt.Valid and then not Res_Max_Opt.Replaced);
      Check ("Huge Margin_Cp => 10_000 completes without overflow and keeps Kf1",
             Res_Huge.Valid and then not Res_Huge.Replaced);
      Check ("Zero Margin_Cp => 0 completes cleanly and replaces >= 0",
             Res_Low.Valid and then Res_Low.Replaced
             and then Res_Low.Best_Score >= Res_Low.Chosen_Score);
   end;

   --  2. Positional sub-100 cp gap (f2f3 vs center move in startpos depth 6):
   --     Margin_Cp => 100 keeps f2f3 (< 100 cp), while Margin_Cp => 20 replaces it.
   declare
      Res_100 : Tactical_Search.Verify_Result;
      Res_20  : Tactical_Search.Verify_Result;
   begin
      Search_Integration.Reset_Game;
      Check ("Parse Startpos FEN (100 cp threshold)",
             Search_Integration.Try_Parse_FEN
               ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_100 := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('f', '2'),
         Chosen_To     => Sq ('f', '3'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 100);

      Search_Integration.Reset_Game;
      Check ("Parse Startpos FEN (20 cp threshold)",
             Search_Integration.Try_Parse_FEN
               ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, True, False);
      Res_20 := Tactical_Search.Verify
        (White_To_Move => True,
         Chosen_From   => Sq ('f', '2'),
         Chosen_To     => Sq ('f', '3'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 20);

      Put_Line ("  Startpos diagnostic (f2f3): Chosen=" & Integer'Image (Res_100.Chosen_Score) &
                " Best20=" & Integer'Image (Res_20.Best_Score) &
                " Depth=" & Integer'Image (Res_20.Depth));
      Check ("Startpos f2f3 kept at Margin_Cp => 100 (sub-100 gap)",
             Res_100.Valid and then not Res_100.Replaced);
      Check ("Startpos f2f3 replaced at Margin_Cp => 20",
             Res_20.Valid and then Res_20.Replaced
             and then Res_20.Best_Score - Res_20.Chosen_Score >= 20);
   end;

   --  3. Colour-mirror symmetry (Black twin of #1):
   declare
      Res_B_Default : Tactical_Search.Verify_Result;
      Res_B_Strict  : Tactical_Search.Verify_Result;
   begin
      Search_Integration.Reset_Game;
      Check ("Parse Black-mirrored Step 1 FEN",
             Search_Integration.Try_Parse_FEN
               ("6k1/2r2ppp/8/3P4/7P/6P1/5PK1/8 b - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, False, False);
      Res_B_Default := Tactical_Search.Verify
        (White_To_Move => False,
         Chosen_From   => Sq ('g', '8'),
         Chosen_To     => Sq ('f', '8'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6);

      Search_Integration.Reset_Game;
      Check ("Parse Black-mirrored Step 1 FEN (Margin_Cp => 250)",
             Search_Integration.Try_Parse_FEN
               ("6k1/2r2ppp/8/3P4/7P/6P1/5PK1/8 b - - 0 1", White_Move));
      Tactical_Search.Clear_TT;
      Time_Management.Start_Search (0, 0, 0, 0, 0, 0, 6, False, False);
      Res_B_Strict := Tactical_Search.Verify
        (White_To_Move => False,
         Chosen_From   => Sq ('g', '8'),
         Chosen_To     => Sq ('f', '8'),
         Chosen_Promo  => 0,
         Budget_Ms     => 2500,
         Max_Depth     => 6,
         Margin_Cp     => 250);

      Check ("Black mirror replaces at default Margin_Cp (25)",
             Res_B_Default.Valid and then Res_B_Default.Replaced);
      Check ("Black mirror keeps Kf8 at Margin_Cp => 250 (G-mirror)",
             Res_B_Strict.Valid and then not Res_B_Strict.Replaced);
   end;

   if Failures = 0 then
      Put_Line ("TEST_V0991734_STEP1: PASS");
   else
      Put_Line ("TEST_V0991734_STEP1: FAIL (" & Natural'Image (Failures) & ")");
   end if;
end Test_V0991734_Step1;
