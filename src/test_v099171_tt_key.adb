-------------------------------------------------------------------------------
--  PRECHESS UCI - V0.9.9.17.1 TT KEY & HASH CORRECTNESS TEST SUITE
--
--  Unit:          Test_V099171_TT_Key
--  Standard:      Ada 2022 (ISO/IEC 8652:2023)
--  Compiler:      GNAT native (-gnat2022)
--  Author:        Arthur Matheus (Prechess Engine Project)
--  Date:          2026
-------------------------------------------------------------------------------

with Ada.Command_Line;
with Ada.Text_IO; use Ada.Text_IO;
with TT_Types; use TT_Types;
with Search_Integration;
with Move_Validation;

procedure Test_V099171_TT_Key is
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
   Put_Line ("  Prechess 0.9.9.17.1 - TT Key Hash Correctness Gate    ");
   Put_Line ("========================================================");

   -- 1. Castling Rights Differentiation in TT Key
   Put_Line ("[1/3] Testing Castling Rights inclusion in Root_Position_Key...");
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

   -- 2. Side to Move Hash Key Invariance
   Put_Line ("[2/3] Testing Side to Move Differentiation...");
   declare
      Key_W, Key_B : TT_Types.Hash_Key;
   begin
      Search_Integration.Parse_FEN ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", Dummy_White);
      Key_W := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1", Dummy_White);
      Key_B := Search_Integration.Root_Position_Key (False);

      Check ("Key with White to move differs from Black to move",
             TT_Types."/=" (Key_W, Key_B));
   end;

   -- 3. EP Square Key differentiation
   Put_Line ("[3/4] Testing En Passant Square in Key...");
   declare
      Key_With_Legal_EP : TT_Types.Hash_Key;
      Key_Without_EP    : TT_Types.Hash_Key;
   begin
      Search_Integration.Parse_FEN ("4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1", Dummy_White);
      Key_With_Legal_EP := Search_Integration.Root_Position_Key (True);

      Search_Integration.Parse_FEN ("4k3/8/8/3Pp3/8/8/8/4K3 w - - 0 1", Dummy_White);
      Key_Without_EP := Search_Integration.Root_Position_Key (True);

      Check ("Legal EP square e6 produces different key than without EP",
             TT_Types."/=" (Key_With_Legal_EP, Key_Without_EP));

      declare
         Key_No_Capturer_EP   : TT_Types.Hash_Key;
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

   Put_Line ("--------------------------------------------------------");
   if Failures = 0 then
      Put_Line ("TEST_V099171_TT_KEY: ALL PASS");
   else
      Put_Line ("TEST_V099171_TT_KEY: FAIL (" & Natural'Image (Failures) & " failures)");
   end if;
   Put_Line ("========================================================");
end Test_V099171_TT_Key;
