with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with TT_Table;
with TT_Types;   use TT_Types;

--  Gate for the UCI `hashfull` metric (TT_Table.Hash_Full_Permille).
--  Verifies the occupancy counter is exact: it tracks distinct stores, ignores
--  exact-key refreshes, resets on Clear_TT, and is reported as per-mille.
procedure Test_Hashfull is

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

   --  300 distinct keys are enough to exceed one permille in the smallest
   --  table (1 MB), so a broken non-incrementing occupancy counter fails loud.
   for I in 1 .. 300 loop
      TT_Table.Store_TT (Key   => Hash_Key (I) * Hash_Key (7919),
                         Depth => 3,
                         Score => 0,
                         Flag  => Exact,
                         Best  => Move_None);
   end loop;
   declare
      After_Stores : constant Integer := TT_Table.Hash_Full_Permille;
      After_Refresh : Integer;
      Pass : Boolean := True;
   begin
      Show ("after 300 distinct stores", "> 0");
      Put_Line ("  TT_Stores =" & Long_Long_Integer'Image (TT_Table.TT_Stores)
                & "   (expect 300)");
      if After_Stores <= 0 or else TT_Table.TT_Stores /= 300 then
         Pass := False;
      end if;

      --  Refreshing an already-stored key must NOT bump occupancy (case 1 path).
      TT_Table.Store_TT (Key   => Hash_Key (1) * Hash_Key (7919),
                         Depth => 9,
                         Score => 0,
                         Flag  => Exact,
                         Best  => Move_None);
      After_Refresh := TT_Table.Hash_Full_Permille;
      Put_Line ("  after 1 refresh       TT_Stores ="
                & Long_Long_Integer'Image (TT_Table.TT_Stores)
                & "   (expect 301); hashfull must stay"
                & Integer'Image (After_Stores));
      if After_Refresh /= After_Stores or else TT_Table.TT_Stores /= 301 then
         Pass := False;
      end if;

      --  Clear resets occupancy to 0 (and bumps the generation).
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
