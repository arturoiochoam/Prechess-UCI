with Pvalidade;
with Search_Integration; use Pvalidade;
with Time_Management;

package body pprechess2 is
--Esse pacote contem o procedimento prechess2 que � o programa de xadrez propriamente dito.
--Mas aqui ele � chamado pelo prechess.adb que � interface do usuario e se comporta como programa principal.


   --  Tapered PeSTO-sourced piece-square tables for the positional tie-break
   --  (v0.7.9.7). All tables are written from the ENGINE'S OWN perspective: the
   --  board is mirrored for Black by Search_Integration.Flip_Board before this
   --  package runs, so one self-relative set serves both colours. Square index is
   --  (rank-1)*8 + file, rank 1 = own back rank, advancing toward rank 8;
   --  files 1..8 = a..h. Row 1 of each aggregate is the own back rank (squares
   --  1..8), row 8 the far rank.
   --
   --  These ONLY break ties among quiet moves the decision cascade already
   --  considers equally safe -- they do not change what is "safe" anywhere, only
   --  which equally-safe move is kept when no tactical tier decides.
   subtype Square_Index is Integer range 1 .. 64;
   subtype Phase_256 is Integer range 0 .. 256;
   type PST_Array is array (Square_Index) of Integer;

   --  Opening-only pawn tie-break from the 0.7.9.6 PST. The tapered
   --  PeSTO middlegame pawn table rewards b3/b6 more than central pawn
   --  play from the untouched starting material, which reintroduced the
   --  old b-pawn shuffle at the root. Keep the tapered pawn table for
   --  non-opening phases, but preserve the proven opening pawn ordering.
   PST_Pawn_Opening : constant PST_Array := (
        0,    0,    0,    0,    0,    0,    0,    0,
        0,    0,    5,    5,    5,    5,    0,    0,
        5,    5,   10,   15,   15,   10,    5,    5,
       10,   10,   20,   25,   25,   20,   10,   10,
       15,   20,   30,   35,   35,   30,   20,   15,
       25,   30,   35,   40,   40,   35,   30,   25,
       35,   35,   40,   45,   45,   40,   35,   35,
       45,   45,   45,   45,   45,   45,   45,   45);

   PST_Pawn_MG : constant PST_Array := (
        0,    0,    0,    0,    0,    0,    0,    0,
      -22,   38,   24,  -15,  -23,  -20,   -1,  -35,
      -12,   33,    3,    3,  -10,   -4,   -4,  -26,
      -25,   10,    6,   17,   12,   -5,   -2,  -27,
      -23,   17,   12,   23,   21,    6,   13,  -14,
      -20,   25,   56,   65,   31,   26,    7,   -6,
      -11,   34,  126,   68,   95,   61,  134,   98,
        0,    0,    0,    0,    0,    0,    0,    0);

   PST_Pawn_EG : constant PST_Array := (
        0,    0,    0,    0,    0,    0,    0,    0,
       -7,    2,    0,   13,   10,    8,    8,   13,
       -8,   -1,   -5,    0,    1,   -6,    7,    4,
       -1,    3,   -8,   -7,   -7,   -3,    9,   13,
       17,   17,    4,   -2,    5,   13,   24,   32,
       84,   82,   53,   56,   67,   85,  100,   94,
      187,  165,  132,  147,  134,  158,  173,  178,
        0,    0,    0,    0,    0,    0,    0,    0);

   PST_Knight_MG : constant PST_Array := (
      -23,  -19,  -28,  -17,  -33,  -58,  -21, -105,
      -19,  -14,   18,   -1,   -3,  -12,  -53,  -29,
      -16,   25,   17,   19,   10,   12,   -9,  -23,
       -8,   21,   19,   28,   13,   16,    4,  -13,
       22,   18,   69,   37,   53,   19,   17,   -9,
       44,   73,  129,   84,   65,   37,   60,  -47,
      -17,    7,   62,   23,   36,   72,  -41,  -73,
     -107,  -15,  -97,   61,  -49,  -34,  -89, -167);

   PST_Knight_EG : constant PST_Array := (
      -64,  -50,  -18,  -22,  -15,  -23,  -51,  -29,
      -44,  -23,  -20,   -2,   -5,  -10,  -20,  -42,
      -22,  -20,   -3,   10,   15,   -1,   -3,  -23,
      -18,    4,   17,   16,   25,   16,   -6,  -18,
      -18,    8,   11,   22,   22,   22,    3,  -17,
      -41,  -19,   -9,   -1,    9,   10,  -20,  -24,
      -52,  -24,  -25,   -9,   -2,  -25,   -8,  -25,
      -99,  -63,  -27,  -31,  -28,  -13,  -38,  -58);

   PST_Bishop_MG : constant PST_Array := (
      -21,  -39,  -12,  -13,  -21,  -14,   -3,  -33,
        1,   33,   21,    7,    0,   16,   15,    4,
       10,   18,   27,   14,   15,   15,   15,    0,
        4,   10,   12,   34,   26,   13,   13,   -6,
       -2,    7,   37,   37,   50,   19,    5,   -4,
       -2,   37,   50,   35,   40,   43,   37,  -16,
      -47,   18,   59,   30,  -13,  -18,   16,  -26,
       -8,    7,  -42,  -25,  -37,  -82,    4,  -29);

   PST_Bishop_EG : constant PST_Array := (
      -17,   -5,  -16,   -9,   -5,  -23,   -9,  -23,
      -27,  -15,   -9,    4,   -1,   -7,  -18,  -14,
      -15,   -7,    3,   13,   10,    8,   -3,  -12,
       -9,   -3,   10,    7,   19,   13,    3,   -6,
        2,    3,   10,   14,    9,   12,    9,   -3,
        4,    0,    6,   -2,   -1,    0,   -8,    2,
      -14,   -4,  -13,   -3,  -12,    7,   -4,   -8,
      -24,  -17,   -9,   -7,   -8,  -11,  -21,  -14);

   PST_Rook_MG : constant PST_Array := (
      -26,  -37,    7,   16,   17,    1,  -13,  -19,
      -71,   -6,   11,   -1,   -9,  -20,  -16,  -44,
      -33,   -5,    0,    3,  -17,  -16,  -25,  -45,
      -23,    6,   -7,    9,   -1,  -12,  -26,  -36,
      -20,   -8,   35,   24,   26,    7,  -11,  -24,
       16,   61,   45,   17,   36,   26,   19,   -5,
       44,   26,   67,   80,   62,   58,   32,   27,
       43,   31,    9,   63,   51,   32,   42,   32);

   PST_Rook_EG : constant PST_Array := (
      -20,    4,  -13,   -5,   -1,    3,    2,   -9,
       -3,  -11,   -9,   -9,    2,    0,   -6,   -6,
      -16,   -8,  -12,   -7,   -1,   -5,    0,   -4,
      -11,   -8,   -6,   -5,    4,    8,    5,    3,
        2,   -1,    1,    2,    1,   13,    3,    4,
       -3,   -5,   -3,    4,    5,    7,    7,    7,
        3,    8,    3,   -3,   11,   13,   13,   11,
        5,    8,   12,   12,   15,   18,   10,   13);

   PST_Queen_MG : constant PST_Array := (
      -50,  -31,  -25,  -15,   10,   -9,  -18,   -1,
        1,   -3,   15,    8,    2,   11,   -8,  -35,
        5,   14,    2,   -5,   -2,  -11,    2,  -14,
       -3,    3,   -4,   -2,  -10,   -9,  -26,   -9,
        1,   -2,   17,   -1,  -16,  -16,  -27,  -27,
       57,   47,   56,   29,    8,    7,  -17,  -13,
       54,   28,   57,  -16,    1,   -5,  -39,  -24,
       45,   43,   44,   59,   12,   29,    0,  -28);

   PST_Queen_EG : constant PST_Array := (
      -41,  -20,  -32,   -5,  -43,  -22,  -28,  -33,
      -32,  -36,  -23,  -16,  -16,  -30,  -23,  -22,
        5,   10,   17,    9,    6,   15,  -27,  -16,
       23,   39,   34,   31,   47,   19,   28,  -18,
       36,   57,   40,   57,   45,   24,   22,    3,
        9,   19,   35,   47,   49,    9,    6,  -20,
        0,   30,   25,   58,   41,   32,   20,  -17,
       20,   10,   19,   27,   27,   22,   22,   -9);

   PST_King_MG : constant PST_Array := (
       14,   24,  -28,    8,  -54,   12,   36,  -15,
        8,    9,  -16,  -43,  -64,   -8,    7,    1,
      -27,  -15,  -30,  -44,  -46,  -22,  -14,  -14,
      -51,  -33,  -44,  -46,  -39,  -27,   -1,  -49,
      -36,  -14,  -25,  -30,  -27,  -12,  -20,  -17,
      -22,   22,    6,  -20,  -16,    2,   24,   -9,
      -29,  -38,   -4,   -8,   -7,  -20,   -1,   29,
       13,    2,  -34,  -56,  -15,   16,   23,  -65);

   PST_King_EG : constant PST_Array := (
      -43,  -24,  -14,  -28,  -11,  -21,  -34,  -53,
      -17,   -5,    4,   14,   13,    4,  -11,  -27,
       -9,    7,   16,   23,   21,   11,   -3,  -19,
      -11,    9,   23,   27,   24,   21,   -4,  -18,
        3,   26,   33,   26,   27,   24,   22,   -8,
       13,   44,   45,   20,   15,   23,   17,   10,
       11,   23,   38,   17,   17,   14,   17,  -12,
      -17,    4,   15,  -11,  -18,  -18,  -35,  -74);

   type Piece_Code is (Pawn, Bishop, Knight, Rook, Queen, King);
   function To_Piece_Code (Piece : Integer) return Piece_Code is
      (case Piece is
          when 1    => Pawn,
          when 3    => Bishop,
          when 4    => Knight,
          when 7    => Rook,
          when 20   => Queen,
          when 999  => King,
          when others => Pawn);
   pragma Inline (To_Piece_Code);

   Total_Phase : constant := 24;
   Root_Game_Phase : Phase_256 := 0;

   function Phase_Weight (Piece : Integer) return Integer is
      (case abs Piece is
          when 4  => 1,
          when 3  => 1,
          when 7  => 2,
          when 20 => 4,
          when others => 0);
   pragma Inline (Phase_Weight);

   function Raw_Phase return Integer is
      Phase : Integer := 0;
   begin
      for Sq in Square_Index loop
         Phase := Phase + Phase_Weight (Tabuleiro (Sq));
      end loop;
      if Phase > Total_Phase then
         return Total_Phase;
      end if;
      return Phase;
   end Raw_Phase;

   function Compute_Game_Phase return Phase_256 is
      Missing_Phase : constant Integer := Total_Phase - Raw_Phase;
   begin
      return Phase_256 ((Missing_Phase * 256 + Total_Phase / 2) / Total_Phase);
   end Compute_Game_Phase;

   function Positional_Game_Phase return Integer is
   begin
      return Integer (Compute_Game_Phase);
   end Positional_Game_Phase;

   function Interpolate (MG, EG : Integer; Phase : Phase_256) return Integer is
      Phase_Int : constant Integer := Integer (Phase);
   begin
      return (MG * (256 - Phase_Int) + EG * Phase_Int) / 256;
   end Interpolate;
   pragma Inline (Interpolate);

   function Positional_Interpolate (MG, EG, Phase : Integer) return Integer is
   begin
      return Interpolate (MG, EG, Phase_256 (Phase));
   end Positional_Interpolate;

   function Score_With_Phase (Piece : Piece_Code; Sq : Square_Index; Phase : Phase_256) return Integer is
   begin
      case Piece is
         when Pawn   => return Interpolate (PST_Pawn_MG (Sq),   PST_Pawn_EG (Sq),   Phase);
         when Bishop => return Interpolate (PST_Bishop_MG (Sq), PST_Bishop_EG (Sq), Phase);
         when Knight => return Interpolate (PST_Knight_MG (Sq), PST_Knight_EG (Sq), Phase);
         when Rook   => return Interpolate (PST_Rook_MG (Sq),   PST_Rook_EG (Sq),   Phase);
         when Queen  => return Interpolate (PST_Queen_MG (Sq),  PST_Queen_EG (Sq),  Phase);
         when King   => return Interpolate (PST_King_MG (Sq),   PST_King_EG (Sq),   Phase);
      end case;
   end Score_With_Phase;
   pragma Inline (Score_With_Phase);

   function Positional_Test_Score (Piece, Sq, Phase : Integer) return Integer is
      Code : constant Piece_Code := To_Piece_Code (Piece);
   begin
      if Code = Pawn and then Phase = 0 then
         return PST_Pawn_Opening (Square_Index (Sq));
      end if;
      return Score_With_Phase (Code, Square_Index (Sq), Phase_256 (Phase));
   end Positional_Test_Score;

   --  Piece-aware quiet-move tie-break. Piece codes are the search's own:
   --  Pawn=1, Bishop=3, Knight=4, Rook=7, Queen=20, King=999.
   function Positional_Score (Piece : Piece_Code; Sq : Square_Index) return Integer is
   begin
      if Piece = Pawn and then Root_Game_Phase = 0 then
         return PST_Pawn_Opening (Sq);
      end if;
      return Score_With_Phase (Piece, Sq, Root_Game_Phase);
   end Positional_Score;
   pragma Inline (Positional_Score);


