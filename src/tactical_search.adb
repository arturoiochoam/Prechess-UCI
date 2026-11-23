-------------------------------------------------------------------------------
--  PRECHESS UCI - TACTICAL VERIFICATION SEARCH (Body)
-------------------------------------------------------------------------------

with Ada.Real_Time;   use Ada.Real_Time;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with Interfaces;
with Pvalidade;
with Move_Validation;
with BCH_Hash;
with Search_Integration;
with Time_Management;
with TT_Types;

package body Tactical_Search is
   use Move_Gen;
   use type TT_Types.Hash_Key;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Integer_8;

   Infinity : constant := Mate_Value + 1;

   ----------------------------------------------------------------------------
   --  Copy-make snapshot & incremental Zobrist state
   ----------------------------------------------------------------------------
   Cur_Key       : TT_Types.Hash_Key := 0;
   Cur_Ep_Hashed : Integer := 0;
   Cur_Half_Move : Natural := 0;

   subtype Board_Copy is Pvalidade.Board_Array;
   type Snapshot is record
      Bd             : Board_Copy;
      WK, WQ, BK, BQ : Boolean;
      EP             : Integer;
   end record;

   type Key_Snapshot is record
      Key  : TT_Types.Hash_Key;
      EP_H : Integer;
      HM   : Natural;
   end record;

   procedure Save (S : out Snapshot) is
   begin
      S.Bd := Pvalidade.Tabuleiro;   --  whole-array (block) copy
      S.WK := Move_Validation.White_Castling_K;
      S.WQ := Move_Validation.White_Castling_Q;
      S.BK := Move_Validation.Black_Castling_K;
      S.BQ := Move_Validation.Black_Castling_Q;
      S.EP := Move_Validation.En_Passant_Sq;
   end Save;

   procedure Restore (S : Snapshot) is
   begin
      Pvalidade.Tabuleiro := S.Bd;   --  whole-array (block) copy
      Move_Validation.White_Castling_K := S.WK;
      Move_Validation.White_Castling_Q := S.WQ;
      Move_Validation.Black_Castling_K := S.BK;
      Move_Validation.Black_Castling_Q := S.BQ;
      Move_Validation.En_Passant_Sq    := S.EP;
   end Restore;

   procedure Save_Key (KS : out Key_Snapshot) is
   begin
      KS.Key  := Cur_Key;
      KS.EP_H := Cur_Ep_Hashed;
      KS.HM   := Cur_Half_Move;
   end Save_Key;

   procedure Restore_Key (KS : Key_Snapshot) is
   begin
      Cur_Key       := KS.Key;
      Cur_Ep_Hashed := KS.EP_H;
      Cur_Half_Move := KS.HM;
   end Restore_Key;

   procedure Apply_Move (F, T, Promo : Integer; White : Boolean) is
      Piece      : constant Integer := Pvalidade.Tabuleiro (F);
      Abs_Piece  : constant Integer := abs Piece;
      Cap        : constant Integer := Pvalidade.Tabuleiro (T);
      Old_Rights : constant Integer := Move_Validation.Castling_Rights_Bits;
      Old_EP     : constant Integer := Move_Validation.En_Passant_Sq;
      FF         : constant Integer := Move_Validation.File_Of (F);
      TF         : constant Integer := Move_Validation.File_Of (T);
      Is_EP      : constant Boolean :=
        Abs_Piece = 1 and then Old_EP /= 0 and then T = Old_EP
        and then Cap = 0 and then TF /= FF;
      Is_Castle  : constant Boolean :=
        Abs_Piece = 999 and then abs (TF - FF) = 2;
      New_Rights : Integer;
      New_EP     : Integer;
   begin
      Make_Move (F, T, Promo, White);

      if Abs_Piece = 1 or else Cap /= 0 or else Is_EP then
         Cur_Half_Move := 0;
      else
         Cur_Half_Move := Cur_Half_Move + 1;
      end if;

      if Cur_Ep_Hashed /= 0 then
         Cur_Key := Cur_Key xor BCH_Hash.Hash_Ep (Cur_Ep_Hashed);
         Cur_Ep_Hashed := 0;
      end if;

      Cur_Key := Cur_Key
        xor BCH_Hash.Hash_Side
        xor BCH_Hash.Hash_Piece (Piece, F)
        xor BCH_Hash.Hash_Piece (Cap, T)
        xor BCH_Hash.Hash_Piece (Pvalidade.Tabuleiro (T), T);

      if Is_EP then
         declare
            Ep_Pawn_Sq : constant Integer := (if White then T - 8 else T + 8);
            Ep_Pawn    : constant Integer := (if White then -1 else 1);
         begin
            Cur_Key := Cur_Key xor BCH_Hash.Hash_Piece (Ep_Pawn, Ep_Pawn_Sq);
         end;
      end if;

      if Is_Castle then
         declare
            Kingside  : constant Boolean := TF > FF;
            Rook_From : constant Integer :=
              Move_Validation.Home_Rook_Square (White, Kingside);
            Rook_To   : constant Integer :=
              (if Kingside then F + 1 else F - 1);
            Rook_Code : constant Integer := (if White then 7 else -7);
         begin
            Cur_Key := Cur_Key
              xor BCH_Hash.Hash_Piece (Rook_Code, Rook_From)
              xor BCH_Hash.Hash_Piece (Rook_Code, Rook_To);
         end;
      end if;

      New_Rights := Move_Validation.Castling_Rights_Bits;
      if New_Rights /= Old_Rights then
         Cur_Key := Cur_Key
           xor BCH_Hash.Hash_Castling (Old_Rights)
           xor BCH_Hash.Hash_Castling (New_Rights);
      end if;

      New_EP := Move_Validation.En_Passant_Sq;
      if New_EP /= 0
        and then Search_Integration.Has_Legal_En_Passant_Capture (not White, New_EP)
      then
         Cur_Ep_Hashed := New_EP;
         Cur_Key := Cur_Key xor BCH_Hash.Hash_Ep (Cur_Ep_Hashed);
      end if;

      pragma Assert
        (Cur_Key = Search_Integration.Root_Position_Key (not White));
   end Apply_Move;

   ----------------------------------------------------------------------------
   --  Search state
   ----------------------------------------------------------------------------
   Deadline      : Time := Clock;
   Hard_Deadline : Time := Clock;
   Abort_Allowed : Boolean := True;
   Aborted       : Boolean := False;
   Nodes         : Long_Long_Integer := 0;
   Nodes_Global_Base : Long_Long_Integer := 0;
   Sel           : Natural := 0;
   --  Number of leading quiescence plies that also search checking moves.
   Q_Check_Plies      : constant := 2;
   In_Verify_Search   : Boolean  := False;
   Verify_Attack_Eval : Boolean  := False;
   Verify_Development : Boolean  := False;

   function Needs_Development return Boolean is
     ((Pvalidade.Tabuleiro (7) = 999 and then Pvalidade.Tabuleiro (2) = 4
       and then Pvalidade.Tabuleiro (3) = 3)
      or else (Pvalidade.Tabuleiro (63) = -999 and then Pvalidade.Tabuleiro (58) = -4
       and then Pvalidade.Tabuleiro (59) = -3));

   No_Move : constant Move_Rec := (From => 0, To => 0, Promo => 0);

   type Killer_Pair is array (1 .. 2) of Move_Rec;
   Killers   : array (0 .. Max_Ply + 1) of Killer_Pair :=
     [others => [others => No_Move]];
   PV_Table  : array (0 .. Max_Ply + 1) of PV_Array;
   PV_Length : array (0 .. Max_Ply + 1) of Natural := [others => 0];
   Key_Stack : array (0 .. Max_Ply + 1) of TT_Types.Hash_Key :=
     [others => 0];

   procedure Tick is
      Now : Time;
   begin
      Nodes := Nodes + 1;
      if Nodes mod 64 = 0 then
         --  Batch shared telemetry instead of a global read/modify/write on
         --  every node; Report_PV and Verify flush the tail as needed.
         TT_Types.Nodes_Searched := Nodes_Global_Base + Nodes;
         Time_Management.Check_Time;
         if Time_Management.Search_Aborted then
            Aborted := True;
            return;
         end if;
         Now := Clock;
         if Now >= Hard_Deadline
           or else (Abort_Allowed and then Now >= Deadline)
         then
            Aborted := True;
         end if;
      end if;
   end Tick;

   ----------------------------------------------------------------------------
   --  Evaluation
   ----------------------------------------------------------------------------
   function Val (P : Integer) return Integer is
     (case abs P is
         when 1      => 100,
         when 4      => 320,
         when 3      => 330,
         when 7      => 500,
         when 20     => 975,
         when 999    => 20000,
         when others => 0);

   function Needs_Attack_Evaluation return Boolean is
      WK     : Integer := 0;
      BK     : Integer := 0;
      Has_WQ : Boolean := False;
      Has_BQ : Boolean := False;
      P      : Integer;
   begin
      for S in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (S);
         if P = 999 then
            WK := S;
         elsif P = -999 then
            BK := S;
         elsif P = 20 then
            Has_WQ := True;
         elsif P = -20 then
            Has_BQ := True;
         end if;
      end loop;
      return (WK in 9 .. 64 and then Has_BQ)
        or else (BK in 1 .. 56 and then Has_WQ);
   end Needs_Attack_Evaluation;

   function Evaluate_White return Integer is
      Adv    : constant array (1 .. 8) of Integer := [0, 0, 4, 10, 18, 28, 45, 0];
      Pass   : constant array (1 .. 8) of Integer := [0, 5, 10, 20, 35, 110, 210, 0];
      N_Rank : constant array (1 .. 8) of Integer := [-15, -6, 6, 14, 18, 16, 2, -10];
      N_File : constant array (1 .. 8) of Integer := [-14, -4, 8, 12, 12, 8, -4, -14];
      B_Rank : constant array (1 .. 8) of Integer := [-10, 0, 6, 10, 10, 8, 2, -6];
      B_File : constant array (1 .. 8) of Integer := [-6, 0, 4, 6, 6, 4, 0, -6];
      Attack_Eval : constant Boolean :=
        (if In_Verify_Search then Verify_Attack_Eval
         else Needs_Attack_Evaluation);
      Development : constant Boolean :=
        (if In_Verify_Search then Verify_Development else Needs_Development);
      W_Min  : array (0 .. 9) of Integer := [others => 9];  --  lowest white pawn rank per file
      B_Max  : array (0 .. 9) of Integer := [others => 0];  --  highest black pawn rank per file
      W_Cnt  : array (1 .. 8) of Natural := [others => 0];
      B_Cnt  : array (1 .. 8) of Natural := [others => 0];
      Score  : Integer := 0;
      WN, BN : Natural := 0;
      WB, BB : Natural := 0;
      WQ, BQ : Natural := 0;
      WK_Sq  : Integer := 0;
      BK_Sq  : Integer := 0;
      P, R, F, MR : Integer;
      Passed : Boolean;

      function Mobility (S, PC : Integer) return Integer is
         K  : constant Integer := (if PC > 0 then BK_Sq else WK_Sq);
         KR : constant Integer := (if K > 0 then (K - 1) / 8 + 1 else 0);
         KF : constant Integer := (if K > 0 then (K - 1) mod 8 + 1 else 0);
         R0 : constant Integer := (S - 1) / 8 + 1;
         F0 : constant Integer := (S - 1) mod 8 + 1;
         RR, FF, SS, TT : Integer;
         Count, Pressure : Integer := 0;
         Dirs : constant array (1 .. 8, 1 .. 2) of Integer :=
           [[-1, -1], [-1, 1], [1, -1], [1, 1],
            [-1, 0], [1, 0], [0, -1], [0, 1]];
         First_D : constant Integer := (if abs PC = 7 then 5 else 1);
         Last_D  : constant Integer := (if abs PC = 3 then 4 else 8);
      begin
         for D in First_D .. Last_D loop
            RR := R0 + Dirs (D, 1);
            FF := F0 + Dirs (D, 2);
            while RR in 1 .. 8 and then FF in 1 .. 8 loop
               SS := (RR - 1) * 8 + FF;
               TT := Pvalidade.Tabuleiro (SS);
               if K > 0 and then abs (RR - KR) <= 1
                 and then abs (FF - KF) <= 1
               then
                  Pressure := Pressure + (if abs PC = 20 then 12 else 8);
               end if;
               exit when TT /= 0 and then ((PC > 0) = (TT > 0));
               Count := Count + 1;
               exit when TT /= 0;
               RR := RR + Dirs (D, 1);
               FF := FF + Dirs (D, 2);
            end loop;
         end loop;
         return Pressure +
           (case abs PC is
               when 3      => 5 * (Count - 7),
               when 7      => 3 * (Count - 7),
               when others => Count - 14);
      end Mobility;

      --  Rule-based bonus for a free 6th/7th-rank passed-pawn stop square
      --  and friendly knight control from ranks 5-6 (White) or 3-4 (Black).
      function Passed_Stop_Bonus
        (Sq : Integer; Is_White : Boolean) return Integer
      is
         Stop_Sq : constant Integer := (if Is_White then Sq + 8 else Sq - 8);
         N_First : constant Integer := (if Is_White then 33 else 17);
         N_Last  : constant Integer := (if Is_White then 48 else 32);
         Own_N   : constant Integer := (if Is_White then 4 else -4);
         Bonus   : Integer := 0;
      begin
         if Stop_Sq in 1 .. 64 and then Pvalidade.Tabuleiro (Stop_Sq) = 0 then
            if (if Is_White then Sq >= 49 else Sq <= 16)
              and then Move_Validation.Is_Square_Attacked (Stop_Sq, not Is_White)
            then
               return (if Is_White then -Pass (7) / 2 else Pass (7) / 2);
            end if;
            declare
               Stop_R : constant Integer := (Stop_Sq - 1) / 8 + 1;
               Stop_F : constant Integer := (Stop_Sq - 1) mod 8 + 1;
               NR, NF : Integer;
            begin
               Bonus := 45;
               for N_Sq in N_First .. N_Last loop
                  if Pvalidade.Tabuleiro (N_Sq) = Own_N then
                     NR := (N_Sq - 1) / 8 + 1;
                     NF := (N_Sq - 1) mod 8 + 1;
                     if (abs (NR - Stop_R) = 1 and then abs (NF - Stop_F) = 2)
                       or else (abs (NR - Stop_R) = 2 and then abs (NF - Stop_F) = 1)
                     then
                        Bonus := Bonus + 90;
                        exit;
                     end if;
                  end if;
               end loop;
            end;
         end if;
         return (if Is_White then Bonus else -Bonus);
      end Passed_Stop_Bonus;
   begin
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if abs P = 1 then
            F := (Sq - 1) mod 8 + 1;
            R := (Sq - 1) / 8 + 1;
            if P = 1 then
               W_Min (F) := Integer'Min (W_Min (F), R);
               W_Cnt (F) := W_Cnt (F) + 1;
            else
               B_Max (F) := Integer'Max (B_Max (F), R);
               B_Cnt (F) := B_Cnt (F) + 1;
            end if;
         elsif P = 999 then
            WK_Sq := Sq;
         elsif P = -999 then
            BK_Sq := Sq;
         elsif P = 20 then
            WQ := WQ + 1;
         elsif P = -20 then
            BQ := BQ + 1;
         end if;
      end loop;

      for F_Idx in 1 .. 8 loop
         if W_Cnt (F_Idx) > 1 then
            Score := Score - 15 * Integer (W_Cnt (F_Idx) - 1);
         end if;
         if B_Cnt (F_Idx) > 1 then
            Score := Score + 15 * Integer (B_Cnt (F_Idx) - 1);
         end if;
      end loop;

      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if P /= 0 and then abs P /= 999 then
            F  := (Sq - 1) mod 8 + 1;
            R  := (Sq - 1) / 8 + 1;
            MR := (if P > 0 then R else 9 - R);
            if P > 0 then
               Score := Score + Val (P);
            else
               Score := Score - Val (P);
            end if;
            if P = 1 then
               Passed := B_Max (F - 1) <= R and then B_Max (F) <= R and then B_Max (F + 1) <= R;
               if Passed then
                  Score := Score + Adv (MR) + Pass (MR);
                  if MR in 6 .. 7 then
                     Score := Score + Passed_Stop_Bonus (Sq, Is_White => True);
                  end if;
               elsif F in 3 .. 6 then
                  Score := Score + Adv (MR);
               else
                  Score := Score + Adv (MR) / 2;
               end if;
            elsif P = -1 then
               Passed := W_Min (F - 1) >= R and then W_Min (F) >= R and then W_Min (F + 1) >= R;
               if Passed then
                  Score := Score - Adv (MR) - Pass (MR);
                  if MR in 6 .. 7 then
                     Score := Score + Passed_Stop_Bonus (Sq, Is_White => False);
                  end if;
               elsif F in 3 .. 6 then
                  Score := Score - Adv (MR);
               else
                  Score := Score - Adv (MR) / 2;
               end if;
            elsif P = 4 then
               WN := WN + 1;
               Score := Score + N_Rank (MR) + N_File (F);
               if R in 5 .. 6 and then F in 4 .. 5
                 and then B_Max (F - 1) <= R and then B_Max (F + 1) <= R
               then
                  Score := Score + 45;
                  declare
                     N_Off : constant array (1 .. 8) of Integer :=
                       [-17, -15, -10, -6, 6, 10, 15, 17];
                     Target_P : Integer;
                  begin
                     for D of N_Off loop
                        Target_P := Pvalidade.Tabuleiro (Sq + D);
                        if Target_P = -3 or else Target_P = -7 then
                           Score := Score + 55;
                           exit;
                        end if;
                     end loop;
                  end;
               end if;
            elsif P = -4 then
               BN := BN + 1;
               Score := Score - (N_Rank (MR) + N_File (F));
               if R in 3 .. 4 and then F in 4 .. 5
                 and then W_Min (F - 1) >= R and then W_Min (F + 1) >= R
               then
                  Score := Score - 45;
                  declare
                     N_Off : constant array (1 .. 8) of Integer :=
                       [-17, -15, -10, -6, 6, 10, 15, 17];
                     Target_P : Integer;
                  begin
                     for D of N_Off loop
                        Target_P := Pvalidade.Tabuleiro (Sq + D);
                        if Target_P = 3 or else Target_P = 7 then
                           Score := Score - 55;
                           exit;
                        end if;
                     end loop;
                  end;
               end if;
            elsif P = 3 then
               WB := WB + 1;
               Score := Score + B_Rank (MR) + B_File (F);
            elsif P = -3 then
               BB := BB + 1;
               Score := Score - (B_Rank (MR) + B_File (F));
            elsif P = 7 then
               if W_Cnt (F) = 0 then
                  Score := Score + (if B_Cnt (F) = 0 then 16 else 8);
               end if;
               if MR = 7 then
                  Score := Score + 15;
               end if;
            elsif P = -7 then
               if B_Cnt (F) = 0 then
                  Score := Score - (if W_Cnt (F) = 0 then 16 else 8);
               end if;
               if MR = 7 then
                  Score := Score - 15;
               end if;
            end if;
            if (Attack_Eval and then abs P in 3 | 7 | 20)
              or else (WQ = 0 and then BQ = 0 and then abs P in 3 | 7)
              or else (Development and then abs P = 3 and then WQ > 0 and then BQ > 0)
            then
               Score := Score +
                 (if P > 0 then Mobility (Sq, P) else -Mobility (Sq, P));
            end if;
         end if;
      end loop;

      if WB >= 2 then Score := Score + 30; end if;
      if BB >= 2 then Score := Score - 30; end if;
      if Attack_Eval then
         if WB >= 2 and then BN = 0 and then BB = 0 then
            Score := Score + 80;
         end if;
         if BB >= 2 and then WN = 0 and then WB = 0 then
            Score := Score - 80;
         end if;
      end if;

      if BQ > 0 and then WK_Sq > 0
        and then ((WK_Sq - 1) mod 8 in 3 .. 4 or else WK_Sq > 8)
        and then not (Move_Validation.White_Castling_K
                      or else Move_Validation.White_Castling_Q)
      then
         Score := Score - 80;
      end if;
      if WQ > 0 and then BK_Sq > 0
        and then ((BK_Sq - 1) mod 8 in 3 .. 4 or else BK_Sq <= 56)
        and then not (Move_Validation.Black_Castling_K
                      or else Move_Validation.Black_Castling_Q)
      then
         Score := Score + 80;
      end if;

      --  King safety & pawn shield evaluation
      --  A knight in front of an unmoved c-pawn delays the c-file break
      --  against an opposing central pawn. Do not charge after the pawn moves.
      if Development and then WQ > 0 and then BQ > 0 then
         if Pvalidade.Tabuleiro (11) = 1 and then Pvalidade.Tabuleiro (19) = 4
           and then Pvalidade.Tabuleiro (36) = -1
         then
            Score := Score - 32;
         end if;
         if Pvalidade.Tabuleiro (51) = -1 and then Pvalidade.Tabuleiro (43) = -4
           and then Pvalidade.Tabuleiro (28) = 1
         then
            Score := Score + 32;
         end if;
      end if;
      --  Discount home-square minor pieces while both queens are present.
      if Development and then WQ > 0 and then BQ > 0 then
         for File_Idx in 1 .. 8 loop
            declare
               Minor : constant Integer :=
                 (case File_Idx is when 2 | 7 => 4, when 3 | 6 => 3, when others => 0);
            begin
               if Minor /= 0 then
                  if Pvalidade.Tabuleiro (File_Idx) = Minor then
                     Score := Score - 38;
                  end if;
                  if Pvalidade.Tabuleiro (56 + File_Idx) = -Minor then
                     Score := Score + 38;
                  end if;
               end if;
            end;
         end loop;
      end if;
      --  A two-step advance or loss of the outside shelter pawn opens
      --  entry squares beside a castled king while the enemy queen remains.
      if Development and then BQ > 0 and then WK_Sq in 7 .. 8
        and then Pvalidade.Tabuleiro (16) /= 1 and then Pvalidade.Tabuleiro (24) /= 1
      then
         Score := Score - 55;
      end if;
      if Development and then WQ > 0 and then BK_Sq in 63 .. 64
        and then Pvalidade.Tabuleiro (56) /= -1 and then Pvalidade.Tabuleiro (48) /= -1
      then
         Score := Score + 55;
      end if;
      if BQ > 0 and then WK_Sq in 4 .. 5 and then W_Cnt (WK_Sq) = 0 then
         Score := Score - 110;
      end if;
      if WQ > 0 and then BK_Sq in 60 .. 61 and then B_Cnt (BK_Sq - 56) = 0 then
         Score := Score + 110;
      end if;
      if BQ > 0 then
         if WK_Sq in 6 .. 8 and then Pvalidade.Tabuleiro (15) /= 1 then
            Score := Score - 75;
         end if;
         if WK_Sq in 5 .. 7
           and then Pvalidade.Tabuleiro (14) /= 1
           and then Pvalidade.Tabuleiro (15) /= 1
         then
            Score := Score - 85;
         elsif (WK_Sq in 6 .. 8 or else WK_Sq in 14 .. 16)
           and then W_Cnt (7) = 0
           and then W_Cnt (8) = 0
         then
            Score := Score - 135;
            if Pvalidade.Tabuleiro (22) = 4
              and then (Pvalidade.Tabuleiro (31) = -3
                        or else Pvalidade.Tabuleiro (40) = -3)
            then
               Score := Score - 60;
            end if;
         elsif WK_Sq = 5 and then Pvalidade.Tabuleiro (14) /= 1 then
            Score := Score - 45;
            if Pvalidade.Tabuleiro (13) = 3 then
               Score := Score + 30;
            end if;
         end if;
      elsif WK_Sq /= 0 then
         declare
            KR : constant Integer := (WK_Sq - 1) / 8 + 1;
            KF : constant Integer := (WK_Sq - 1) mod 8 + 1;
         begin
            if KR = 2 and then KF in 4 .. 5 then
               Score := Score + 35;
            end if;
         end;
      end if;

      if WQ > 0 then
         if BK_Sq in 62 .. 64 and then Pvalidade.Tabuleiro (55) /= -1 then
            Score := Score + 75;
         end if;
         if BK_Sq in 61 .. 63
           and then Pvalidade.Tabuleiro (54) /= -1
           and then Pvalidade.Tabuleiro (55) /= -1
         then
            Score := Score + 85;
         elsif (BK_Sq in 54 .. 56 or else BK_Sq in 62 .. 64)
           and then B_Cnt (7) = 0
           and then B_Cnt (8) = 0
         then
            Score := Score + 135;
            if Pvalidade.Tabuleiro (46) = -4
              and then (Pvalidade.Tabuleiro (39) = 3
                        or else Pvalidade.Tabuleiro (32) = 3)
            then
               Score := Score + 60;
            end if;
         elsif BK_Sq = 61 and then Pvalidade.Tabuleiro (54) /= -1 then
            Score := Score + 45;
            if Pvalidade.Tabuleiro (53) = -3 then
               Score := Score - 30;
            end if;
         end if;
      elsif BK_Sq /= 0 then
         declare
            KR : constant Integer := (BK_Sq - 1) / 8 + 1;
            KF : constant Integer := (BK_Sq - 1) mod 8 + 1;
         begin
            if KR = 7 and then KF in 4 .. 5 then
               Score := Score - 35;
            end if;
         end;
      end if;

      return Score;
   end Evaluate_White;

   function Eval_Side (White : Boolean) return Integer is
     (if White then Evaluate_White else -Evaluate_White);

   ----------------------------------------------------------------------------
   --  Move classification / ordering
   ----------------------------------------------------------------------------
   function Is_Capture (M : Move_Rec) return Boolean is
     (Pvalidade.Tabuleiro (M.To) /= 0
      or else (abs Pvalidade.Tabuleiro (M.From) = 1 and then (M.To - M.From) mod 8 /= 0));

   function Order_Score (M : Move_Rec; Ply : Natural) return Integer is
      Victim   : constant Integer := Pvalidade.Tabuleiro (M.To);
      Attacker : constant Integer := Pvalidade.Tabuleiro (M.From);
   begin
      if M.Promo = 20 then
         return 20_000 + Val (Victim);
      elsif M.Promo /= 0 then
         return -1_000;
      elsif Victim /= 0 then
         return 10_000 + 10 * Val (Victim) - Val (Attacker) / 100;
      elsif abs Attacker = 1 and then (M.To - M.From) mod 8 /= 0 then
         return 10_999;   --  en passant
      elsif M = Killers (Ply) (1) then
         return 8_000;
      elsif M = Killers (Ply) (2) then
         return 7_900;
      elsif abs Attacker = 7 then
         return 80;
      else
         return 0;
      end if;
   end Order_Score;

   type Score_Array is array (1 .. Max_Moves) of Integer;
   Skip : constant Integer := Integer'First;

   --  Selection pick: index of the highest remaining score, 0 if none.
   function Pick (Sc : in out Score_Array; N : Natural) return Natural is
      Best_I : Natural := 0;
      Best_S : Integer := Skip;
   begin
      for I in 1 .. N loop
         if Sc (I) /= Skip and then (Best_I = 0 or else Sc (I) > Best_S) then
            Best_I := I;
            Best_S := Sc (I);
         end if;
      end loop;
      if Best_I /= 0 then
         Sc (Best_I) := Skip;
      end if;
      return Best_I;
   end Pick;


   ----------------------------------------------------------------------------
   --  Fast pseudo-legal generator (offset based). Legality is checked
   --  lazily by the caller: Make_Move then Is_In_Check (mover).
   --  Captures_Only => captures, en passant and queen promotions.
   ----------------------------------------------------------------------------
   type Delta_Pair is record DR, DF : Integer; end record;
   type Delta_List is array (Positive range <>) of Delta_Pair;
   Knight_D : constant Delta_List :=
     [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
   King_D   : constant Delta_List :=
     [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
   Diag_D   : constant Delta_List := [(1, 1), (1, -1), (-1, 1), (-1, -1)];
   Ortho_D  : constant Delta_List := [(1, 0), (-1, 0), (0, 1), (0, -1)];

   procedure Gen (White : Boolean; Captures_Only : Boolean; L : out Move_List) is
      Sign : constant Integer := (if White then 1 else -1);

      procedure Add (F, T, P : Integer) is
      begin
         if L.N < Max_Moves then
            L.N := L.N + 1;
            L.V (L.N) := (From => F, To => T, Promo => P);
         end if;
      end Add;

      function Enemy (P : Integer) return Boolean is
        (P /= 0 and then (P > 0) /= White);

      procedure Add_Pawn (F, T : Integer; Last_Rank : Boolean) is
      begin
         if Last_Rank then
            Add (F, T, 20);
            if not Captures_Only then
               Add (F, T, 7);
               Add (F, T, 4);
               Add (F, T, 3);
            end if;
         else
            Add (F, T, 0);
         end if;
      end Add_Pawn;

      procedure Steps (Sq, R, F : Integer; D : Delta_List) is
         R2, F2, T : Integer;
      begin
         for I in D'Range loop
            R2 := R + D (I).DR;
            F2 := F + D (I).DF;
            if R2 in 1 .. 8 and then F2 in 1 .. 8 then
               T := (R2 - 1) * 8 + F2;
               if Enemy (Pvalidade.Tabuleiro (T)) then
                  Add (Sq, T, 0);
               elsif Pvalidade.Tabuleiro (T) = 0 and then not Captures_Only then
                  Add (Sq, T, 0);
               end if;
            end if;
         end loop;
      end Steps;

      procedure Slides (Sq, R, F : Integer; D : Delta_List) is
         R2, F2, T : Integer;
      begin
         for I in D'Range loop
            R2 := R + D (I).DR;
            F2 := F + D (I).DF;
            while R2 in 1 .. 8 and then F2 in 1 .. 8 loop
               T := (R2 - 1) * 8 + F2;
               if Pvalidade.Tabuleiro (T) = 0 then
                  if not Captures_Only then
                     Add (Sq, T, 0);
                  end if;
               else
                  if Enemy (Pvalidade.Tabuleiro (T)) then
                     Add (Sq, T, 0);
                  end if;
                  exit;
               end if;
               R2 := R2 + D (I).DR;
               F2 := F2 + D (I).DF;
            end loop;
         end loop;
      end Slides;

      P, R, F, T, Dir, Last, Start : Integer;
      EP : constant Integer := Move_Validation.En_Passant_Sq;
   begin
      L.N := 0;
      Dir   := Sign;
      Last  := (if White then 8 else 1);
      Start := (if White then 2 else 7);
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if P /= 0 and then (P > 0) = White then
            R := (Sq - 1) / 8 + 1;
            F := (Sq - 1) mod 8 + 1;
            case abs P is
               when 1 =>
                  if R + Dir in 1 .. 8 then
                     T := Sq + 8 * Dir;
                     if Pvalidade.Tabuleiro (T) = 0 then
                        if R + Dir = Last then
                           Add_Pawn (Sq, T, True);
                        elsif not Captures_Only then
                           Add (Sq, T, 0);
                           if R = Start and then Pvalidade.Tabuleiro (T + 8 * Dir) = 0 then
                              Add (Sq, T + 8 * Dir, 0);
                           end if;
                        end if;
                     end if;
                     for DF in -1 .. 1 loop
                        if DF /= 0 and then F + DF in 1 .. 8 then
                           T := Sq + 8 * Dir + DF;
                           if Enemy (Pvalidade.Tabuleiro (T)) then
                              Add_Pawn (Sq, T, R + Dir = Last);
                           elsif EP /= 0 and then T = EP
                             and then Pvalidade.Tabuleiro (T) = 0
                             and then R = (if White then 5 else 4)
                             and then Pvalidade.Tabuleiro (T - 8 * Dir) = -Sign
                           then
                              Add (Sq, T, 0);
                           end if;
                        end if;
                     end loop;
                  end if;
               when 4 =>
                  Steps (Sq, R, F, Knight_D);
               when 3 =>
                  Slides (Sq, R, F, Diag_D);
               when 7 =>
                  Slides (Sq, R, F, Ortho_D);
               when 20 =>
                  Slides (Sq, R, F, Diag_D);
                  Slides (Sq, R, F, Ortho_D);
               when 999 =>
                  Steps (Sq, R, F, King_D);
                  if not Captures_Only then
                     declare
                        K_From : constant Integer := (if White then 5 else 61);
                     begin
                        if Sq = K_From then
                           if Move_Validation.Is_Castle_Legal (White, Kingside => True) then
                              Add (K_From, K_From + 2, 0);
                           end if;
                           if Move_Validation.Is_Castle_Legal (White, Kingside => False) then
                              Add (K_From, K_From - 2, 0);
                           end if;
                        end if;
                     end;
                  end if;
               when others =>
                  null;
            end case;
         end if;
      end loop;
   end Gen;

   function Perft_Fast (Depth : Natural; White : Boolean) return Long_Long_Integer is
      L     : Move_List;
      S     : Snapshot;
      Total : Long_Long_Integer := 0;
   begin
      if Depth = 0 then
         return 1;
      end if;
      Gen (White, False, L);
      for I in 1 .. L.N loop
         Save (S);
         Make_Move (L.V (I).From, L.V (I).To, L.V (I).Promo, White);
         if not Move_Validation.Is_In_Check (White) then
            Total := Total + Perft_Fast (Depth - 1, not White);
         end if;
         Restore (S);
      end loop;
      return Total;
   end Perft_Fast;

   ----------------------------------------------------------------------------
   --  Shared ray-alignment and fast checking-move pre-filter
   ----------------------------------------------------------------------------
   function Squares_Aligned (A, B : Integer) return Boolean is
      DR, DF : Integer;
   begin
      if A not in 1 .. 64 or else B not in 1 .. 64 then
         return False;
      end if;
      DR := Move_Validation.Rank_Of (A) - Move_Validation.Rank_Of (B);
      DF := Move_Validation.File_Of (A) - Move_Validation.File_Of (B);
      return DR = 0 or else DF = 0 or else abs DR = abs DF;
   end Squares_Aligned;

   --  Sound superset pre-filter for quiet checking moves in quiescence: any
   --  quiet move that can give direct check, discovered check, or castling
   --  rook check passes; unrelated quiet moves are rejected without Save/Make.
   function May_Give_Check
     (From_Sq, To_Sq, Abs_Piece, Enemy_King_Sq : Integer;
      White                                   : Boolean) return Boolean
   is
      TR, TF, EKR, EKF, DR, DF : Integer;
   begin
      if Enemy_King_Sq not in 1 .. 64 then
         return True;
      end if;
      --  Discovered check possibility if mover leaves a line to enemy king.
      if Squares_Aligned (From_Sq, Enemy_King_Sq) then
         return True;
      end if;

      TR  := (To_Sq - 1) / 8 + 1;
      TF  := (To_Sq - 1) mod 8 + 1;
      EKR := (Enemy_King_Sq - 1) / 8 + 1;
      EKF := (Enemy_King_Sq - 1) mod 8 + 1;
      DR  := abs (TR - EKR);
      DF  := abs (TF - EKF);

      case Abs_Piece is
         when 1 =>
            return (if White then EKR = TR + 1 else EKR = TR - 1)
              and then DF = 1;
         when 4 =>
            return (DR = 1 and then DF = 2) or else (DR = 2 and then DF = 1);
         when 3 =>
            return DR = DF;
         when 7 =>
            return DR = 0 or else DF = 0;
         when 20 =>
            return DR = 0 or else DF = 0 or else DR = DF;
         when 999 =>
            declare
               FF : constant Integer := (From_Sq - 1) mod 8 + 1;
            begin
               if abs (TF - FF) = 2 then
                  --  Castling puts the rook between King start and target.
                  return Squares_Aligned ((From_Sq + To_Sq) / 2, Enemy_King_Sq);
               end if;
               return False;
            end;
         when others =>
            return True;
      end case;
   end May_Give_Check;

   ----------------------------------------------------------------------------
   --  Quiescence: captures + queen promotions; all evasions when in check.
   ----------------------------------------------------------------------------
   function Quiesce
     (White : Boolean; Alpha_In, Beta : Integer; Ply : Natural;
      QD : Natural := 0) return Integer
   is
      Alpha        : Integer := Alpha_In;
      L            : Move_List;
      Sc           : Score_Array;
      In_Check     : Boolean;
      Stand        : Integer;
      Best         : Integer;
      Score        : Integer;
      K            : Natural;
      S            : Snapshot;
      Legal        : Natural := 0;
      Quiet        : Move_List;
      N_Caps       : Natural;
      Checks_Added : Boolean := False;
   begin
      PV_Length (Ply) := 0;
      Tick;
      if Aborted then
         return 0;
      end if;
      if Ply > Sel then
         Sel := Ply;
      end if;

      In_Check := Move_Validation.Is_In_Check (White);
      Stand    := Eval_Side (White);
      if Ply >= Max_Ply then
         return Stand;
      end if;

      if In_Check then
         Best := -Mate_Value + Ply;
      else
         --  Check stand-pat before generating captures: avoids move generation
         --  completely on the majority of quiet stand-pat beta cutoffs.
         if Stand >= Beta then
            return Stand;
         end if;
         if Stand > Alpha then
            Alpha := Stand;
         end if;
         Best := Stand;
      end if;

      Gen (White, Captures_Only => not In_Check, L => L);
      for I in 1 .. L.N loop
         Sc (I) := Order_Score (L.V (I), Ply);
      end loop;
      N_Caps := L.N;

      loop
         K := Pick (Sc, L.N);
         if K = 0 then
            --  Defer quiet-check generation until all captures fail to produce
            --  a beta cutoff; capture beta cutoffs skip quiet generation & King scan.
            if not Checks_Added and then not In_Check and then QD < Q_Check_Plies then
               Checks_Added := True;
               declare
                  Enemy_King_Sq : constant Integer := Move_Validation.Find_King (not White);
                  QM            : Move_Rec;
                  Abs_Mover     : Integer;
               begin
                  Gen (White, Captures_Only => False, L => Quiet);
                  for I in 1 .. Quiet.N loop
                     QM := Quiet.V (I);
                     if not Is_Capture (QM) and then QM.Promo = 0
                       and then L.N < Max_Moves
                     then
                        Abs_Mover := abs Pvalidade.Tabuleiro (QM.From);
                        if May_Give_Check (QM.From, QM.To, Abs_Mover, Enemy_King_Sq, White) then
                           L.N := L.N + 1;
                           L.V (L.N) := QM;
                           Sc (L.N) := -500;
                        end if;
                     end if;
                  end loop;
                  K := Pick (Sc, L.N);
               end;
            end if;
            exit when K = 0;
         end if;
         --  Delta pruning: even winning the victim outright cannot reach
         --  alpha. En passant victims sit beside the (empty) target square,
         --  so their 100 cp value is supplied explicitly.
         declare
            M    : constant Move_Rec := L.V (K);
            Vict : constant Integer :=
              (if abs Pvalidade.Tabuleiro (M.From) = 1
                 and then Pvalidade.Tabuleiro (M.To) = 0
                 and then Move_Validation.File_Of (M.From)
                          /= Move_Validation.File_Of (M.To)
               then 1   --  en-passant capture: victim is a pawn
               else Pvalidade.Tabuleiro (M.To));
         begin
            if not In_Check
              and then K <= N_Caps
              and then M.Promo = 0
              and then Stand + Val (Vict) + 200 < Alpha
            then
               null;
            else
               Save (S);
               Make_Move (M.From, M.To, M.Promo, White);
               --  Quiet candidates (appended checks): test gives-check first
               --  -- ~90% of quiet moves fail it, and the accepted set is the
               --  same conjunction of (legal, gives check).
               if K > N_Caps
                 and then not Move_Validation.Is_In_Check (not White)
               then
                  Restore (S);   --  quiet non-checking move: not quiescent
               elsif Move_Validation.Is_In_Check (White) then
                  Restore (S);   --  illegal: leaves own king in check
               else
                  Legal := Legal + 1;
                  Score := -Quiesce (not White, -Beta, -Alpha, Ply + 1, QD + 1);
                  Restore (S);
                  if Aborted then
                     return 0;
                  end if;
                  if Score > Best then
                     Best := Score;
                     if Score > Alpha then
                        Alpha := Score;
                        PV_Table (Ply) (1) := M;
                        PV_Length (Ply) := 1;
                        for I in 1 .. PV_Length (Ply + 1) loop
                           exit when I + 1 > Max_Ply;
                           PV_Table (Ply) (I + 1) := PV_Table (Ply + 1) (I);
                           PV_Length (Ply) := I + 1;
                        end loop;
                        if Alpha >= Beta then
                           return Best;
                        end if;
                     end if;
                  end if;
               end if;
            end if;
         end;
      end loop;
      if In_Check and then Legal = 0 then
         return -Mate_Value + Ply;   --  checkmate (all evasions generated)
      end if;
      return Best;
   end Quiesce;

   ----------------------------------------------------------------------------
   --  Full-width alpha-beta (fail-soft negamax)
   ----------------------------------------------------------------------------
   ----------------------------------------------------------------------------
   --  Transposition table (private to the verifier; compact 16-byte layout)
   ----------------------------------------------------------------------------
   type TT_Flag is (Exact, Lower, Upper) with Size => 8;
   type TT_Entry is record
      Key        : TT_Types.Hash_Key := 0;
      Score      : Interfaces.Integer_16 := 0;
      Best_Code  : Interfaces.Unsigned_16 := 0;
      Generation : Interfaces.Unsigned_16 := 0;
      Depth      : Interfaces.Integer_8 := -1;
      Flag       : TT_Flag := Exact;
   end record with Size => 128, Alignment => 8;

   function Pack_Move (M : Move_Rec) return Interfaces.Unsigned_16 is
      F_Bits, T_Bits, P_Bits : Interfaces.Unsigned_16;
   begin
      if M.From not in 1 .. 64 or else M.To not in 1 .. 64 then
         return 0;
      end if;
      F_Bits := Interfaces.Unsigned_16 (M.From - 1);
      T_Bits := Interfaces.Unsigned_16 (M.To - 1);
      case M.Promo is
         when 0  => P_Bits := 0;
         when 3  => P_Bits := 1;
         when 4  => P_Bits := 2;
         when 7  => P_Bits := 3;
         when 20 => P_Bits := 4;
         when others => return 0;
      end case;
      return 16#8000#
        or F_Bits
        or Interfaces.Shift_Left (T_Bits, 6)
        or Interfaces.Shift_Left (P_Bits, 12);
   end Pack_Move;

   function Unpack_Move (Code : Interfaces.Unsigned_16) return Move_Rec is
      F_Sq, T_Sq, P_Val : Integer;
   begin
      if (Code and 16#8000#) = 0 then
         return No_Move;
      end if;
      F_Sq := Integer (Code and 16#003F#) + 1;
      T_Sq := Integer (Interfaces.Shift_Right (Code, 6) and 16#003F#) + 1;
      case Interfaces.Shift_Right (Code, 12) and 16#0007# is
         when 0      => P_Val := 0;
         when 1      => P_Val := 3;
         when 2      => P_Val := 4;
         when 3      => P_Val := 7;
         when 4      => P_Val := 20;
         when others => return No_Move;
      end case;
      return (From => F_Sq, To => T_Sq, Promo => P_Val);
   end Unpack_Move;

   --  The verifier is the engine's real alpha-beta search, so its table is
   --  sized by the UCI "Hash" option (Set_Hash_MB). Resizing is deferred to
   --  the start of the next Verify so a table is never freed mid-search.
   Default_TT_Size : constant := 2 ** 18;
   type TT_Array is array (Natural range <>) of TT_Entry;
   type TT_Access is access TT_Array;
   procedure Free_TT is new Ada.Unchecked_Deallocation (TT_Array, TT_Access);
   TT      : TT_Access := new TT_Array (0 .. Default_TT_Size - 1);
   TT_Size : Natural   := Default_TT_Size;
   TT_Mask : TT_Types.Hash_Key := TT_Types.Hash_Key (Default_TT_Size - 1);
   TT_MB_Now       : Natural := 0;   --  0 = built-in default allocation
   TT_MB_Requested : Natural := 0;
   pragma Atomic (TT_MB_Requested);
   TT_Generation : Interfaces.Unsigned_16 := 1;
   --  Slots stamped with TT_Generation (reset per Verify): drives UCI hashfull.
   TT_Used       : Natural := 0;

   function TT_Hash_Full return Integer is
     (if TT = null or else TT_Size = 0 or else TT_Used = 0 then 0
      else Integer'Min
        (1000, Integer'Max
           (1, Integer ((Long_Long_Integer (TT_Used) * 1000)
                        / Long_Long_Integer (TT_Size)))));

   function TT_Index (K : TT_Types.Hash_Key) return Natural is
     (Natural (K and TT_Mask));

   procedure Set_Hash_MB (MB : Positive) is
   begin
      TT_MB_Requested := MB;
   end Set_Hash_MB;

   function Current_Hash_Entries return Natural is (TT_Size);

   --  Apply a pending Set_Hash_MB. Free old table first to avoid Old+New peak.
   procedure Apply_Hash_Resize is
      MB          : constant Natural := TT_MB_Requested;
      Entry_Bytes : constant Long_Long_Integer :=
        Long_Long_Integer'Max (1, Long_Long_Integer (TT_Entry'Object_Size / 8));
      Raw_Count   : Long_Long_Integer;
      Pow2_Count  : Long_Long_Integer := 1024;
   begin
      if MB = 0 or else MB = TT_MB_Now then
         return;
      end if;
      Raw_Count := (Long_Long_Integer (MB) * 1024 * 1024) / Entry_Bytes;
      Raw_Count := Long_Long_Integer'Max
        (1024, Long_Long_Integer'Min (Raw_Count, Long_Long_Integer (Natural'Last)));
      while Pow2_Count <= Raw_Count / 2 loop
         Pow2_Count := Pow2_Count * 2;
      end loop;

      if TT /= null then
         Free_TT (TT);
         TT := null;
         TT_Size := 0;
         TT_Mask := 0;
      end if;
      begin
         TT := new TT_Array (0 .. Natural (Pow2_Count) - 1);
      exception
         when Storage_Error =>
            Ada.Text_IO.Put_Line
              ("info string Verifier hash resize failed for" &
               Natural'Image (MB) & " MB (out of memory); using default");
            TT_MB_Requested := 0;
            TT_MB_Now       := 0;
            TT_Generation   := 1;
            begin
               TT      := new TT_Array (0 .. Default_TT_Size - 1);
               TT_Size := Default_TT_Size;
               TT_Mask := TT_Types.Hash_Key (Default_TT_Size - 1);
            exception
               when Storage_Error =>
                  TT      := null;
                  TT_Size := 0;
                  TT_Mask := 0;
            end;
            return;
      end;
      TT_Size       := Natural (Pow2_Count);
      TT_Mask       := TT_Types.Hash_Key (Pow2_Count - 1);
      TT_MB_Now     := MB;
      TT_Generation := 1;   --  fresh entries are Generation 0: all stale
   end Apply_Hash_Resize;

   procedure Clear_TT is
   begin
      Apply_Hash_Resize;
      if TT /= null then
         TT.all := [others => (Key => 0, Score => 0, Best_Code => 0,
                               Generation => 0, Depth => -1, Flag => Exact)];
      end if;
      TT_Generation := 1;
      TT_Used       := 0;
   end Clear_TT;

   --  Mate scores are stored relative to the node, not the root.
   function To_TT (Score : Integer; Ply : Natural) return Interfaces.Integer_16 is
      V : Integer := Score;
   begin
      if V >= Mate_Threshold then
         V := V + Ply;
      elsif V <= -Mate_Threshold then
         V := V - Ply;
      end if;
      if V > 32767 then
         V := 32767;
      elsif V < -32767 then
         V := -32767;
      end if;
      return Interfaces.Integer_16 (V);
   end To_TT;

   function From_TT (Score : Interfaces.Integer_16; Ply : Natural) return Integer is
      V : constant Integer := Integer (Score);
   begin
      if V >= Mate_Threshold then
         return V - Ply;
      elsif V <= -Mate_Threshold then
         return V + Ply;
      else
         return V;
      end if;
   end From_TT;

   procedure TT_Store (K : TT_Types.Hash_Key; Depth, Score : Integer;
                       Flag : TT_Flag; Best : Move_Rec; Ply : Natural) is
      D8 : Interfaces.Integer_8;
   begin
      if TT = null or else TT_Size = 0 then
         return;
      end if;
      D8 := Interfaces.Integer_8 (Integer'Max (-128, Integer'Min (127, Depth)));
      declare
         E : TT_Entry renames TT (TT_Index (K));
      begin
         if E.Key /= K or else E.Generation /= TT_Generation
           or else D8 >= E.Depth
         then
            if E.Generation /= TT_Generation then
               TT_Used := TT_Used + 1;
            end if;
            E := (Key        => K,
                  Score      => To_TT (Score, Ply),
                  Best_Code  => Pack_Move (Best),
                  Generation => TT_Generation,
                  Depth      => D8,
                  Flag       => Flag);
         end if;
      end;
   end TT_Store;

   function Has_Pieces (White : Boolean) return Boolean is
      P : Integer;
   begin
      for Sq in 1 .. 64 loop
         P := Pvalidade.Tabuleiro (Sq);
         if P /= 0 and then (P > 0) = White
           and then abs P /= 1 and then abs P /= 999
         then
            return True;
         end if;
      end loop;
      return False;
   end Has_Pieces;

   ----------------------------------------------------------------------------
   --  Full-width alpha-beta: fail-soft negamax with TT, PVS, null move
   --  (R=2, never in check / pawn-only endings) and late-move reductions
   --  on quiet non-checking moves (always re-searched at full depth when
   --  they beat alpha).
   ----------------------------------------------------------------------------
   function Search
     (White : Boolean; Depth_In : Integer; Alpha_In, Beta : Integer; Ply : Natural;
      Null_Ok : Boolean := True; Min_Rep_Ply : Natural := 0) return Integer
   is
      Depth      : Integer := Depth_In;
      Alpha      : Integer := Alpha_In;
      Alpha_Orig : constant Integer := Alpha_In;
      L          : Move_List;
      Sc         : Score_Array;
      In_Check   : Boolean;
      Best       : Integer := -Infinity;
      Best_Move  : Move_Rec := No_Move;
      TT_Move    : Move_Rec := No_Move;
      Score      : Integer;
      K          : Natural;
      S          : Snapshot;
      Legal      : Natural := 0;
      Key        : TT_Types.Hash_Key;
      King_Sq    : Integer := 0;
   begin
      PV_Length (Ply) := 0;
      if Depth <= 0 then
         return Quiesce (White, Alpha, Beta, Ply);
      end if;
      Tick;
      if Aborted then
         return 0;
      end if;
      if Ply > Sel then
         Sel := Ply;
      end if;

      --  FIDE 50-move draw in search (checkmate takes precedence on ply 100).
      if Ply > 0 and then Cur_Half_Move >= 100 then
         if not Move_Validation.Is_In_Check (White) then
            return 0;
         end if;
         Gen (White, Captures_Only => False, L => L);
         for I in 1 .. L.N loop
            Save (S);
            Make_Move (L.V (I).From, L.V (I).To, L.V (I).Promo, White);
            if not Move_Validation.Is_In_Check (White) then
               Restore (S);
               return 0;
            end if;
            Restore (S);
         end loop;
         return -Mate_Value + Ply;
      end if;

      --  In-tree and game-history repetition (same side to move) = draw.
      --  Respect Min_Rep_Ply so a null-move subtree cannot false-match across
      --  the skipped turn.
      Key := Cur_Key;
      Key_Stack (Ply) := Key;
      declare
         J     : Integer := Ply - 2;
         H_End : constant Integer := Search_Integration.History_Count - 1;
         H_Beg : constant Integer :=
           Integer'Max (1, Search_Integration.History_Count
                           - Search_Integration.Fifty_Move_Counter);
      begin
         while J >= Integer (Min_Rep_Ply) loop
            if Key_Stack (J) = Key then
               return 0;
            end if;
            J := J - 2;
         end loop;
         if Min_Rep_Ply = 0 then
            for H in H_Beg .. H_End loop
               if Search_Integration.History (H) = Key then
                  return 0;
               end if;
            end loop;
         end if;
      end;

      --  TT probe
      if TT /= null and then TT_Size > 0 then
         declare
            E : TT_Entry renames TT (TT_Index (Key));
            V : Integer;
         begin
            if E.Key = Key and then E.Generation = TT_Generation then
               TT_Move := Unpack_Move (E.Best_Code);
               if Integer (E.Depth) >= Depth and then Beta - Alpha <= 1 then
                  V := From_TT (E.Score, Ply);
                  if E.Flag = Exact
                    or else (E.Flag = Lower and then V >= Beta)
                    or else (E.Flag = Upper and then V <= Alpha)
                  then
                     return V;
                  end if;
               end if;
            end if;
         end;
      end if;

      if Ply >= Max_Ply - 1 then
         return Eval_Side (White);
      end if;
      In_Check := Move_Validation.Is_In_Check (White);

      --  Null move pruning
      if Null_Ok and then not In_Check and then Depth >= 3
        and then abs Beta < Mate_Threshold
        and then Has_Pieces (White)
        and then Eval_Side (White) >= Beta
      then
         declare
            KS : Key_Snapshot;
         begin
            Save (S);
            Save_Key (KS);
            if Cur_Ep_Hashed /= 0 then
               Cur_Key := Cur_Key xor BCH_Hash.Hash_Ep (Cur_Ep_Hashed);
               Cur_Ep_Hashed := 0;
            end if;
            Move_Validation.En_Passant_Sq := 0;
            Cur_Key := Cur_Key xor BCH_Hash.Hash_Side;
            Cur_Half_Move := 0;
            Score := -Search
              (not White, Depth - 3, -Beta, -Beta + 1, Ply + 1,
               Null_Ok => False, Min_Rep_Ply => Ply + 1);
            Restore_Key (KS);
            Restore (S);
         end;
         if Aborted then
            return 0;
         end if;
         if Score >= Beta then
            return Beta;
         end if;
      end if;

      if In_Check and then Ply < Max_Ply - 16 then
         Depth := Depth + 1;   --  check extension
      end if;

      Gen (White, Captures_Only => False, L => L);
      for I in 1 .. L.N loop
         if L.V (I) = TT_Move then
            Sc (I) := 1_000_000;
         else
            Sc (I) := Order_Score (L.V (I), Ply);
         end if;
      end loop;

      --  Own king square, located once per node for the pin-alignment
      --  legality filter below.
      King_Sq := Move_Validation.Find_King (White);

      loop
         K := Pick (Sc, L.N);
         exit when K = 0;
         declare
            M           : constant Move_Rec := L.V (K);
            Cap         : constant Boolean := Is_Capture (M);
            --  Pre-make board facts (the declare block runs before Make_Move).
            Mover       : constant Integer := Pvalidade.Tabuleiro (M.From);
            Target_Occ  : constant Boolean := Pvalidade.Tabuleiro (M.To) /= 0;
            Is_EP_Move  : constant Boolean :=
              abs Mover = 1 and then not Target_Occ
                and then Move_Validation.File_Of (M.From)
                         /= Move_Validation.File_Of (M.To);

            --  A quiet, non-king move from a square that is not aligned with
            --  the own king cannot expose the king (no ray opens, the landing
            --  square stays occupied) and cannot create a self-attack. Only
            --  king moves, in-check nodes, en-passant captures (a third square
            --  is vacated) and king-aligned movers need the legality probe.
            --  Alignment is explicit (Ray_Between is 0 both for unaligned
            --  squares AND for directly adjacent squares on a ray).
            function Move_Needs_Legality_Probe return Boolean is
            begin
               return In_Check
                 or else abs Mover = 999
                 or else Is_EP_Move
                 --  King_Sq = 0 (king captured deeper in tree) follows the
                 --  Is_In_Check convention: no own king, nothing to expose.
                 or else (King_Sq /= 0
                          and then Squares_Aligned (King_Sq, M.From));
            end Move_Needs_Legality_Probe;

            R  : Integer := 0;
            KS : Key_Snapshot;
         begin
            Save (S);
            Save_Key (KS);
            Apply_Move (M.From, M.To, M.Promo, White);
            if not Move_Needs_Legality_Probe then
               null;   --  provably legal: skip the probe
            elsif Move_Validation.Is_In_Check (White) then
               Restore_Key (KS);
               Restore (S);
               goto Next_Move;
            end if;
            Legal := Legal + 1;

            if Legal = 1 then
               Score := -Search (not White, Depth - 1, -Beta, -Alpha, Ply + 1,
                                 Null_Ok => True, Min_Rep_Ply => Min_Rep_Ply);
            else
               --  Gives-check is only consumed by the LMR conjuncts; the
               --  inlined probe below is evaluated lazily by short-circuit.
               if Depth >= 3 and then Legal > 3 and then not In_Check
                 and then not Cap and then M.Promo = 0
                 and then abs Pvalidade.Tabuleiro (M.To) /= 7
                 and then M /= Killers (Ply) (1) and then M /= Killers (Ply) (2)
                 and then not Move_Validation.Is_In_Check (not White)
               then
                  R := (if Legal > 10 and then Depth >= 5 then 2 else 1);
               end if;
               Score := -Search (not White, Depth - 1 - R, -Alpha - 1, -Alpha, Ply + 1,
                                 Null_Ok => True, Min_Rep_Ply => Min_Rep_Ply);
               if not Aborted and then Score > Alpha and then R > 0 then
                  Score := -Search (not White, Depth - 1, -Alpha - 1, -Alpha, Ply + 1,
                                    Null_Ok => True, Min_Rep_Ply => Min_Rep_Ply);
               end if;
               if not Aborted and then Score > Alpha and then Score < Beta then
                  Score := -Search (not White, Depth - 1, -Beta, -Alpha, Ply + 1,
                                    Null_Ok => True, Min_Rep_Ply => Min_Rep_Ply);
               end if;
            end if;
            Restore_Key (KS);
            Restore (S);
            if Aborted then
               return 0;
            end if;

            if Score > Best then
               Best := Score;
               Best_Move := M;
               if Score > Alpha then
                  Alpha := Score;
                  PV_Table (Ply) (1) := M;
                  PV_Length (Ply) := 1;
                  for I in 1 .. PV_Length (Ply + 1) loop
                     exit when I + 1 > Max_Ply;
                     PV_Table (Ply) (I + 1) := PV_Table (Ply + 1) (I);
                     PV_Length (Ply) := I + 1;
                  end loop;
                  if Alpha >= Beta then
                     if not Cap and then M /= Killers (Ply) (1) then
                        Killers (Ply) (2) := Killers (Ply) (1);
                        Killers (Ply) (1) := M;
                     end if;
                     TT_Store (Key, Depth, Best, Lower, M, Ply);
                     return Best;
                  end if;
               end if;
            end if;
         end;
         <<Next_Move>>
      end loop;

      if Legal = 0 then
         return (if In_Check then -Mate_Value + Ply else 0);
      end if;
      TT_Store (Key, Depth, Best,
                (if Best <= Alpha_Orig then Upper else Exact), Best_Move, Ply);
      return Best;
   end Search;

   ----------------------------------------------------------------------------
   --  Root verification
   ----------------------------------------------------------------------------

   function Verify
     (White_To_Move      : Boolean;
      Chosen_From, Chosen_To, Chosen_Promo : Integer;
      Budget_Ms          : Natural;
      Max_Depth          : Positive := 12;
      Margin_Cp          : Natural := Veto_Margin_Cp;
      Report_Progress    : Boolean := False;
      Searchmoves_Filter : Move_Gen.Move_List := Empty_Move_List;
      Mate_Target        : Natural := 0) return Verify_Result
   is
      R          : Verify_Result;
      Root_State : Snapshot;
      L          : Move_List;
      Chosen_Idx : Natural := 0;
      Prev_Best  : Natural := 0;
   begin
      Save (Root_State);
      Aborted  := False;
      Nodes    := 0;
      Nodes_Global_Base := TT_Types.Nodes_Searched;
      Sel      := 0;
      Killers  := [others => [others => No_Move]];
      Apply_Hash_Resize;
      --  Generation stamping replaces full-table clearing between calls.
      if TT_Generation < Interfaces.Unsigned_16'Last then
         TT_Generation := TT_Generation + 1;
      else
         if TT /= null then
            TT.all := [others => (Key => 0, Score => 0, Best_Code => 0,
                                  Generation => 0, Depth => -1, Flag => Exact)];
         end if;
         TT_Generation := 1;
      end if;
      TT_Used := 0;
      Deadline := Clock + Milliseconds (Integer'Max (Budget_Ms, 1));
      Hard_Deadline := Deadline + Milliseconds
        (Integer'Min (50, Integer'Max (5, Budget_Ms / 10)));

      Generate_Legal_Moves (White_To_Move, L);
      if Searchmoves_Filter.N > 0 then
         declare
            Filtered : Move_List;
            Keep     : Boolean;
         begin
            Filtered.N := 0;
            for I in 1 .. L.N loop
               Keep := False;
               for J in 1 .. Searchmoves_Filter.N loop
                  if L.V (I).From = Searchmoves_Filter.V (J).From
                    and then L.V (I).To = Searchmoves_Filter.V (J).To
                    and then (Searchmoves_Filter.V (J).Promo = 0
                              or else L.V (I).Promo = Searchmoves_Filter.V (J).Promo)
                  then
                     Keep := True;
                     exit;
                  end if;
               end loop;
               if Keep and then Filtered.N < Max_Moves then
                  Filtered.N := Filtered.N + 1;
                  Filtered.V (Filtered.N) := L.V (I);
               end if;
            end loop;
            L := Filtered;
         end;
      end if;

      if L.N = 0 then
         TT_Types.Nodes_Searched := Nodes_Global_Base + Nodes;
         R.Nodes := Nodes;
         In_Verify_Search   := False;
         Verify_Attack_Eval := False;
         Verify_Development := False;
         Restore (Root_State);
         return R;
      end if;

      Verify_Attack_Eval := Needs_Attack_Evaluation;
      Verify_Development := Needs_Development;
      In_Verify_Search   := True;

      for I in 1 .. L.N loop
         if L.V (I).From = Chosen_From and then L.V (I).To = Chosen_To
           and then (L.V (I).Promo = Chosen_Promo
                     or else (Chosen_Promo = 0 and then L.V (I).Promo = 20))
         then
            Chosen_Idx := I;
            exit;
         end if;
      end loop;

      Cur_Key := Search_Integration.Root_Position_Key (White_To_Move);
      Cur_Half_Move := Natural'Max (0, Search_Integration.Fifty_Move_Counter);
      Cur_Ep_Hashed :=
        (if Move_Validation.En_Passant_Sq /= 0
           and then Search_Integration.Has_Legal_En_Passant_Capture
                      (White_To_Move, Move_Validation.En_Passant_Sq)
         then Move_Validation.En_Passant_Sq
         else 0);
      Key_Stack (0) := Cur_Key;

      for D in 1 .. Max_Depth loop
         --  Depth 1 is exempt only from the private soft deadline; shared
         --  aborts (stop, node limit) still bound it via Tick.
         Abort_Allowed := D > 1;
         declare
            Sc        : Score_Array;
            S         : Snapshot;
            Score     : Integer;
            Alpha     : Integer;
            It_Chosen : Integer := -Mate_Value;
            It_Best   : Integer := -Infinity;
            It_Idx    : Natural := Chosen_Idx;
            It_PV     : PV_Array;
            It_PV_Len : Natural := 0;
            Better    : Boolean := False;
            K         : Natural;
            Chosen_PV     : PV_Array;
            Chosen_PV_Len : Natural := 0;

            procedure Capture_PV (Idx : Natural) is
            begin
               It_PV (1) := L.V (Idx);
               It_PV_Len := 1;
               for I in 1 .. PV_Length (1) loop
                  exit when I + 1 > Max_Ply;
                  It_PV (I + 1) := PV_Table (1) (I);
                  It_PV_Len := I + 1;
               end loop;
            end Capture_PV;

            procedure Commit is
            begin
               R.Valid        := True;
               R.Depth        := D;
               R.Seldepth     := Integer'Max (Sel, D);
               R.Chosen_Score := It_Chosen;
               R.Best_Score   := It_Best;
               R.Best         := L.V (It_Idx);
               --  Only override the cascade on robust evidence: a completed
               --  depth >= 6, a gap >= 250 cp, or a mate on either side.
               R.Replaced     := It_Idx /= Chosen_Idx
                 and then (Chosen_Idx = 0
                           or else D >= 6
                           or else It_Best - It_Chosen >= 250
                           or else (It_Chosen = 0 and then Chosen_PV_Len = 1
                                    and then Eval_Side (White_To_Move) >= 50
                                    and then It_Best > 0)
                           or else abs It_Best >= Mate_Threshold
                           or else abs It_Chosen >= Mate_Threshold);
               if not R.Replaced and then Chosen_Idx /= 0 then
                  R.Best       := L.V (Chosen_Idx);
                  R.Best_Score := It_Chosen;
                  R.PV         := Chosen_PV;
                  R.PV_Len     := Chosen_PV_Len;
               else
                  R.PV           := It_PV;
                  R.PV_Len       := It_PV_Len;
               end if;
            end Commit;
         begin
            if Chosen_Idx /= 0 then
               declare
                  Root_KS : Key_Snapshot;
               begin
                  Save (S);
                  Save_Key (Root_KS);
                  Apply_Move (L.V (Chosen_Idx).From, L.V (Chosen_Idx).To,
                              L.V (Chosen_Idx).Promo, White_To_Move);
                  Score := -Search (not White_To_Move, D - 1, -Infinity, Infinity, 1);
                  Restore_Key (Root_KS);
                  Restore (S);
               end;
               exit when Aborted;   --  keep the previous completed depth
               It_Chosen := Score;
               It_Best   := Score;
               Capture_PV (Chosen_Idx);
               Chosen_PV     := It_PV;
               Chosen_PV_Len := It_PV_Len;
               --  An alternative must beat the cascade move by the margin,
               --  unless the cascade move immediately repeats a game-history
               --  position (It_Chosen = 0, Chosen_PV_Len = 1) while ahead.
               if Score = 0 and then Chosen_PV_Len = 1
                 and then Eval_Side (White_To_Move) >= 50
               then
                  Alpha := 0;
               else
                  Alpha :=
                    (if abs Score >= Mate_Threshold then Score
                     else Integer (Long_Long_Integer'Min
                            (Long_Long_Integer (Infinity - 1),
                             Long_Long_Integer (Score) + Long_Long_Integer
                               ((if (for some I in 1 .. L.N => L.V (I).Promo /= 0)
                                 then Natural'Min (1, Margin_Cp) else Margin_Cp)) - 1)));
               end if;
            else
               Alpha := -Infinity;
            end if;

            for I in 1 .. L.N loop
               if I = Chosen_Idx then
                  Sc (I) := Skip;
               elsif I = Prev_Best then
                  Sc (I) := 100_000;
               else
                  Sc (I) := Order_Score (L.V (I), 0);
               end if;
            end loop;

            loop
               K := Pick (Sc, L.N);
               exit when K = 0;
               declare
                  Root_KS : Key_Snapshot;
               begin
                  Save (S);
                  Save_Key (Root_KS);
                  Apply_Move (L.V (K).From, L.V (K).To, L.V (K).Promo, White_To_Move);
                  Score := -Search (not White_To_Move, D - 1, -Infinity, -Alpha, 1);
                  Restore_Key (Root_KS);
                  Restore (S);
               end;
               exit when Aborted;
               if Score > Alpha then
                  Alpha   := Score;
                  It_Best := Score;
                  It_Idx  := K;
                  Better  := True;
                  Capture_PV (K);
               end if;
            end loop;

            if Aborted then
               --  Discard partial iterations once depth 1 has completed so
               --  R.Depth strictly matches the deepest finished iteration.
               if not R.Valid and then Better and then Chosen_Idx /= 0 then
                  Commit;
               end if;
               exit;
            end if;

            if It_Idx = 0 then
               It_Idx := 1;   --  cascade move illegal and nothing searched
            end if;
            Commit;
            if Report_Progress then
               TT_Types.Nodes_Searched := Nodes_Global_Base + Nodes;
               declare
                  PV_Text : String (1 .. 512);
                  Last    : Natural := 0;
               begin
                  for I in 1 .. R.PV_Len loop
                     declare
                        M : constant String := Move_Gen.Move_To_UCI (R.PV (I));
                     begin
                        if Last > 0 then
                           Last := Last + 1;
                           PV_Text (Last) := ' ';
                        end if;
                        PV_Text (Last + 1 .. Last + M'Length) := M;
                        Last := Last + M'Length;
                     end;
                  end loop;
                  Search_Integration.Report_PV
                    (D, R.Seldepth, R.Best_Score, PV_Text (1 .. Last),
                     Hashfull => TT_Hash_Full);
               end;
            end if;
            Prev_Best := It_Idx;
            if Mate_Target > 0 then
               exit when It_Best >= Mate_Value - (2 * Integer (Mate_Target) - 1);
            else
               exit when It_Best >= Mate_Threshold and then D >= 2;
            end if;
         end;
      end loop;

      TT_Types.Nodes_Searched := Nodes_Global_Base + Nodes;
      R.Nodes := Nodes;
      In_Verify_Search   := False;
      Verify_Attack_Eval := False;
      Verify_Development := False;
      Restore (Root_State);
      return R;
   exception
      when others =>
         TT_Types.Nodes_Searched := Nodes_Global_Base + Nodes;
         In_Verify_Search   := False;
         Verify_Attack_Eval := False;
         Verify_Development := False;
         Restore (Root_State);
         R.Valid := False;
         return R;
   end Verify;

end Tactical_Search;
