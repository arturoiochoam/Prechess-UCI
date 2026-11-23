-------------------------------------------------------------------------------
--  PRECHESS UCI - TRANSPOSITION TABLE HASHFULL OCCUPANCY TEST HARNESS
--
--  Harness:       Test_Hashfull
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Author:        Arthur Matheus (UCI Engine Integration & Test Harness)
--  Date:          2026
--
--  SCOPE & TEST MATRICES (N1: 250-cluster generation-aware sampler):
--  1. Fresh table reads 0.
--  2. Fills rise dynamically with current-generation stores.
--  3. New generation read drops back to 0 (stale generation entries excluded).
--  4. Clear_TT resets occupancy to 0.
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with TT_Table;
with TT_Types;   use TT_Types;

procedure Test_Hashfull is

   Pass : Boolean := True;

   procedure Show (Label : String; Expect : String) is
   begin
      Put_Line ("  " & Label & "  hashfull ="
                & Integer'Image (TT_Table.Hash_Full_Permille)
                & "   (expect " & Expect & ")");
   end Show;

   Move_None : constant Move_Type := (From_Sq => 1, To_Sq => 1, Prom => 0);

begin
   Put_Line ("TEST_TT_HASHFULL");

   TT_Table.Init_TT (1);   --  smallest table (1 MB)
   Show ("after init             ", "0");
   if TT_Table.Hash_Full_Permille /= 0 then
      Pass := False;
   end if;

   --  Store 50 keys directly targeting the sampled clusters (0 .. 49)
   for I in 0 .. 49 loop
      TT_Table.Store_TT (Key   => Hash_Key (I),
                         Depth => 3,
                         Score => 0,
                         Flag  => Exact,
                         Best  => Move_None);
   end loop;

   declare
      After_Stores : constant Integer := TT_Table.Hash_Full_Permille;
      After_Refresh : Integer;
   begin
      Show ("after 50 distinct stores", "> 0");
      Put_Line ("  TT_Stores =" & Long_Long_Integer'Image (TT_Table.TT_Stores)
                & "   (expect 50)");
      if After_Stores <= 0 or else TT_Table.TT_Stores /= 50 then
         Pass := False;
      end if;

      --  Refreshing an already-stored key must NOT bump occupancy.
      TT_Table.Store_TT (Key   => Hash_Key (0),
                         Depth => 9,
                         Score => 0,
                         Flag  => Exact,
                         Best  => Move_None);
      After_Refresh := TT_Table.Hash_Full_Permille;
      Put_Line ("  after 1 refresh       TT_Stores ="
                & Long_Long_Integer'Image (TT_Table.TT_Stores)
                & "   (expect 51); hashfull must stay"
                & Integer'Image (After_Stores));
      if After_Refresh /= After_Stores or else TT_Table.TT_Stores /= 51 then
         Pass := False;
      end if;

      --  N1: New generation read drops back to 0 (old generation entries not counted)
      TT_Table.New_Generation;
      Show ("after New_Generation   ", "0");
      if TT_Table.Hash_Full_Permille /= 0 then
         Pass := False;
      end if;

      --  Storing in the new generation makes hashfull rise again
      for I in 0 .. 19 loop
         TT_Table.Store_TT (Key   => Hash_Key (I),
                            Depth => 4,
                            Score => 0,
                            Flag  => Exact,
                            Best  => Move_None);
      end loop;
      Show ("after new gen stores   ", "> 0");
      if TT_Table.Hash_Full_Permille <= 0 then
         Pass := False;
      end if;

      --  Clear resets occupancy to 0 (and bumps generation).
      TT_Table.Clear_TT;
      Show ("after Clear_TT          ", "0");
      if TT_Table.Hash_Full_Permille /= 0 then
         Pass := False;
      end if;

      if Pass then
         Put_Line ("TEST_TT_HASHFULL: PASS");
      else
         Put_Line ("TEST_TT_HASHFULL: FAIL");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      end if;
   end;
end Test_Hashfull;
