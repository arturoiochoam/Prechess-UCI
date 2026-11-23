-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.21 BOUNDS CHECK & TELEMETRY TEST SUITE
--
--  Unit:          Test_V0991721_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with Move_Gen;
with Move_Validation;
with Search_Integration;
with TT_Table;
with TT_Types;   use TT_Types;

procedure Test_V0991721_Suite is

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

   function Sq (File_Char : Character; Rank_Char : Character) return Integer is
      F : constant Integer := Character'Pos (File_Char) - Character'Pos ('a') + 1;
      R : constant Integer := Character'Pos (Rank_Char) - Character'Pos ('0');
   begin
      return Move_Validation.Square_Of (R, F);
   end Sq;

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.21 - Bounds Check & Telemetry Suite ");
   Put_Line ("========================================================");

   -- 1. Test Move_Gen.Move_To_UCI coordinate bounds checking:
   --    Non-board coordinates (0000 / out-of-range) must return "0000" safely without crashing.
   Put_Line ("[1/4] Testing Move_To_UCI coordinate bounds validation...");
   declare
      Invalid_Move_1 : constant Move_Gen.Move_Rec := (From => 0, To => 0, Promo => 0);
      Invalid_Move_2 : constant Move_Gen.Move_Rec := (From => -1, To => 65, Promo => 0);
      Valid_Move_1   : constant Move_Gen.Move_Rec := (From => Sq ('e', '2'), To => Sq ('e', '4'), Promo => 0);
      Valid_Move_2   : constant Move_Gen.Move_Rec := (From => Sq ('e', '7'), To => Sq ('e', '8'), Promo => 20);
   begin
      Check ("Move_To_UCI (0,0) returns 0000", Move_Gen.Move_To_UCI (Invalid_Move_1) = "0000");
      Check ("Move_To_UCI (-1,65) returns 0000", Move_Gen.Move_To_UCI (Invalid_Move_2) = "0000");
      Check ("Move_To_UCI (e2,e4) returns e2e4", Move_Gen.Move_To_UCI (Valid_Move_1) = "e2e4");
      Check ("Move_To_UCI (e7,e8,q) returns e7e8q", Move_Gen.Move_To_UCI (Valid_Move_2) = "e7e8q");
   end;

   -- 2. Test Transposition Table hashfull telemetry:
   --    Hashfull permille calculation must start at 0 and track active generation entries.
   Put_Line ("[2/4] Testing Transposition Table Hashfull Telemetry...");
   declare
      Dummy_Move : constant Move_Type := (From_Sq => 1, To_Sq => 1, Prom => 0);
   begin
      TT_Table.Init_TT (1);
      Check ("TT Hashfull is 0 after fresh initialization", TT_Table.Hash_Full_Permille = 0);

      -- Store entries in sampled clusters
      for I in 0 .. 49 loop
         TT_Table.Store_TT
           (Key   => Hash_Key (I),
            Depth => 3,
            Score => 0,
            Flag  => Exact,
            Best  => Dummy_Move);
      end loop;
      Check ("TT Hashfull increases after storing entries", TT_Table.Hash_Full_Permille > 0);

      -- New generation resets effective occupancy
      TT_Table.New_Generation;
      Check ("TT Hashfull resets to 0 on new search generation", TT_Table.Hash_Full_Permille = 0);
   end;

   -- 3. Test Two Knights Fried Liver castling integrity (Move 9 O-O):
   Put_Line ("[3/4] Testing Two Knights Fried Liver castling availability...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("r1bq1b1r/ppp3pp/2n1k3/3np3/2B5/5Q2/PPPP1PPP/RNB1K2R w KQ - 2 9", Dummy_White);

   declare
      Can_Castle : constant Boolean :=
        Move_Validation.Is_Castle_Legal (White_To_Move => True, Kingside => True);
   begin
      Check ("Two Knights Fried Liver Move 9: Kingside castling is legal", Can_Castle);
      Check ("Two Knights Fried Liver Move 9: King square is e1", Move_Validation.Find_King (True) = Sq ('e', '1'));
   end;

   -- 4. Test Square Bound and Coordinate Helpers:
   Put_Line ("[4/4] Testing Square Bound and Mirror Helpers...");
   declare
      Sq_A1 : constant Integer := Sq ('a', '1');
      Sq_H8 : constant Integer := Sq ('h', '8');
      Sq_A8 : constant Integer := Sq ('a', '8');
   begin
      Check ("Square_Of (1, 1) = 1 (a1)", Sq_A1 = 1);
      Check ("Square_Of (8, 8) = 64 (h8)", Sq_H8 = 64);
      Check ("Mirror_Square (a1) = a8", Move_Validation.Mirror_Square (Sq_A1) = Sq_A8);
      Check ("Rank_Of (a1) = 1", Move_Validation.Rank_Of (Sq_A1) = 1);
      Check ("File_Of (a1) = 1", Move_Validation.File_Of (Sq_A1) = 1);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991721_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991721_Suite;