Procedure prechess2 is

 i,J: Integer:=1;  --Usados como memoria da 1a jogada; ver Segundo_Lance/Analize1/Analize2.

 --  Caches for the final decision cascade only (see note above the
 --  precompute loop, near "Aqui da xeque mate nele!"). Never read or
 --  written anywhere during the ply-1/2/3 trial-move search itself.
 Valid_Cache : array(1..64,1..64) of Boolean;
 Own_Piece   : array(1..64) of Boolean;
 Not_Own     : array(1..64) of Boolean;

 type Root_Move is record
    A : Integer;
    B : Integer;
 end record;
 type Root_Move_Array is array (1 .. 4096) of Root_Move;
 Root_Moves      : Root_Move_Array;
 Root_Move_Count : Natural := 0;

 --  The fallback tiers below (the "Aqui joga ... que nao perca nada"
 --  blocks) scan every (A,B) pair in ascending order and keep the pair
 --  whose Positional_Score (package-level, above) is >= the best so far
 --  -- i.e. among the moves the cascade already considers equally safe,
 --  they now keep the positionally best one. This was destination-file
 --  centrality only (Quiet_Move_Score), which treated a king's central
 --  step the same as a developing knight; it is now the piece-aware
 --  piece-square value. A full safety match is still required first; the
 --  score only decides which of several already-qualifying matches is
 --  kept, so what counts as a "safe" move is unchanged everywhere.

 Best_Positional_Score : Integer;

 type Draw_Effect is (No_Draw_Change, Reset_Draw, Add_Draw);

 procedure Select_Move (A, B : Integer; Effect : Draw_Effect) is
 begin
    cc := A;
    dd := B;
    Search_Integration.Report_UCI(A, B);
    case Effect is
       when No_Draw_Change => null;
       when Reset_Draw    => Zerar_Contagem_Empate := True;
       when Add_Draw      => Somar_Contagem_Empate := True;
    end case;
 end Select_Move;

 procedure Select_Positional_Move (A, B : Integer; Effect : Draw_Effect) is
    Score : constant Integer :=
      Positional_Score (To_Piece_Code (Tabuleiro (A)), B);
 begin
    if Score >= Best_Positional_Score then
       Best_Positional_Score := Score;
       Select_Move (A, B, Effect);
    end if;
 end Select_Positional_Move;

  procedure Alinha_Dama_Rei is
  Posicao_Dama, Posicao_Rei: Integer:=0;
  begin
     for A in 1..64 loop
      if Tabuleiro(A)=20 then Posicao_Dama:=A;end if;
      if Tabuleiro(A)=999 then Posicao_Rei:=A; end if;
     end loop;
     if Posicao_Dama /= 0 and then Posicao_Rei /= 0 then Tabuleiro(Posicao_Dama):=-3;
      if Validade(Posicao_Dama,Posicao_Rei)=True then Alinha(I,J):=True; else Alinha(I,J):=False; end if;
      Tabuleiro(Posicao_Dama):=20;
     end if; --So para evitar zebra caso nao tenha a Dama ou Rei!
     if Posicao_DAma /= 0 and then Posicao_Rei /= 0 then Tabuleiro(Posicao_Dama):=-7;
      if Validade(Posicao_Dama,Posicao_Rei)=True then Alinha(I,J):=True; end if;
      Tabuleiro(Posicao_Dama):=20;
     end if;
  end Alinha_Dama_Rei;

 --  Generalizes the four legacy functions Dama_Protegida / Torre_Protegida /
 --  Bispo_Protegido / Cavalo_Protegido, which were identical copies of this
 --  same loop differing only in one threshold constant. B is the square
 --  where the computer's piece just stood (now holding the capturing enemy
 --  piece); Piece_Threshold is the same per-piece constant the original
 --  functions used (Dama=-20, Torre=-7, Bispo=-3, Cavalo=-4). Behavior is
 --  byte-for-byte identical to the four originals at every call site:
 --  Dama_Protegida(L) = Protegida(L,-20), Torre_Protegida(L) = Protegida(L,-7),
 --  Bispo_Protegido(L) = Protegida(L,-3), Cavalo_Protegido(L) = Protegida(L,-4).
 --  The King is still deliberately excluded as a defender (Tabuleiro(C)/=999
 --  below), exactly as in the legacy code ("Nao quiz proteger com o Rei so
 --  para evitar o pior") -- this is an inherited evaluation simplification,
 --  not something this cleanup changes.
 function Protegida(B, Piece_Threshold : Integer) return Boolean is
 begin
  if Tabuleiro(B) > Piece_Threshold then
     return False;
  end if;
  --  Early-exit on the first defender: Validade is a pure geometry oracle
  --  (no board writes), so returning mid-scan is identical to the old
  --  "set Result and finish the loop" form -- just far fewer calls in the
  --  hot (k,l) trial loop that invokes this via Analize2.
  for C in 1 .. 64 loop
     if Validade(C,B)=True and Tabuleiro(C)>0 and Tabuleiro(C)/=999 then
        return True;
     end if;
  end loop;
  return False;
 end Protegida;

 procedure Analize3(i,J,K,L,M,N,Soma3l,Soma2l:integer) is

  --  Mirror of Protegida for the other side: does ANY of the person's
  --  pieces defend (i.e. could immediately recapture on) square Sq?
  --  Validade handles capture geometry for the person's pieces itself,
  --  including the person's pawn capture direction, because Sq holds a
  --  computer (positive) piece at the moment this is asked.
  function Person_Defends (Sq : Integer) return Boolean is
  begin
     for C in 1..64 loop
        if Tabuleiro(C) < 0 and then Validade(C,Sq) then
           return True;
        end if;
     end loop;
     return False;
  end Person_Defends;

  Ganho : constant Integer := Soma3l - Soma2l;
 begin
 if L /= N then --Isso seguinifica que a peca amecada ficou parada no 2 lance.
    --E' so para ser coerente com a definicao do que chamamos de ameacar.
  --
  --  Threat realism guard: the legacy version flagged a "threat" for ANY
  --  ply-3 capture of a piece that stayed put, without asking whether
  --  the capture would be good -- its own comment below Analize2 admits
  --  this needed improving ("nem sempre que der true ai voce
  --  efetivamente vai perder..."). A queen "threatening" a pawn-defended
  --  knight is an empty threat (queen takes knight, pawn takes queen),
  --  yet it satisfied the old test, and the cascade's threat tiers
  --  rank high enough that this produced real blunders (Qd8-f6 after
  --  1.e4 e5 2.Nf3, reported from an actual game). A threat now counts
  --  only if the capture wouldn't lose material on the spot: the target
  --  square is undefended by the person, OR the capturing piece's value
  --  (Tabuleiro(N), already standing on the captured square when
  --  Analize3 runs) is at most the captured piece's value.
  --  Freshness guard (see Raiz_Ja_Ameacado in the spec): a material
  --  threat counts only if the target was NOT already attacked on the
  --  root board -- maintaining an existing threat from a different
  --  square is not a reason to move. Check threats are exempt.
  if (Ganho = 999 or else not Raiz_Ja_Ameacado(N))
    and then (Tabuleiro(N) <= Ganho or else not Person_Defends(N))
  then
     if Ganho=1   then Jogada_ameacaP(I,J):=True; end if;
     if Ganho=3   then Jogada_ameacaB(I,J):=True; end if;
     if Ganho=4   then Jogada_ameacaC(I,J):=True; end if;
     if Ganho=7   then Jogada_ameacaT(I,J):=True; end if;
     if Ganho=20  then Jogada_ameacaD(I,J):=True; end if;
     if Ganho=999 then Jogada_ameacaR(I,J):=True; end if;
  end if;
 end if;
 end Analize3;

 procedure Analize2(i,J,K,L,Soma2l,Soma1l:integer) is

  procedure Check_Promotion_Threat is
  begin
     --  NOTE: deliberately evaluated here in Analize2 (the ply-2 board,
     --  after the opponent's simulated reply to this root move), not in
     --  Analize1 (the ply-1 board) as the original stale comment below
     --  used to suggest ("Essa linha acima deveria estar na analize 1").
     --  Analize1 and Analize2 run against two DIFFERENT board states, so
     --  moving this to Analize1 would change which root moves get flagged
     --  as allowing a human promotion -- a real behavior change, not a
     --  cleanup -- so it stays exactly where the legacy engine had it.
     for A in 1..8 loop
        if Tabuleiro(A)=-1 then Jogada_Promove_Humano(I,J):=True; end if;
        if Tabuleiro(65-A)=1 then Jogada_Promove_Maquina(I,J):=True; end if;
     end loop;
  end Check_Promotion_Threat;

 begin

  if Soma2l - Soma1l=-1   then BackupPeao:=Jogada_PerdeP(I,J); Jogada_PerdeP(I,J):=True; end if;
  if Soma2l - Soma1l=-3  and Protegida(L,-3)=false  then Jogada_PerdeB(I,J):=True; end if;
  if Soma2l - Soma1l=-4  and Protegida(L,-4)=false then Jogada_PerdeC(I,J):=True; end if;
  if Soma2l - Soma1l=-7  and Protegida(L,-7)=false  then Jogada_PerdeT(I,J):=True; end if;
  if Soma2l - Soma1l=-20 and Protegida(L,-20)=false   then Jogada_PerdeD(I,J):=True; end if;
  if Soma2l - Soma1l=-999 then Jogada_PerdeR(I,J):=True; end if;
 --Essa parte deve ser aprimorada pois nem sempre que der true ai voce efetivamente vai perder o Rei, a Dama
 --Usarei as funcoes Dama_protegida, torre_protegida, etc. :).
  Check_Promotion_Threat;
 end Analize2;

 procedure Analize1(i,J,Soma1l,Soma0l:integer) is
 begin
  if Soma1l - Soma0l=1   then Jogada_PegaP(I,J):=True; end if; --Peao
  if Soma1l - Soma0l=3   then Jogada_PegaB(I,J):=True; end if; --Bispo
  if Soma1l - Soma0l=4   then Jogada_PegaC(I,J):=True; end if; --Cavalo
  if Soma1l - Soma0l=7   then Jogada_PegaT(I,J):=True; end if; --Torre
  if Soma1l - Soma0l=20  then Jogada_PegaD(I,J):=True; end if; --Dama
  if Soma1l - Soma0l=999 then Jogada_PegaR(I,J):=True; end if; --Rei
 end Analize1;

 procedure Mate(I,J:Integer) is
 --E' um porcedimento e nao uma funcao pois ele recebe
 --como dado de entrada somente a posicao do tabuleiro.
   Temp1, Temp2: Integer;
   Morre: array(1..64,1..64) of Boolean;
   Exequemate_T: array(1..64,1..64) of Boolean;
 procedure S_Lance(Ii,Jj:Integer)  is --Procedimento dentro do Mate.
  begin
 --  Deliberately NO time-abort here (one used to be): S_Lance feeds the
 --  mate / check-exposure flags (Exequemate, Expoem_A_Xeque, MataEle2)
 --  the decision cascade depends on for EVERY root move. Aborting
 --  mid-scan left those flags computed for early root moves and missing
 --  for later ones, and the cascade -- which has no notion of "flag not
 --  computed" -- would then prefer exactly the unvetted moves (seen as
 --  f7-f6-style junk under a tight clock). The full ply-1..3 pass costs
 --  only tens of milliseconds, so it always runs to completion; the
 --  clock is enforced by the expensive ply-4..16 chain instead, whose
 --  entry checks skip it cleanly per root move.
  for kk in 1..64 loop
       if tabuleiro(kk) < 0 then   --Ou seja, se tem uma pe�a da pessoa.
          for ll in 1..64 loop
            if tabuleiro(ll) = 999 then --O uso do and deixaria mais lento!
             if validade(kk,ll)=true then
             Morre(II,JJ):=True;
             --O adversario comeu o Rei do computador!!!
             end if;
            end if;
          end loop;
       end if;
  end loop;
  end S_Lance;

 begin --Incio do Mate.

 Exequemate_T(I,J):=true;

 for ii in 1..64 loop
      if tabuleiro(ii) > 0 then   --Ou seja, se tem uma peca do computador.
          temp1:=tabuleiro(ii);--So para lembrar que peca era.

          for jj in 1..64 loop
            if tabuleiro(jj) <= 0 then
             if validade(ii,jj)=true then

             Morre(Ii,Jj):=False;

             tabuleiro(ii) := 0;      --A pe�a sai, ele comeca a jogar em seu pensamento!
             temp2:=tabuleiro(jj);
             tabuleiro(jj):=temp1; --pronto, jogou!
             --O computador fez uma jogada qualquer possivel.
             S_Lance(iI,Jj);  --Executa o procedimento So_Lance, que e parecido.

             if Morre(iI,Jj)=false then  --Basta 1 para nao ser chequemate!
                Exequemate_T(I,J):=false;
             end if;

             tabuleiro(jj):=temp2;
             tabuleiro(ii):=temp1;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!

             end if;
            end if;
          end loop;
       end if;
  end loop;

 if Exequemate_T(I,J)=True then Exequemate(I,J):=True;  end if;
 end Mate;



procedure Mate_ele2(I,J:Integer) is
 --E' um porcedimento e nao uma funcao pois ele recebe
 --como dado de entrada somente a posicao do tabuleiro.
 --Esse procedimento serve para acabar com ele enquanto o
 --outro serve para saber se ele ta em mate ou n�o.
   Temp1, Temp2: Integer;
   Morre: array(1..64,1..64) of Boolean;
   Exequemate_T: array(1..64,1..64) of Boolean;
 procedure S_Lance(Ii,Jj:Integer)  is --Procedimento dentro do Mate.
  begin
 --  Deliberately NO time-abort here (one used to be): S_Lance feeds the
 --  mate / check-exposure flags (Exequemate, Expoem_A_Xeque, MataEle2)
 --  the decision cascade depends on for EVERY root move. Aborting
 --  mid-scan left those flags computed for early root moves and missing
 --  for later ones, and the cascade -- which has no notion of "flag not
 --  computed" -- would then prefer exactly the unvetted moves (seen as
 --  f7-f6-style junk under a tight clock). The full ply-1..3 pass costs
 --  only tens of milliseconds, so it always runs to completion; the
 --  clock is enforced by the expensive ply-4..16 chain instead, whose
 --  entry checks skip it cleanly per root move.
  for kk in 1..64 loop
       if tabuleiro(kk) > 0 then   --Ou seja, se tem uma pe�a da pessoa.
          for ll in 1..64 loop
             if tabuleiro(ll) = -999 then --O uso de and tornaria o programa mais lento!
               if validade(kk,ll)=true then
                  Morre(II,JJ):=True;
             --O computador come o rei do cara.!!!
               end if;
             end if;
          end loop;
       end if;
  end loop;
  end S_Lance;

 begin --Incio do Mate ele 2.

 Exequemate_T(I,J):=true;

 for ii in 1..64 loop
      if tabuleiro(ii) < 0 then   --Ou seja, se tem uma peca do computador.
          temp1:=tabuleiro(ii);--So para lembrar que peca era.

          for jj in 1..64 loop
            if tabuleiro(jj) >= 0 then  --O uso de and tornaria o programa mais lento!
             if validade(ii,jj)=true then

             Morre(Ii,Jj):=False;

             tabuleiro(ii) := 0;      --A pe�a sai, ele comeca a jogar em seu pensamento!
             temp2:=tabuleiro(jj);
             tabuleiro(jj):=temp1; --pronto, jogou!
             --O computador fez uma jogada qualquer possivel.
             S_Lance(iI,Jj);  --Executa o procedimento So_Lance, que e parecido.

             if Morre(iI,Jj)=false then  --Basta 1 para nao ser chequemate!
                Exequemate_T(I,J):=false;
             end if;

             tabuleiro(jj):=temp2;
             tabuleiro(ii):=temp1;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!

             end if;
            end if;
          end loop;
       end if;
  end loop;

 if Exequemate_T(I,J)=True then mataele2(I,J):=True;  end if;
 end Mate_ele2;


 --  (Ply-4 Analize4 and its Jogada_Perde2* flags removed in 0.7.9.3:
 --   written here and reset per-root but never consumed by any cascade
 --   tier. The live ply-4 verdict is Jogada_Perde_Profunda, set in
 --   Quarto_Lance via the Quinto_Lance recovery test.)

 --  Ply 16 (Decimo_Sexto_Lance): the deliberately pessimistic leaf of
 --  the deep tactical check. For the opponent's final reply, only the quick
 --  material test is applied: if ANY opponent move drops the running sum
 --  back below Soma2l, the ply-15 recovery under test is treated as refuted.
 procedure Decimo_Sexto_Lance(Soma2l,Soma15l:integer; Refuted: in out Boolean) is
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 DX_Loop:
 for d in 1..64 loop
      if tabuleiro(d) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario31:=tabuleiro(d);--So para lembrar que peca era.
         for e in 1..64 loop
           if tabuleiro(e) >= 0 then
            if validade(d,e)=true then
            tabuleiro(d) := 0;
            Temporario32:=tabuleiro(e);
            tabuleiro(e):=Temporario31;
            Soma16l:=Soma15l - Temporario32;

            if Soma16l < Soma2l then
               Refuted := True;
            end if;

            tabuleiro(e):=Temporario32;
            tabuleiro(d):=Temporario31;

            end if;
           end if;
           exit DX_Loop when Refuted;
         end loop;
      end if;
 end loop DX_Loop;
 end Decimo_Sexto_Lance;

 --  Ply 15 (Decimo_Quinto_Lance): the computer's answer to the
 --  opponent's ply-14 counter. It must recover to at least Soma2l and
 --  survive the pessimistic ply-16 leaf.
 procedure Decimo_Quinto_Lance(Soma2l,Soma14l:integer; Answered: in out Boolean) is
 Refuted : Boolean;
 begin
 DQn_Loop:
 for n in 1..64 loop
      if tabuleiro(n) > 0 then   --Ou seja, se tem uma peca do computador.
         Temporario29:=tabuleiro(n);--So para lembrar que peca era.
         for o in 1..64 loop
           if tabuleiro(o) <= 0 then
            if validade(n,o)=true then
            tabuleiro(n) := 0;
            Temporario30:=tabuleiro(o);
            tabuleiro(o):=Temporario29;
            Soma15l:=Soma14l - Temporario30;

            if Soma15l >= Soma2l then
               Refuted := False;
               Decimo_Sexto_Lance(Soma2l,Soma15l,Refuted);
               if not Refuted then
                  Answered := True;
               end if;
            end if;

            tabuleiro(o):=Temporario30;
            tabuleiro(n):=Temporario29;

            end if;
           end if;
           exit DQn_Loop when Answered;
         end loop;
      end if;
 end loop DQn_Loop;
 end Decimo_Quinto_Lance;

 --  Ply 14 (Decimo_Quarto_Lance): now mirrors Decimo_Segundo/Decimo one
 --  exchange deeper. An opponent ply-14 reply below Soma2l refutes the
 --  ply-13 answer only if the computer has no ply-15 continuation surviving
 --  to ply 16.
 procedure Decimo_Quarto_Lance(Soma2l,Soma13l:integer; Refuted: in out Boolean) is
 Answered : Boolean;
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 DQ_Loop:
 for d in 1..64 loop
      if tabuleiro(d) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario27:=tabuleiro(d);--So para lembrar que peca era.
         for e in 1..64 loop
           if tabuleiro(e) >= 0 then
            if validade(d,e)=true then
            tabuleiro(d) := 0;
            Temporario28:=tabuleiro(e);
            tabuleiro(e):=Temporario27;
            Soma14l:=Soma13l - Temporario28;

            if Soma14l < Soma2l then
               Answered := False;
               Decimo_Quinto_Lance(Soma2l,Soma14l,Answered);
               if not Answered then
                  Refuted := True;
               end if;
            end if;

            tabuleiro(e):=Temporario28;
            tabuleiro(d):=Temporario27;

            end if;
           end if;
           exit DQ_Loop when Refuted;
         end loop;
      end if;
 end loop DQ_Loop;
 end Decimo_Quarto_Lance;

 --  Ply 13 (Decimo_Terceiro_Lance): the computer's answer to the
 --  opponent's ply-12 counter. It must recover to at least Soma2l and
 --  survive through the ply-16 leaf.
 procedure Decimo_Terceiro_Lance(Soma2l,Soma12l:integer; Answered: in out Boolean) is
 Refuted : Boolean;
 begin
 DT_Loop:
 for n in 1..64 loop
      if tabuleiro(n) > 0 then   --Ou seja, se tem uma peca do computador.
         Temporario25:=tabuleiro(n);--So para lembrar que peca era.
         for o in 1..64 loop
           if tabuleiro(o) <= 0 then
            if validade(n,o)=true then
            tabuleiro(n) := 0;
            Temporario26:=tabuleiro(o);
            tabuleiro(o):=Temporario25;
            Soma13l:=Soma12l - Temporario26;

            if Soma13l >= Soma2l then
               Refuted := False;
               Decimo_Quarto_Lance(Soma2l,Soma13l,Refuted);
               if not Refuted then
                  Answered := True;
               end if;
            end if;

            tabuleiro(o):=Temporario26;
            tabuleiro(n):=Temporario25;

            end if;
           end if;
           exit DT_Loop when Answered;
         end loop;
      end if;
 end loop DT_Loop;
 end Decimo_Terceiro_Lance;

 --  Ply 12 (Decimo_Segundo_Lance): the opponent's counter to the ply-11
 --  answer. A reply below Soma2l refutes only if there is no surviving
 --  ply-13 answer through the ply-16 leaf.
 procedure Decimo_Segundo_Lance(Soma2l,Soma11l:integer; Refuted: in out Boolean) is
 Answered : Boolean;
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 DS_Loop:
 for t in 1..64 loop
      if tabuleiro(t) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario23:=tabuleiro(t);--So para lembrar que peca era.
         for u in 1..64 loop
           if tabuleiro(u) >= 0 then
            if validade(t,u)=true then
            tabuleiro(t) := 0;
            Temporario24:=tabuleiro(u);
            tabuleiro(u):=Temporario23;
            Soma12l:=Soma11l - Temporario24;

            if Soma12l < Soma2l then
               Answered := False;
               Decimo_Terceiro_Lance(Soma2l,Soma12l,Answered);
               if not Answered then
                  Refuted := True;
               end if;
            end if;

            tabuleiro(u):=Temporario24;
            tabuleiro(t):=Temporario23;

            end if;
           end if;
           exit DS_Loop when Refuted;
         end loop;
      end if;
 end loop DS_Loop;
 end Decimo_Segundo_Lance;

 --  Ply 11 (Decimo_Primeiro_Lance): the computer's answer to the
 --  opponent's ply-10 counter. It must recover to at least Soma2l and
 --  survive plies 12-14.
 procedure Decimo_Primeiro_Lance(Soma2l,Soma10l:integer; Answered: in out Boolean) is
 Refuted : Boolean;
 begin
 DP_Loop:
 for n in 1..64 loop
      if tabuleiro(n) > 0 then   --Ou seja, se tem uma peca do computador.
         Temporario21:=tabuleiro(n);--So para lembrar que peca era.
         for o in 1..64 loop
           if tabuleiro(o) <= 0 then
            if validade(n,o)=true then
            tabuleiro(n) := 0;
            Temporario22:=tabuleiro(o);
            tabuleiro(o):=Temporario21;
            Soma11l:=Soma10l - Temporario22;

            if Soma11l >= Soma2l then
               Refuted := False;
               Decimo_Segundo_Lance(Soma2l,Soma11l,Refuted);
               if not Refuted then
                  Answered := True;
               end if;
            end if;

            tabuleiro(o):=Temporario22;
            tabuleiro(n):=Temporario21;

            end if;
           end if;
           exit DP_Loop when Answered;
         end loop;
      end if;
 end loop DP_Loop;
 end Decimo_Primeiro_Lance;

 --  Ply 10 (Decimo_Lance): now mirrors Oitavo/Sexto one exchange deeper.
 --  An opponent ply-10 reply below Soma2l refutes the ply-9 answer only if
 --  the computer has no ply-11 continuation surviving to ply 16.
 procedure Decimo_Lance(Soma2l,Soma9l:integer; Refuted: in out Boolean) is
 Answered : Boolean;
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 D_Loop:
 for d in 1..64 loop
      if tabuleiro(d) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario19:=tabuleiro(d);--So para lembrar que peca era.
         for e in 1..64 loop
           if tabuleiro(e) >= 0 then
            if validade(d,e)=true then
            tabuleiro(d) := 0;
            Temporario20:=tabuleiro(e);
            tabuleiro(e):=Temporario19;
            Soma10l:=Soma9l - Temporario20;

            if Soma10l < Soma2l then
               Answered := False;
               Decimo_Primeiro_Lance(Soma2l,Soma10l,Answered);
               if not Answered then
                  Refuted := True;
               end if;
            end if;

            tabuleiro(e):=Temporario20;
            tabuleiro(d):=Temporario19;

            end if;
           end if;
           exit D_Loop when Refuted;
         end loop;
      end if;
 end loop D_Loop;
 end Decimo_Lance;

 --  Ply 9 (Nono_Lance): mirrors Setimo_Lance's shape one exchange
 --  deeper -- does the computer have an answer to the opponent's ply-8
 --  counter-capture that brings the sum back to at least Soma2l AND
 --  survives the opponent's deeper ply-10..16 replies (Decimo_Lance)?
 procedure Nono_Lance(Soma2l,Soma8l:integer; Answered: in out Boolean) is
 Refuted : Boolean;
 begin
 N_Loop:
 for n in 1..64 loop
      if tabuleiro(n) > 0 then   --Ou seja, se tem uma peca do computador.
         Temporario17:=tabuleiro(n);--So para lembrar que peca era.
         for o in 1..64 loop
           if tabuleiro(o) <= 0 then
            if validade(n,o)=true then
            tabuleiro(n) := 0;
            Temporario18:=tabuleiro(o);
            tabuleiro(o):=Temporario17;
            Soma9l:=Soma8l - Temporario18;

            if Soma9l >= Soma2l then
               Refuted := False;
               Decimo_Lance(Soma2l,Soma9l,Refuted);
               if not Refuted then
                  Answered := True;
               end if;
            end if;

            tabuleiro(o):=Temporario18;
            tabuleiro(n):=Temporario17;

            end if;
           end if;
           --  One surviving answer is enough; stop looking.
           exit N_Loop when Answered;
         end loop;
      end if;
 end loop N_Loop;
 end Nono_Lance;

 --  Ply 8 (Oitavo_Lance): mirrors Sexto_Lance's shape one exchange
 --  deeper. An opponent ply-8 reply that drops the sum below Soma2l only
 --  refutes the ply-7 answer under test if the computer has NO ply-9
 --  continuation (Nono_Lance) that recovers and survives through the
 --  ply-16 leaf. Replies that keep the sum at or above Soma2l need no
 --  answer and are skipped, which is what keeps the deep chain cheap in
 --  practice.
 --
 --  On time-abort the deeper verification is skipped with Refuted left
 --  as the caller pre-set it (False): under time pressure the check
 --  gracefully degrades to the shallower verdict instead of spuriously
 --  refuting answers it never finished analyzing.
 procedure Oitavo_Lance(Soma2l,Soma7l:integer; Refuted: in out Boolean) is
 Answered : Boolean;
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 T_Loop:
 for t in 1..64 loop
      if tabuleiro(t) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario15:=tabuleiro(t);--So para lembrar que peca era.
         for u in 1..64 loop
           if tabuleiro(u) >= 0 then
            if validade(t,u)=true then
            tabuleiro(t) := 0;
            Temporario16:=tabuleiro(u);
            tabuleiro(u):=Temporario15;
            Soma8l:=Soma7l - Temporario16;

            if Soma8l < Soma2l then
               Answered := False;
               Nono_Lance(Soma2l,Soma8l,Answered);
               if not Answered then
                  Refuted := True;
               end if;
            end if;

            tabuleiro(u):=Temporario16;
            tabuleiro(t):=Temporario15;

            end if;
           end if;
           --  One unanswerable refuting reply is enough; stop looking.
           exit T_Loop when Refuted;
         end loop;
      end if;
 end loop T_Loop;
 end Oitavo_Lance;

 --  Ply 7 (Setimo_Lance): mirrors Quinto_Lance's shape one exchange
 --  deeper -- does the computer have an answer to the opponent's ply-6
 --  counter-capture that brings the sum back to at least Soma2l AND
 --  survives opponent counter-play through the ply-16 leaf?
 procedure Setimo_Lance(Soma2l,Soma6l:integer; Answered: in out Boolean) is
 Refuted : Boolean;
 begin
 V_Loop:
 for v in 1..64 loop
      if tabuleiro(v) > 0 then   --Ou seja, se tem uma peca do computador.
         Temporario13:=tabuleiro(v);--So para lembrar que peca era.
         for w in 1..64 loop
           if tabuleiro(w) <= 0 then
            if validade(v,w)=true then
            tabuleiro(v) := 0;
            Temporario14:=tabuleiro(w);
            tabuleiro(w):=Temporario13;
            Soma7l:=Soma6l - Temporario14;

            if Soma7l >= Soma2l then
               Refuted := False;
               Oitavo_Lance(Soma2l,Soma7l,Refuted);
               if not Refuted then
                  Answered := True;
               end if;
            end if;

            tabuleiro(w):=Temporario14;
            tabuleiro(v):=Temporario13;

            end if;
           end if;
           --  One surviving answer is enough; stop looking.
           exit V_Loop when Answered;
         end loop;
      end if;
 end loop V_Loop;
 end Setimo_Lance;

 --  Ply 6 (Sexto_Lance): mirrors Quarto_Lance's shape one exchange
 --  deeper -- given a candidate ply-5 recovery move (already applied to
 --  the board by Quinto_Lance below), does any opponent counter-reply
 --  drop the sum back below Soma2l with NO surviving ply-7 answer
 --  (Setimo_Lance)? If so the candidate recovery does not actually
 --  hold, and Holds is cleared. Opponent replies that keep the sum at
 --  or above Soma2l need no answer and are skipped -- only genuine
 --  counter-captures below the break-even line are examined, which is
 --  what keeps this deep chain cheap in practice.
 --
 --  On time-abort the deep verification is skipped with Holds left as
 --  the caller pre-set it (True): under time pressure the check
 --  gracefully degrades to the shallower ply-5 verdict instead of
 --  spuriously flagging root moves it never finished analyzing.
 procedure Sexto_Lance(Soma2l,Soma5l:integer; Holds: in out Boolean) is
 Answered : Boolean;
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 X_Loop:
 for x in 1..64 loop
      if tabuleiro(x) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario11:=tabuleiro(x);--So para lembrar que peca era.
         for y in 1..64 loop
           if tabuleiro(y) >= 0 then
            if validade(x,y)=true then
            tabuleiro(x) := 0;
            Temporario12:=tabuleiro(y);
            tabuleiro(y):=Temporario11;
            Soma6l:=Soma5l - Temporario12;

            if Soma6l < Soma2l then
               Answered := False;
               Setimo_Lance(Soma2l,Soma6l,Answered);
               if not Answered then
                  Holds := False;
               end if;
            end if;

            tabuleiro(y):=Temporario12;
            tabuleiro(x):=Temporario11;

            end if;
           end if;
           --  One unanswerable counter-reply is enough; stop looking.
           exit X_Loop when not Holds;
         end loop;
      end if;
 end loop X_Loop;
 end Sexto_Lance;

 --  Ply 5: the computer's own follow-up reply to the opponent's ply-4
 --  recapture (Quarto_Lance). Mirrors Terceiro_Lance's shape (the
 --  computer's own move) with the same O(1) running-sum update as
 --  every other ply in this file. Recovered is set True the moment
 --  ANY ply-5 continuation brings the material level back to at least
 --  Soma2l (the level just before the ply-3 move started this little
 --  exchange) -- i.e. "the computer has a good enough answer to this
 --  specific opponent reply" -- AND that answer survives the continuation
 --  through `Decimo_Sexto_Lance` / ply 16.
 --  The search stops early via the named-loop exit the instant one
 --  surviving recovery is found, since one is enough.
 procedure Quinto_Lance(Soma2l,Soma4l:integer; Recovered: in out Boolean) is
 Holds : Boolean;
 begin
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 R_Loop:
 for r in 1..64 loop
      if tabuleiro(r) > 0 then   --Ou seja, se tem uma peca do computador.
         Temporario9:=tabuleiro(r);--So para lembrar que peca era.
         for s in 1..64 loop
           if tabuleiro(s) <= 0 then
            if validade(r,s)=true then
            tabuleiro(r) := 0;
            Temporario10:=tabuleiro(s);
            tabuleiro(s):=Temporario9;
            --  Soma5l = Soma4l - Temporario10, same O(1) reasoning as
            --  every other running-sum update in this file.
            Soma5l:=Soma4l - Temporario10;

            if Soma5l >= Soma2l then
               --  Quick test passed; verify the recovery survives the
               --  opponent's counter-play three plies further out
               --  (plies 6/7/8). The candidate move is still applied
               --  to the board here, which is exactly what Sexto_Lance
               --  needs to scan the opponent's replies to it.
               Holds := True;
               Sexto_Lance(Soma2l,Soma5l,Holds);
               if Holds then
                  Recovered := True;
               end if;
            end if;

            tabuleiro(s):=Temporario10;
            tabuleiro(r):=Temporario9;

            end if;
           end if;
           --  One recovering continuation is enough; stop looking.
           exit R_Loop when Recovered;
         end loop;
      end if;
 end loop R_Loop;
 end Quinto_Lance;

 --  Ply 4 search: for every person's piece (the opponent, replying to
 --  the computer's ply-3 move just applied by Terceiro_Lance below),
 --  try every legal destination and see whether it recaptures
 --  material. Same shape as Segundo_Lance one level up, with the same
 --  O(1) running-sum update as every other ply in this file.
 procedure Quarto_Lance(i,J,Soma2l,Soma3l:integer) is
 Recovered : Boolean;
 begin
 --  Once Jogada_Perde_Profunda(I,J) is set for this root move by an
 --  earlier Terceiro_Lance (m,n) trial, it will never be un-set (it is
 --  reset only once per root move, like every other Jogada_* flag), so
 --  later trials calling Quarto_Lance for the same (I,J) have nothing
 --  left to discover for the one flag the cascade actually reads --
 --  skip the whole ply-4/5 exploration for them.
 if Jogada_Perde_Profunda(I,J) then return; end if;
 Time_Management.Check_Time;
 if Time_Management.Search_Aborted then return; end if;
 P_Loop:
 for p in 1..64 loop
      if tabuleiro(p) < 0 then   --Ou seja, se tem uma peca da pessoa.
         Temporario7:=tabuleiro(p);--So para lembrar que peca era.
         for q in 1..64 loop
           if tabuleiro(q) >= 0 then
            if validade(p,q)=true then
            tabuleiro(p) := 0;
            Temporario8:=tabuleiro(q);
            tabuleiro(q):=Temporario7;
            --  Soma4l = Soma3l - Temporario8, same reasoning as every
            --  other running-sum update in this file: only p and q
            --  change, by exactly -Temporario8.
            Soma4l:=Soma3l - Temporario8;

            if Soma4l < Soma2l then
               Recovered := False;
               Quinto_Lance(Soma2l,Soma4l,Recovered);
               if Time_Management.Search_Aborted then
                  --  Quinto_Lance did not finish: its Recovered=False
                  --  proves nothing. Without this guard, the clock
                  --  expiring mid-verification stamped a SPURIOUS
                  --  Jogada_Perde_Profunda on whichever root move was
                  --  being vetted at that instant, while every
                  --  later-scanned move skipped vetting entirely and
                  --  looked clean -- so under time pressure the cascade
                  --  systematically preferred the unvetted moves over
                  --  the one the abort happened to land on (observed as
                  --  f7-f6 beating d7-d6 at short movetime). Undo the
                  --  trial move and stop: completed deep verdicts stay,
                  --  the unfinished one proves nothing either way.
                  tabuleiro(q):=Temporario8;
                  tabuleiro(p):=Temporario7;
                  exit P_Loop;
               end if;
               if not Recovered then
                  --  This specific opponent ply-4 reply captures material
                  --  and the computer has no ply-5 answer that gets back
                  --  to even Soma2l: a genuine, minimax-checked deep loss.
                  Jogada_Perde_Profunda(I,J):=True;
               end if;
            end if;

            tabuleiro(q):=Temporario8;
            tabuleiro(p):=Temporario7;

            end if;
           end if;
           --  Once found, one unrecoverable reply is enough evidence
           --  for this root move; no need to keep searching for more.
           exit P_Loop when Jogada_Perde_Profunda(I,J);
         end loop;
      end if;
 end loop P_Loop;
 end Quarto_Lance;

 Procedure Terceiro_Lance(i,J,k,L,temporario4,Soma2l:integer) is
 begin
 for m in 1..64 loop
      if tabuleiro(m) > 0 then   --Ou seja, se tem uma pe�a do computador.

         temporario5:=tabuleiro(m);--So para lembrar que pe�a era.
         for n in 1..64 loop
           if tabuleiro(n) <= 0 then
            if validade(m,n)=true then
            tabuleiro(m) := 0;      --A pe�a sai, ele comeca a jogar em seu pensamento!
            temporario6:=tabuleiro(n);
            tabuleiro(n):=temporario5; --pronto, jogou!
            --  Soma3l = Soma2l - Temporario6, by the same reasoning as
            --  the Soma2l update in Segundo_Lance above: only squares m
            --  and n change, by exactly -Temporario6.
            Soma3l:=Soma2l - Temporario6;

            Analize3(i,J,K,L,M,N,Soma3l,Soma2l);
            Quarto_Lance(i,J,Soma2l,Soma3l);  --Ply 4/5: opponent's reply, then the computer's answer to it.

            if not Time_Management.Search_Aborted
              and then N = L
              and then Temporario4 = 1
              and then BackupPeao = false
            then
               Jogada_PerdeP(I,J):=false;
            end if;
            --Ou seja, se N (um lugar onde o computador pode jogar) for igual a L
            --(um lugar onde a pessoa teria jogado comendo um peao) ent�o o peao esta protegido.
            --O backupPeao=true e'para saber se estamos falando do mesmo peao.
            --O ultimo que foi visto.

            tabuleiro(n):=temporario6;
            tabuleiro(m):=temporario5;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!
            exit when Time_Management.Search_Aborted;

            end if;
           end if;
         end loop;
         exit when Time_Management.Search_Aborted;
      end if;
 end loop;
 end Terceiro_Lance;

 procedure Segundo_Lance(i,J,Soma1l:integer) is
 --  Our king's square on the post-root-move board. Invariant within
 --  this procedure's (k,l) opponent-reply loop: the person's trial
 --  reply moves only their own (negative) pieces, so OUR king (positive
 --  999) never shifts square -- it is either still at King_Sq or, if
 --  the reply captured it (l = King_Sq), absent entirely. That one-bit
 --  fact replaces the legacy 64-square rescan that used to run on every
 --  (k,l) trial with an O(1) test, with byte-identical results:
 --  Posicao_Do_Rei is still exactly 0 when the king is absent from the
 --  trial board and exactly King_Sq otherwise -- the invariant the
 --  Mate call below and its Constraint_Error guard depend on.
 King_Sq : Integer := 0;
 begin
 BackupPeao:=False; --Isso ta relacionado com o peao estar nao protegido.
 for A in 1..64 loop
    if Tabuleiro(A)=999 then King_Sq:=A; end if;
 end loop;
 Posicao_Do_Rei := King_Sq;
 for k in 1..64 loop
      if tabuleiro(k) < 0 then   --Ou seja, se tem uma pe�a da pessoa.
         temporario3:=tabuleiro(k);--So para lembrar que pe�a era.
         for l in 1..64 loop
           if tabuleiro(l) >= 0 then --O uso do And tornaria o programa mais lento!
            if validade(k,l)=true then
            tabuleiro(k) := 0;      --A pe�a sai, ele comeca a jogar em seu pensamento!
            temporario4:=tabuleiro(l);
            tabuleiro(l):=temporario3; --pronto, jogou!
            --  Soma2l = Soma1l - Temporario4: the trial move only
            --  touches squares k (temporario3 -> 0) and l (temporario4
            --  -> temporario3), so the board sum changes by exactly
            --  -Temporario4. Replaces a full 64-square rescan on every
            --  one of this loop's iterations with an O(1) update -- the
            --  single largest hot-loop cost in the legacy search.
            Soma2l:=Soma1l - Temporario4;

            Analize2(i,J,K,L,Soma2l,Soma1l);
            Terceiro_Lance(i,J,k,L,Temporario4,Soma2l);  --Executa o procedimento Terceiro Lance.

            if not Time_Management.Search_Aborted then

            --  O(1) king-presence update: the opponent's trial reply
            --  (k,l) cannot move OUR king, only possibly capture it at
            --  its fixed square King_Sq. So the king is absent from the
            --  trial board iff l = King_Sq (the reply landed on the
            --  king's square). This replaces the legacy 64-square rescan
            --  that used to run on every (k,l) trial; see King_Sq above.
            --  The Constraint_Error guard is preserved: Posicao_Do_Rei
            --  is still exactly 0 when the king is absent (no stale
            --  value or uninitialized garbage can reach Validade, since
            --  King_Sq itself is scanned fresh once per root move
            --  before this loop) and King_Sq otherwise.
            if l = King_Sq then
               Posicao_Do_Rei := 0;
            else
               Posicao_Do_Rei := King_Sq;
            end if;

            if Posicao_Do_Rei /= 0 and then Validade(L,Posicao_Do_Rei)=True then
               --Esse if acima e' so para nao ficar lento demais!
               --Devo aprimorar para nao ficar lento e jogar bem!!!
               Mate(I,J);

               Expoem_A_Xeque(I,J):=True;
            end if;

            end if;

            tabuleiro(l):=temporario4;
            tabuleiro(k):=temporario3;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!
            exit when Time_Management.Search_Aborted;

            end if;
           end if;
         end loop;
         exit when Time_Management.Search_Aborted;
      end if;
 end loop;
 end Segundo_Lance;

 Begin --Inicio do programa em si, o prechess2. Mas aqui esta como um procedimento chamado
 --pela interface do usuario que se comporta como programa principal.

 --Aqui inicia o jogo. Esse programa por hora sera chamado cada vez que se for jogar.
 --As pe�as da maquina sao positivas e as da pessoa negativas.
 --Peao=1, bispo=3, cavalo=4, torre=7, dama=20, rei=999.
 --De inicio so vou pensar em coisas que comem, sem me preocupar com coisas complicadas como o xeque.
 --Tamb�m n�o vou me preocupar com os movimentos.
 --Qualquer pe�a pode sair de qualquer lugar e ir para qualquer outro que nao tenha uma pe�a do mesmo
 --tipo. O Rei a principio pode ser comido (por enquanto).
 --Depois a funcao validade diz se a jogada � possivel.

 Root_Game_Phase := Compute_Game_Phase;

 for A in 1..64 loop
   for B in 1..64 loop       --De inicio nenhuma jogada � boa ou ruim.
      Jogada_pegaR(A,B):=False;Jogada_PerdeR(A,B):=false;Jogada_ameacaR(A,B):=False;
      Jogada_PerdeD(A,B):=False;Jogada_PegaD(A,B):=False;Jogada_ameacaD(A,B):=False;
      Jogada_pegaT(A,B):=False;Jogada_ameacaT(A,B):=False;Jogada_PerdeT(A,B):=False;
      Jogada_pegaB(A,B):=False;Jogada_ameacaB(A,B):=False;Jogada_PerdeB(A,B):=False;
      Jogada_pegaC(A,B):=False;Jogada_ameacaC(A,B):=False;Jogada_PerdeC(A,B):=False;
      Jogada_pegaP(A,B):=False;Jogada_ameacaP(A,B):=False;Jogada_PerdeP(A,B):=False;
      Expoem_A_Xeque(A,B):=False;Exequemate(A,B):=False;
      Jogada_Promove_Maquina(A,B):=False; Jogada_Promove_humano(A,B):=False;
      Alinha(A,B):=False;
      MataEle2(A,B):=False;
      Jogada_Perde_Profunda(A,B):=False;
   end loop;
 end loop;

 --  (The legacy Quadro 8x8 mirror and its per-search zeroing loop were
 --   removed in 0.7.9.3: Quadro was write-only -- zeroed here, never
 --   read anywhere -- a dead leftover of the removed per-node rebuild.)


 --as letras do inicio do alfabeto, a,b,c,d,e,f,g,h.
 --serao sem importancia. Ja apartir do i serao usadas para memorizar
 --as jogadas e serao de vital importancia.

 --Contar o numero de bispos do adversario (e localizar o rei dele).
 --(Numero_B_Meu, the matching "own bishops" count, was write-only --
 --  never read anywhere -- and is removed.)

 Numero_B_Inimigo:=0;
 Posicao_Do_Rei_Dele:=0;
 for A in 1..64 loop
     if Tabuleiro(A)=-999 then Posicao_Do_Rei_Dele:=A; end if;
     if Tabuleiro(A)=-3 then
        Numero_B_Inimigo:=1;
        for B in 1..64 loop
           if Tabuleiro(B)=-3 and B /= A then
              Numero_B_Inimigo:=2;
           end if;
        end loop;
     end if;
  end loop;

 --Aqui o programa vai pensar no seu primeiro lance.
 --Lembre-se que todas os movimentos sao possiveis a nao ser que a funcao validade diga o contrario.



 --  Root attack map for the threat-freshness rule; see
 --  Raiz_Ja_Ameacado in the spec. Two kinds of pre-existing threat
 --  count: direct attacks (Validade) and slider X-RAYS through exactly
 --  one blocker (a pin or skewer: "if the blocker moves, I take").
 --  The x-ray case is what stops pin-line shuffling -- a bishop
 --  sliding between two squares of the same pin diagonal (observed as
 --  Bg4-Bh5-Bg4 against a pinned knight in front of the queen)
 --  "re-creates" the identical conditional threat from each square,
 --  and without the x-ray in this map each hop was credited as new.
 declare
    function Ja_Ameaca_No_Inicio (S : Integer) return Boolean is
       Sr : constant Integer := (S - 1) / 8 + 1;
       Sf : constant Integer := (S - 1) mod 8 + 1;
       Pr, Pf, Dr, Df, Cr, Cf, Blockers : Integer;
       Pc : Integer;
    begin
       for P in 1..64 loop
          Pc := Tabuleiro(P);
          if Pc > 0 then
             if Validade(P,S) then
                return True;
             end if;
             if Pc = 3 or Pc = 7 or Pc = 20 then
                Pr := (P - 1) / 8 + 1;
                Pf := (P - 1) mod 8 + 1;
                Dr := Sr - Pr;
                Df := Sf - Pf;
                if ((Pc = 7 or Pc = 20) and then (Dr = 0 or Df = 0) and then P /= S)
                  or else ((Pc = 3 or Pc = 20) and then Dr /= 0 and then abs Dr = abs Df)
                then
                   --  Walk from P toward S counting occupied squares
                   --  strictly between; exactly one means x-ray.
                   Dr := (if Dr > 0 then 1 elsif Dr < 0 then -1 else 0);
                   Df := (if Df > 0 then 1 elsif Df < 0 then -1 else 0);
                   Blockers := 0;
                   Cr := Pr + Dr;
                   Cf := Pf + Df;
                   while (Cr /= Sr or Cf /= Sf) and Blockers <= 1 loop
                      if Tabuleiro((Cr - 1) * 8 + Cf) /= 0 then
                         Blockers := Blockers + 1;
                      end if;
                      Cr := Cr + Dr;
                      Cf := Cf + Df;
                   end loop;
                   if Blockers = 1 then
                      return True;
                   end if;
                end if;
             end if;
          end if;
       end loop;
       return False;
    end Ja_Ameaca_No_Inicio;
 begin
    for S in 1..64 loop
       if Tabuleiro(S) < 0 then
          Raiz_Ja_Ameacado(S) := Ja_Ameaca_No_Inicio(S);
       else
          Raiz_Ja_Ameacado(S) := False;
       end if;
    end loop;
 end;

 Soma0l:=0;
 for A in 1..64 loop
 Soma0l:=Soma0l + Tabuleiro(A);
 end loop;

 for i in 1..64 loop
      if tabuleiro(i) > 0 then   --Ou seja, se tem uma pe�a do computador.
         temporario1:=tabuleiro(i);--S� para lembrar que pe�a era.

         for j in 1..64 loop
            if tabuleiro(j) <= 0 then  --O uso do and tornaria o programa mais lento!
             if validade(i,j)=true then
             tabuleiro(i) := 0;      --A pe�a sai, ele comeca a jogar em seu pensamento!
             temporario2:=tabuleiro(j);
             tabuleiro(j):=temporario1; --pronto, jogou!
             --  Soma1l = Soma0l - Temporario2: only squares i and j
             --  change (same reasoning as the deeper plies below).
             Soma1l:=Soma0l - Temporario2;
             Analize1(i,J,Soma1l,Soma0l);

             if Temporario1=20 or Temporario1=999 then
               Alinha_Dama_Rei;
             end if;
             --Isso acima executa um procedimento que da uma resposta true or false.
             --So conta se for de modo que 1 bispo inimigo ficando no lugar da dama
             --pude-se pegar o Rei. A saida e' na variavel alinha(i,j).
             --O if e' como sempre para nao deixar muito lento.

             --  Posicao_Do_Rei_Dele is scanned from the intact board
             --  before these loops, so it is 0 only if the position has
             --  no opposing king at all (malformed FEN) -- guard rather
             --  than index Validade with it.
             if Posicao_Do_Rei_Dele /= 0 and then Validade(J,Posicao_Do_Rei_Dele)=True then Mate_Ele2(I,J); end if;
            --Isso acima serve para acabar com o jogo.

             Segundo_Lance(i,J,Soma1l);  --Executa o procedimento Segundo_Lance, que e parecido.

             tabuleiro(j):=temporario2;
             tabuleiro(i):=temporario1;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!
             exit when Time_Management.Search_Aborted;
             end if;
            end if;
         end loop;
         exit when Time_Management.Search_Aborted;
      end if;
 end loop;

 cc:=0; dd:=0;
 --Isso e' uma pequena sa�da.

 --  One-time precompute for the decision cascade below: from this point
 --  to the end of this procedure the board (Tabuleiro) is only ever read, never
 --  written, so every one of the ~30 rule-blocks below that used to call
 --  Validade(A,B) and re-check Tabuleiro(A)>0/Tabuleiro(B)<=0 for all 4096
 --  (A,B) pairs, independently, now reads these three O(1) lookups instead.
 --  Same 4096 Validade calls as one full rule-block used to make, done
 --  once instead of once per rule-block -- no change to which (A,B) pairs
 --  qualify or to the ascending A-then-B scan order that the "last match
 --  wins" logic below depends on.
 for A in 1..64 loop
    Own_Piece(A) := Tabuleiro(A) > 0;
    Not_Own(A)   := Tabuleiro(A) <= 0;
 end loop;
 for A in 1..64 loop
    for B in 1..64 loop
       --  Jogada_Vetada folds the root-move exclusions from the
       --  forced-mate verification (see pprechess2.ads) into the one
       --  predicate every cascade tier consults, so a vetoed move is
       --  invisible to all rule blocks below without touching any of
       --  them individually.
       Valid_Cache(A,B) := Validade(A,B) and then not Jogada_Vetada(A,B);
       if Valid_Cache(A,B) and then Own_Piece(A) and then Not_Own(B) then
          Root_Move_Count := Root_Move_Count + 1;
          Root_Moves(Root_Move_Count) := (A => A, B => B);
       end if;
    end loop;
 end loop;

 --  If the clock cut the ply-4..16 chain short, its verdicts exist for
 --  early-scanned root moves and are missing for later ones -- and
 --  partial deep flags are WORSE than none: a genuinely bad move whose
 --  vetting never ran sails through the strict "safe" tiers below,
 --  beating properly-vetted good moves that those tiers correctly
 --  excluded from their own (deeper-tier) placement. Observed directly:
 --  at short movetime this engine preferred unvetted f7-f6 over d7-d6
 --  purely because d6's vetting had completed and f6's had not. So on
 --  abort the incomplete deep pass is discarded wholesale, and the
 --  cascade runs with uniform 3-ply semantics -- the same verdict for
 --  every root move, exactly the shallower-but-consistent degradation
 --  the time-management design promises.
 if Time_Management.Search_Aborted then
    for A in 1..64 loop
       for B in 1..64 loop
          Jogada_Perde_Profunda(A,B) := False;
       end loop;
    end loop;
 end if;
 --  The legacy hardcoded first/second-move opening replies that lived
 --  here (keyed on numero_de_meu_movimento) have been REMOVED, not just
 --  guarded: hardcoded opening positions are forbidden by this
 --  project's spec. Every move, including the first of a fresh game,
 --  now comes from the search and decision cascade below.


 --Agora segue uma sequencia que em muito vai definir o estilo de jogo.
 --Note que o n�o expor a Xeque n�o � muito importante uma vez que a maioria dos
 --xeques possiveis s�o sem fundo!


 if Contagem_Empate >= 3 and Soma0l>0 then --O valor 3 pode ser ajustado.
    Perigo_Empate:=True; else  --O ">" � para evitar que passe disso sem empatar empatando depois!
    Perigo_Empate:=False;
 end if;

 Zerar_Contagem_Empate:=False;
 Somar_Contagem_Empate:=False;


 if cc=0 or dd=0 then   --Aqui da xeque mate nele!
 for Root_Index in 1 .. Root_Move_Count loop
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if mataele2(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False
    then --A principio pode trocar dama com dama caso esteja em vantagem!
      Select_Move(A, B, No_Draw_Change);
    end if;
   end;
   end loop;
 end if;


 if cc=0 or dd=0 then   --Esse if e' so para saber se ja nao jogou!
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come a Dama sem expor a Xeque e sem permetir promo��o.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and (Jogada_PerdeD(A,B)=false or Soma0L>0)
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar dama com dama caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come a Dama.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and (Jogada_PerdeD(A,B)=false or Soma0L>0)
    and Exequemate(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar dama com dama caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui se promove.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_Promove_maquina(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and (Jogada_PerdeD(A,B)=false or Soma0L>0)
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Isso e' Xeque com ameaca a Dama.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False and
      Jogada_AmeacaD(A,B)  and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Isso e' Xeque com ameaca a Torre.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Jogada_AmeacaT(A,B)  and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Isso e' Xeque com ameaca ao Bispo.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Jogada_AmeacaB(A,B)  and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Isso e' Xeque com ameaca a Cavalo.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Jogada_AmeacaC(A,B)  and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Isso e' Xeque!
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Torre sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    (Jogada_PerdeT(A,B)=False or Soma0L>0) and Exequemate(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and  Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar torre com torre caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Torre podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    (Jogada_PerdeT(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar torre com torre caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Bispo sem expor a xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeT(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Exequemate(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Bispo podendo expor a xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_Perde_Profunda(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Exequemate(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Cavalo sem expor a xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeB(A,B)=False and
    Jogada_PerdeT(A,B)=False and
    (Jogada_PerdeC(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar cavalo com cavalo caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Cavalo podendo expor a xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeB(A,B)=False and
    Jogada_PerdeT(A,B)=False and
    (Jogada_PerdeC(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar cavalo com cavalo caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Bispo perdendo cavalo em circustancias especificas.  --Sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Lance_Do_Jogo > 6 and Numero_B_inimigo=2
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Bispo perdendo cavalo em circustancias especificas.  --Podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Lance_Do_Jogo > 6 and Numero_B_inimigo=2
     and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;


 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama e torre sem expor a xeque.  --podendo perder peao.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaT(A,B)=True and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama e torre podendo expor a xeque.  --podendo perder peao.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaT(A,B)=True and Exequemate(A,B)=False and Jogada_PerdeP(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama e cavalo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_PerdeP(A,B)=False
    and Jogada_AmeacaC(A,B)=true and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama e cavalo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaC(A,B)=true and Exequemate(A,B)=False and Jogada_PerdeP(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama e bispo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaB(A,B)=True and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_PerdeP(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama e  bispo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaB(A,B)=True and Exequemate(A,B)=False and Jogada_PerdeP(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_PerdeP(A,B)=False
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Dama podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Torre e Bispo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaB(A,B)=True and Expoem_A_Xeque(A,B)=false
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Torre e Bispo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaB(A,B)=True
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Torre e cavalo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Torre e cavalo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Bispo e cavalo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True and Exequemate(A,B)=False
    and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Bispo e cavalo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;


 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Peao sem expor a xeque!
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaP(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar peao com peao caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui come Peao podendo expor a xeque!
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_PegaP(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar peao com peao caso esteja em vantagem!
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Torre sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Torre podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Bispo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False  and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Bispo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False  and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;


 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Cavalo com peao sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaC(A,B)=True and Valid_Cache(A,B)=True and Tabuleiro(a)=1 and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;


 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Cavalo sem expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui ameaca Cavalo podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
    if Jogada_AmeacaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=False
    then
      Select_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 --  The seven quiet fallback blocks below
 --  (pawn-only or any-piece, with/without the Alinha check,
 --  with/without the Expoem_A_Xeque guard) each independently reset
 --  Best_Positional_Score before their own scan: only one of them actually
 --  runs its full scan in a given search (each is guarded by "cc=0 or dd=0",
 --  so once one finds any match the later ones are skipped) but resetting is
 --  harmless and keeps each block self-contained. See Positional_Score above
 --  for what changed and why: the scan/match conditions themselves are
 --  untouched.
 if (cc=0 or dd=0) then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga peao que nao perca nada e nao exponha a Xeque.  --e sem alinhar dama e rei.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Tabuleiro(A)=1 and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Alinha(A,B)=False and Jogada_Promove_Humano(A,B)=False then
      Select_Positional_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca nada e nao exponha a Xeque.  --e sem alinhar dama e rei.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Alinha(A,B)=False and Jogada_Promove_Humano(A,B)=False then
      Select_Positional_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca nada e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      Select_Positional_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga peao que nao perca nada e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=False and Tabuleiro(A)=1
     then
      Select_Positional_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 --  Same tie-break as the "nao exponha a Xeque" tier above, applied to
 --  its "podendo expor a Xeque" (may expose to check) counterpart -- in
 --  practice this is the tier that most quiet opening/middlegame moves
 --  actually resolve through (Expoem_A_Xeque is rarely False this early),
 --  so this is where the edge-pawn-push bias actually needs fixing.
 if (cc=0 or dd=0) and Perigo_Empate=False  then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca nada podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Jogada_Perde_Profunda(A,B)=False and
     Jogada_Promove_Humano(A,B)=False
     then
      Select_Positional_Move(A, B, Add_Draw);
    end if;
   end;
   end loop;
 end if;


 if cc=0 or dd=0  then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga peao n�o perdendo nada podendo expor a Xeque.  --mas que nao alinhe Rei e Dama.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Alinha(A,B)=false
     and Jogada_Promove_Humano(A,B)=False and Tabuleiro(A)=1
     then
      Select_Positional_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0  then
 Best_Positional_Score := Integer'First;
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga peao n�o perdendo nada podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Alinha(A,B)=false
     and Jogada_Promove_Humano(A,B)=False and Tabuleiro(A)=1
     then
      Select_Positional_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que perca peao e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and  Jogada_PerdeC(A,B)=false
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
     then
      Select_Move(A, B, Reset_Draw); --A ideia � que se vou perder uma pe�a � pouco proavel que empate.
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que perca peao podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and  Jogada_PerdeC(A,B)=false
     and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que perca cavalo ou peao e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que perca cavalo ou peao podendo expor  a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=False
     and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que perca bispo, cavalo ou peao e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false  and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que perca bispo, cavalo ou peao podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false  and Exequemate(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca dama e rei e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca dama e rei podendo expor a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca dama e rei e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca dama e rei podendo expor a Xeque  --e pondedo promover o cara.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca rei e nao exponha a Xeque.  --podendo promover o cara
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false and Exequemate(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca rei e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false  and Exequemate(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca Rei e n�o exponha a mate.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Exequemate(A,B)=False and jogada_perdeR(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca o Rei e nao exponha a Xeque.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;

 if cc=0 or dd=0 then
 for Root_Index in 1 .. Root_Move_Count loop    --Aqui joga qualquer coisa que nao perca o Rei.
   declare
      A : constant Integer := Root_Moves(Root_Index).A;
      B : constant Integer := Root_Moves(Root_Index).B;
   begin
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false  then
      Select_Move(A, B, Reset_Draw);
    end if;
   end;
   end loop;
 end if;


if cc=0 or dd=0 then
 Cc:=1; Dd:=1;
end if;


 --  Contagem_Empate is game-history state, not analysis state. The UCI layer
 --  resets it on new positions/games; do not mutate it inside repeated `go`
 --  searches of the same board, or identical analysis requests can choose
 --  different moves after the counter crosses the Perigo_Empate threshold.

end prechess2;  --Fim do programa propriamente dito.

end pprechess2;  --Fim do pacote pprechess2.
