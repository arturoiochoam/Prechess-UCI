-------------------------------------------------------------------------------
--  PRECHESS UCI - MAILBOX BOARD REPRESENTATION & MOVEMENT ORACLE
--
--  Module:        Pvalidade (Body)
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        José Lauro Strapasson (Original 2001 Core)
--                 Arthur Matheus (Ada 2022 Modernization, Telemetry & Bounds Check)
--  Date:          2001-2026
-------------------------------------------------------------------------------

with TT_Types;

package body Pvalidade is

   ----------------------------------------------------------------------------
   --  CORE MOVEMENT VALIDATION FUNCTION
   ----------------------------------------------------------------------------
   function Validade (A, B : in Integer) return Boolean is
      Resultado : Boolean := False;
      Ai, Aj    : Integer;
      Bi, Bj    : Integer;
      Reta_L1   : Integer;
      Reta_L2   : Integer;

      -------------------------------------------------------------------------
      --  PAWN GEOMETRIC MOVES
      -------------------------------------------------------------------------
      procedure Peao_Anda is
      begin
         if Tabuleiro (A) = 1 then -- White Pawn (+1)
            -- Single step forward (+1 rank)
            if Aj = Bj and Bi - Ai = 1 then
               Resultado := True;
            else
               Resultado := False;
            end if;
            -- Initial two-square double push from rank 2 (Ai=2 -> Bi=4)
            if Aj = Bj and Bi = 4 and Ai = 2 and Tabuleiro (16 + Aj) = 0 then
               Resultado := True;
            end if;
         else -- Black Pawn (-1)
            -- Single step forward (-1 rank)
            if Aj = Bj and Ai - Bi = 1 then
               Resultado := True;
            else
               Resultado := False;
            end if;
            -- Initial two-square double push from rank 7 (Ai=7 -> Bi=5)
            if Aj = Bj and Bi = 5 and Ai = 7 and Tabuleiro (40 + Aj) = 0 then
               Resultado := True;
            end if;
         end if;
      end Peao_Anda;

      procedure Peao_Come is
      begin
         if Tabuleiro (A) = 1 then -- White Pawn (+1) diagonal capture
            if Bi - Ai = 1 and (Bj - Aj = 1 or Bj - Aj = -1) then
               Resultado := True;
            else
               Resultado := False;
            end if;
         else -- Black Pawn (-1) diagonal capture
            if Ai - Bi = 1 and (Bj - Aj = 1 or Bj - Aj = -1) then
               Resultado := True;
            else
               Resultado := False;
            end if;
         end if;
      end Peao_Come;

      procedure Peao is
      begin
         if Tabuleiro (B) = 0 then
            Peao_Anda;
         else
            Peao_Come;
         end if;
      end Peao;

      -------------------------------------------------------------------------
      --  BISHOP / DIAGONAL RAY CASTING
      -------------------------------------------------------------------------
      procedure Bispo is
         Soma      : Integer := 0;
         Diferenca : Integer := 0;
      begin
         Reta_L1 := 0;
         Reta_L2 := 0;
         Soma := Ai + Aj;
         Diferenca := Ai - Aj;

         -- Diagonal where rank + file is constant (anti-diagonal)
         if Aj < Bj then
            for E in Aj + 1 .. Bj - 1 loop
               if Soma - E >= 1 and Soma - E <= 8 then
                  if Tabuleiro ((Soma - E - 1) * 8 + E) /= 0 then
                     Reta_L1 := 1;
                  end if;
               end if;
            end loop;
         elsif Bj < Aj then
            for E in Bj + 1 .. Aj - 1 loop
               if Soma - E >= 1 and Soma - E <= 8 then
                  if Tabuleiro ((Soma - E - 1) * 8 + E) /= 0 then
                     Reta_L1 := 1;
                  end if;
               end if;
            end loop;
         end if;

         -- Diagonal where rank - file is constant (main diagonal)
         if Aj < Bj then
            for E in Aj + 1 .. Bj - 1 loop
               if Diferenca + E >= 1 and Diferenca + E <= 8 then
                  if Tabuleiro ((Diferenca + E - 1) * 8 + E) /= 0 then
                     Reta_L2 := 1;
                  end if;
               end if;
            end loop;
         elsif Bj < Aj then
            for E in Bj + 1 .. Aj - 1 loop
               if Diferenca + E >= 1 and Diferenca + E <= 8 then
                  if Tabuleiro ((Diferenca + E - 1) * 8 + E) /= 0 then
                     Reta_L2 := 1;
                  end if;
               end if;
            end loop;
         end if;

         if (Aj + Ai = Bj + Bi and Reta_L1 = 0)
           or (Aj - Ai = Bj - Bi and Reta_L2 = 0)
         then
            Resultado := True;
         else
            Resultado := False;
         end if;
      end Bispo;

      -------------------------------------------------------------------------
      --  KNIGHT / LEAP ARITHMETIC
      -------------------------------------------------------------------------
      procedure Cavalo is
      begin
         -- L-shape movement: (dx^2 = 4 and dy^2 = 1) or (dx^2 = 1 and dy^2 = 4)
         if ((Bj - Aj)**2 = 4 and (Bi - Ai)**2 = 1)
           or ((Bj - Aj)**2 = 1 and (Bi - Ai)**2 = 4)
         then
            Resultado := True;
         else
            Resultado := False;
         end if;
      end Cavalo;

      -------------------------------------------------------------------------
      --  ROOK / ORTHOGONAL RAY CASTING
      -------------------------------------------------------------------------
      procedure Torre is
         Reta_I : Integer := 0;
         Reta_J : Integer := 0;
      begin
         -- Direction I: Scan along rank (horizontal)
         if Aj < Bj then
            for C in Aj + 1 .. Bj - 1 loop
               if Tabuleiro ((Ai - 1) * 8 + C) /= 0 then
                  Reta_I := 1;
               end if;
            end loop;
         elsif Bj < Aj then
            for C in Bj + 1 .. Aj - 1 loop
               if Tabuleiro ((Ai - 1) * 8 + C) /= 0 then
                  Reta_I := 1;
               end if;
            end loop;
         end if;

         -- Direction J: Scan along file (vertical)
         if Ai < Bi then
            for C in Ai + 1 .. Bi - 1 loop
               if Tabuleiro ((C - 1) * 8 + Aj) /= 0 then
                  Reta_J := 1;
               end if;
            end loop;
         elsif Bi < Ai then
            for C in Bi + 1 .. Ai - 1 loop
               if Tabuleiro ((C - 1) * 8 + Aj) /= 0 then
                  Reta_J := 1;
               end if;
            end loop;
         end if;

         if Bj = Aj and Reta_J = 0 then
            Resultado := True;
         elsif Bi = Ai and Reta_I = 0 then
            Resultado := True;
         else
            Resultado := False;
         end if;
      end Torre;

      -------------------------------------------------------------------------
      --  QUEEN / COMPOSITE SLIDING
      -------------------------------------------------------------------------
      procedure Dama is
      begin
         Torre;
         if not Resultado then
            Bispo;
         end if;
      end Dama;

      -------------------------------------------------------------------------
      --  KING / 1-SQUARE STEP
      -------------------------------------------------------------------------
      procedure Rei is
      begin
         if ((Bj - Aj = 0) or (Bj - Aj)**2 = 1)
           and ((Bi - Ai = 0) or (Bi - Ai)**2 = 1)
         then
            Resultado := True;
         else
            Resultado := False;
         end if;
      end Rei;

      -------------------------------------------------------------------------
      --  COORDINATE TRANSLATION: 1..64 -> (Rank 1..8, File 1..8)
      -------------------------------------------------------------------------
      procedure Disposicao is
      begin
         Ai := (A - 1) / 8 + 1;
         Bi := (B - 1) / 8 + 1;
         Aj := (A - 1) mod 8 + 1;
         Bj := (B - 1) mod 8 + 1;
      end Disposicao;

   begin
      --  Boundary defense: reject out-of-bounds indices immediately
      if A < 1 or A > 64 or B < 1 or B > 64 then
         return False;
      end if;

      --  Short-circuit null moves, vacant source, and same-colour captures
      if A = B then
         return False;
      end if;
      if Tabuleiro (A) = 0 then
         return False;
      end if;
      if Tabuleiro (A) * Tabuleiro (B) > 0 then
         return False;
      end if;

      --  Increment global atomic search node telemetry counter
      TT_Types.Nodes_Searched := TT_Types.Nodes_Searched + 1;

      --  Translate 1D coordinates to 2D rank/file coordinates
      Disposicao;

      --  Dispatch to piece-specific geometry validator
      case abs Tabuleiro (A) is
         when 1      => Peao;
         when 3      => Bispo;
         when 4      => Cavalo;
         when 7      => Torre;
         when 20     => Dama;
         when 999    => Rei;
         when others => Resultado := False;
      end case;

      return Resultado;
   end Validade;

end Pvalidade;
