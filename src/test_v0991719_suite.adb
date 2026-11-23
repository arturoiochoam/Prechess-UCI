-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.19 TT AUDIT & ZOBRIST HASH TEST SUITE
--
--  Unit:          Test_V0991719_Suite
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT Community / FSF GCC (-gnat2022)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Text_IO; use Ada.Text_IO;
with TT_Table;
with TT_Types;   use TT_Types;
with BCH_Hash;
with Move_Validation;
with Search_Integration;

procedure Test_V0991719_Suite is

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
   Move_None   : constant Move_Type := (From_Sq => 1, To_Sq => 1, Prom => 0);

begin
   Put_Line ("========================================================");
   Put_Line ("  Prechess 0.9.9.17.19 - TT Audit & Zobrist Hash Suite  ");
   Put_Line ("========================================================");

   -- 1. Test Transposition Table Store and Probe with Generation Stamping:
   Put_Line ("[1/4] Testing TT Store, Probe, and Generation Stamping...");
   TT_Table.Init_TT (1);
   declare
      Key_1     : constant Hash_Key := 987654321;
      Entry_Out : TT_Entry;
      Hit       : Boolean;
   begin
      TT_Table.Store_TT
        (Key   => Key_1,
         Depth => 5,
         Score => 150,
         Flag  => Exact,
         Best  => Move_None);

      Hit := TT_Table.Probe_TT (Key_1, Entry_Out);
      Check ("TT probe hits stored entry", Hit);
      Check ("TT probe retrieves exact score (150)", Entry_Out.Score = 150);
      Check ("TT probe retrieves depth (5)", Entry_Out.Depth = 5);

      -- Advance generation
      TT_Table.New_Generation;
      -- Probe still succeeds (data preserved)
      Hit := TT_Table.Probe_TT (Key_1, Entry_Out);
      Check ("TT probe hits across generation boundary", Hit);
   end;

   -- 2. Test Zobrist Hash Sensitivity to Castling Rights:
   Put_Line ("[2/4] Testing Zobrist Hash Sensitivity to Castling Rights...");
   Search_Integration.Reset_Game;
   Search_Integration.Parse_FEN
     ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);

   declare
      Hash_All_Rights : constant Hash_Key :=
        BCH_Hash.Compute_Hash
          (White_To_Move   => True,
           Ep_Square       => Move_Validation.En_Passant_Sq,
           Castling_Rights => Move_Validation.Castling_Rights_Bits);
      Hash_No_Rights  : Hash_Key;
   begin
      -- Strip all castling rights
      Move_Validation.Set_Castling_Rights (False, False, False, False);
      Hash_No_Rights :=
        BCH_Hash.Compute_Hash
          (White_To_Move   => True,
           Ep_Square       => Move_Validation.En_Passant_Sq,
           Castling_Rights => Move_Validation.Castling_Rights_Bits);
      Check ("Zobrist hash distinguishes full castling from no castling", Hash_All_Rights /= Hash_No_Rights);

      -- Restore castling rights
      Move_Validation.Set_Castling_Rights (True, True, True, True);
      Check ("Zobrist hash restores deterministically",
             BCH_Hash.Compute_Hash
               (White_To_Move   => True,
                Ep_Square       => Move_Validation.En_Passant_Sq,
                Castling_Rights => Move_Validation.Castling_Rights_Bits) = Hash_All_Rights);
   end;

   -- 3. Test Transposition Table Physical Allocation & Stride:
   Put_Line ("[3/4] Testing TT Sizing and Allocation Limits...");
   TT_Table.Init_TT (2); -- 2 MB
   declare
      Size_MB : constant Natural := TT_Table.Current_Size_MB;
      Bytes   : constant Long_Long_Integer := TT_Table.Current_Allocated_Bytes;
   begin
      Check ("Allocated size reports 2 MB", Size_MB = 2);
      Check ("Allocated bytes is bounded within 2 MB buffer", Bytes <= 2 * 1024 * 1024);
   end;

   -- 4. Test Table Clear on New Game:
   Put_Line ("[4/4] Testing TT Clear Lifecycle...");
   declare
      Key_2     : constant Hash_Key := 1122334455;
      Entry_Out : TT_Entry;
      Hit       : Boolean;
   begin
      TT_Table.Store_TT (Key_2, 3, 50, Upper_Bound, Move_None);
      Check ("Entry present before clear", TT_Table.Probe_TT (Key_2, Entry_Out));

      TT_Table.Clear_TT;
      Hit := TT_Table.Probe_TT (Key_2, Entry_Out);
      Check ("Entry wiped after Clear_TT", not Hit);
      Check ("Hashfull permille is 0 after Clear_TT", TT_Table.Hash_Full_Permille = 0);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("ALL TESTS PASSED SUCCESSFULLY");
   else
      Put_Line ("TEST_V0991719_SUITE: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");

end Test_V0991719_Suite;
