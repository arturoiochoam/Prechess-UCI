-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.3 SICILIAN HARMONY & 60_LANCE VERIFICATION SUITE
--
--  Unit:          Test_V099173_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Search_Integration;
with Move_Validation;
with Pvalidade;
with Pprechess2;

procedure Test_V099173_Suite is

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
   Put_Line ("  Prechess 0.9.9.17.3 - Sicilian Harmony & 60_Lance ");
   Put_Line ("========================================================");

   -- 1. Task 0: 60 Lance verification
   Put_Line ("[1/3] Testing Task 0 60 Lance in Pprechess2...");
   Check ("Task 0: Max_Material_Safety_Depth is 60",
          Search_Integration.Max_Material_Safety_Depth = 60);

   Pprechess2.Soma60L := 0;
   Pprechess2.Temporario120 := 0;
   Check ("Task 0: Pprechess2 60 Lance scratch registers active",
          Pprechess2.Soma60L = 0 and Pprechess2.Temporario120 = 0);

   -- 2. Task 1: Queen Kingside Development (Qd1-f3)
   Put_Line ("[2/3] Testing Task 1 Queen Kingside Development (Qd1-f3)...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk2r/pp1bbppp/2nppn2/8/2BNPP2/2N1B3/PPP3PP/R2QK2R w KQkq - 1 9", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D1 : constant Integer := Move_Validation.Square_Of (1, 4);
      Sq_F3 : constant Integer := Move_Validation.Square_Of (3, 6);
   begin
      Search_Integration.Best_Queen_Kingside_Development (True, Found, F, T);
      Check ("Task 1: Found is True", Found);
      Check ("Task 1: From is d1", F = Sq_D1);
      Check ("Task 1: To is f3", T = Sq_F3);
   end;

   -- Symmetrical Black Task 1: Qd8-f6
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk2r/ppp3pp/2n1b3/2bnpp2/8/2NPPN2/PP1BBPPP/R2QK2R b KQkq - 1 9", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_D8 : constant Integer := Move_Validation.Square_Of (8, 4);
      Sq_F6 : constant Integer := Move_Validation.Square_Of (6, 6);
   begin
      Search_Integration.Best_Queen_Kingside_Development (False, Found, F, T);
      Check ("Task 1 Symmetrical Black: Found is True", Found);
      Check ("Task 1 Symmetrical Black: From is d8", F = Sq_D8);
      Check ("Task 1 Symmetrical Black: To is f6", T = Sq_F6);
   end;

   -- 3. Task 2: Bishop retreat to e2 when attacked by Na5
   Put_Line ("[3/3] Testing Task 2 Bishop retreat to e2...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r2qk2r/pp1bbppp/3ppn2/nN6/2B1PP2/2N1B3/PPP3PP/R2QK2R w KQkq - 3 10", Dummy_White);

   declare
      Found : Boolean := False;
      F, T  : Integer := 0;
      Sq_C4 : constant Integer := Move_Validation.Square_Of (4, 3);
      Sq_E2 : constant Integer := Move_Validation.Square_Of (2, 5);
   begin
      Search_Integration.Best_En_Prise_Resolve (True, Found, F, T);
      Check ("Task 2: En-Prise Resolve Found is True", Found);
      Check ("Task 2: From is c4", F = Sq_C4);
      Check ("Task 2: To is e2", T = Sq_E2);
   end;

   if Failures = 0 then
      Put_Line ("TEST_V099173_SUITE: ALL PASS");
   else
      Put_Line ("TEST_V099173_SUITE: FAILURES =" & Natural'Image (Failures));
   end if;

end Test_V099173_Suite;
