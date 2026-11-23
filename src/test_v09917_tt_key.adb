-------------------------------------------------------------------------------
--  PRECHESS UCI - GATE G10: TT KEY & HASH CORRECTNESS TEST SUITE
--
--  Unit:          Test_V09917_TT_Key
--  Standard:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT native 16.1.0 (-gnat2022)
--  Author:        Arthur Matheus (Prechess Engine Project)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with TT_Types; use TT_Types;
with Search_Integration;
with Move_Validation;

procedure Test_V09917_TT_Key is
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
   Put_Line ("  Prechess 0.9.9.17 - TT Key Hash Correctness Gate (G10)");
   Put_Line ("========================================================");

   -- -------------------------------------------------------------------------
   --  Section 1: Castling Rights Differentiation in TT Key (H1 / B-M6)
   -- -------------------------------------------------------------------------
   Put_Line ("[1/4] Testing Castling Rights inclusion in Root_Position_Key...");
   declare
      Key_KQkq, Key_K, Key_Q, Key_None, Key_KQkq_2 : TT_Types.Hash_Key;
   begin
      Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", Dummy_White);
      Key_KQkq := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w K - 0 1", Dummy_White);
      Key_K := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w Q - 0 1", Dummy_White);
      Key_Q := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1", Dummy_White);
      Key_None := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", Dummy_White);
      Key_KQkq_2 := Search_Integration.Root_Position_Key (True);

      Check ("Key with KQkq castling rights differs from K only",
             TT_Types."/=" (Key_KQkq, Key_K));
      Check ("Key with K castling rights differs from Q only",
             TT_Types."/=" (Key_K, Key_Q));
      Check ("Key with Q castling rights differs from None",
             TT_Types."/=" (Key_Q, Key_None));
      Check ("Key with KQkq castling rights differs from None",
             TT_Types."/=" (Key_KQkq, Key_None));
      Check ("Identical positions with same castling rights produce identical keys",
             TT_Types."=" (Key_KQkq, Key_KQkq_2));
   end;

   -- -------------------------------------------------------------------------
   --  Section 2: En Passant Target Differentiation in TT Key (H1 / B-M6)
   -- -------------------------------------------------------------------------
   Put_Line ("[2/4] Testing En Passant inclusion in Root_Position_Key...");
   declare
      --  White pawn on d5, Black pawn on e5. Black just played e7-e5.
      --  EP target is e6. White can legally play d5xe6 e.p.
      Key_With_Legal_EP : TT_Types.Hash_Key;
      Key_Without_EP    : TT_Types.Hash_Key;
   begin
      Search_Integration.Parse_FEN ("4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1", Dummy_White);
      Key_With_Legal_EP := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("4k3/8/8/3Pp3/8/8/8/4K3 w - - 0 1", Dummy_White);
      Key_Without_EP := Search_Integration.Root_Position_Key (True);

      Check ("Legal EP square e6 produces different key than without EP",
             TT_Types."/=" (Key_With_Legal_EP, Key_Without_EP));

      --  Now test EP square when NO capture is legal (e.g. no friendly pawn on adjacent file)
      declare
         Key_No_Capturer_EP : TT_Types.Hash_Key;
         Key_No_Capturer_Dash : TT_Types.Hash_Key;
      begin
         Search_Integration.Parse_FEN ("4k3/8/8/8/3p4/8/8/4K3 w - e3 0 1", Dummy_White);
         Key_No_Capturer_EP := Search_Integration.Root_Position_Key (True);

         Search_Integration.Parse_FEN ("4k3/8/8/8/3p4/8/8/4K3 w - - 0 1", Dummy_White);
         Key_No_Capturer_Dash := Search_Integration.Root_Position_Key (True);

         Check ("Inert EP square (no legal capture) matches dash key per FIDE",
                TT_Types."=" (Key_No_Capturer_EP, Key_No_Capturer_Dash));
      end;
   end;

   -- -------------------------------------------------------------------------
   --  Section 3: Side to Move Differentiation in TT Key
   -- -------------------------------------------------------------------------
   Put_Line ("[3/4] Testing Side to Move differentiation in Root_Position_Key...");
   declare
      Key_White : TT_Types.Hash_Key;
      Key_Black : TT_Types.Hash_Key;
   begin
      Search_Integration.Parse_FEN ("4k3/8/8/8/8/8/8/4K3 w - - 0 1", Dummy_White);
      Key_White := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("4k3/8/8/8/8/8/8/4K3 b - - 0 1", Dummy_White);
      Key_Black := Search_Integration.Root_Position_Key (False);

      Check ("White to move produces different key than Black to move",
             TT_Types."/=" (Key_White, Key_Black));
   end;

   -- -------------------------------------------------------------------------
   --  Section 4: Structural Sizing and Entry Layout Invariants
   -- -------------------------------------------------------------------------
   Put_Line ("[4/4] Testing TT Entry layout invariants...");
   declare
      Ent_Size : constant Integer := TT_Types.TT_Entry'Size;
   begin
      Check ("TT_Entry size is non-zero and multiple of 8 bits",
             Ent_Size > 0 and then Ent_Size mod 8 = 0);
   end;

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V09917_TT_KEY: PASS");
   else
      Put_Line ("TEST_V09917_TT_KEY: FAIL (count =" & Natural'Image (Failures) & ")");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
   Put_Line ("========================================================");
end Test_V09917_TT_Key;
