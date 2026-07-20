with Pvalidade;
with Search_Integration; use Pvalidade;
with Time_Management;

package body pprechess2 is
--Esse pacote contem o procedimento prechess2 que � o programa de xadrez propriamente dito.
--Mas aqui ele � chamado pelo prechess.adb que � interface do usuario e se comporta como programa principal.


Procedure prechess2 is

 i,J: Integer:=1;  --Usados como memoria da 1a jogada; ver Segundo_Lance/Analize1/Analize2.

 --  Caches for the final decision cascade only (see note above the
 --  precompute loop, near "Aqui da xeque mate nele!"). Never read or
 --  written anywhere during the ply-1/2/3 trial-move search itself.
 Valid_Cache : array(1..64,1..64) of Boolean;
 Own_Piece   : array(1..64) of Boolean;
 Not_Own     : array(1..64) of Boolean;

 --  Tie-break for the two "nothing tactical distinguishes these moves"
 --  fallback rule-blocks below ("Aqui joga qualquer coisa que nao perca
 --  nada e nao exponha a Xeque" and its pawn-only equivalent). Those
 --  blocks scan every (A,B) pair in ascending order and, with no `exit`,
 --  simply keep overwriting cc/dd with the LAST matching pair -- i.e.
 --  among moves the legacy evaluation already considers equally safe
 --  (identical material/check-exposure outcome), the original code picks
 --  whichever one happens to come last in the scan, with no regard for
 --  whether it is a sound developing move or a random flank pawn push.
 --  Quiet_Move_Score breaks that tie with a small piece-square-table:
 --  a full tactical/safety match is required FIRST, exactly as before,
 --  and this score only decides which of several *already-qualifying*
 --  quiet moves is kept. It never changes what counts as a safe move and
 --  never touches any cascade tier; it is purely the arbiter the quiet
 --  fallback tiers already consulted, made piece-aware.
 --
 --  Everything is computed in the engine's own frame, where the moving
 --  side's pieces are always positive and sit on the low ranks (the board
 --  is mirrored for Black before the search -- see Move_Validation.
 --  Mirror_Square), so rank 1-2 are always the mover's own back ranks and
 --  higher ranks are advancement, for either colour. The table rewards
 --  central files and central ranks, rewards developing a minor piece off
 --  the first rank, and penalises a knight or bishop going to the rim --
 --  exactly the "sound development beats a random flank move" preference
 --  the file-only centrality version began, now able to see the piece and
 --  the rank as well as the file. Destination From/To are the real
 --  cascade-scan squares; To is where the piece would land.
 function Quiet_Move_Score (From, To : Integer) return Integer is
    File_T     : constant Integer := ((To - 1) mod 8) + 1;
    Rank_T     : constant Integer := ((To - 1) / 8) + 1;
    Piece      : constant Integer := abs Tabuleiro (From);
    Fc         : constant Integer := 8 - abs (2 * File_T - 9); -- file centre 1..7
    --  Central ranks score highest; the mover's own back rank (1) and the
    --  far edge (8) score lowest, discouraging both aimless back-rank
    --  shuffles and premature over-extension.
    Rank_Bonus : constant array (1 .. 8) of Integer := (0, 1, 3, 4, 3, 2, 1, 0);
    Score      : Integer := Fc * 2 + Rank_Bonus (Rank_T);
 begin
    if Piece = 3 or Piece = 4 then          -- bishop / knight: develop, avoid the rim
       if File_T = 1 or File_T = 8 then Score := Score - 3; end if;
       if Rank_T = 1 then Score := Score - 2; end if;
    end if;
    return Score;
 end Quiet_Move_Score;

 Best_Quiet_Score : Integer;

  procedure Alinha_Dama_Rei is
  Posicao_Dama, Posicao_Rei: Integer:=0;
  begin
     for A in 1..64 loop
      if Tabuleiro(A)=20 then Posicao_Dama:=A;end if;
      if Tabuleiro(A)=999 then Posicao_Rei:=A; end if;
     end loop;
     if Posicao_Dama /= 0 then Tabuleiro(Posicao_Dama):=-3;
      if Validade(Posicao_Dama,Posicao_Rei)=True then Alinha(I,J):=True; else Alinha(I,J):=False; end if;
      Tabuleiro(Posicao_Dama):=20;
     end if; --So para evitar zebra caso nao tenha a Dama!
     if Posicao_DAma /= 0 then Tabuleiro(Posicao_Dama):=-7;
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
  Result : Boolean;
 begin
  if Tabuleiro(B) > Piece_Threshold then
     Result := False;
  else
     Result := False;
     for C in 1 .. 64 loop
        if Validade(C,B)=True and Tabuleiro(C)>0 and Tabuleiro(C)/=999 then
           Result := True;
        end if;
     end loop;
  end if;
  return Result;
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
  if Lance_Do_Jogo>5 then
    Check_Promotion_Threat;
  end if;
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
 --  clock is enforced by the expensive ply-4..10 chain instead, whose
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
 --  clock is enforced by the expensive ply-4..10 chain instead, whose
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


 --  Ply 4: the opponent's reply to the computer's ply-3 move
 --  (Terceiro_Lance). Mirrors Analize2's Jogada_PerdeX check (delta of
 --  the mover's own trial move against the running material sum) one
 --  full move-pair deeper -- same threshold-per-piece-value pattern,
 --  same "only reset per root move, existential across every subtree"
 --  style already used by every other Jogada_* flag in this file.
 procedure Analize4(i,J,Soma4l,Soma3l:integer) is
 begin
  if Soma4l - Soma3l=-1   then Jogada_Perde2P(I,J):=True; end if;
  if Soma4l - Soma3l=-3   then Jogada_Perde2B(I,J):=True; end if;
  if Soma4l - Soma3l=-4   then Jogada_Perde2C(I,J):=True; end if;
  if Soma4l - Soma3l=-7   then Jogada_Perde2T(I,J):=True; end if;
  if Soma4l - Soma3l=-20  then Jogada_Perde2D(I,J):=True; end if;
  if Soma4l - Soma3l=-999 then Jogada_Perde2R(I,J):=True; end if;
 end Analize4;

 --  Ply 10 (Decimo_Lance): the leaf of the deep tactical check. For
 --  the opponent's final reply, only the quick material test is
 --  applied: if ANY opponent move drops the running sum back below
 --  Soma2l, the ply-9 recovery under test is treated as refuted. This
 --  leaf is deliberately pessimistic (a ply-11 recapture the computer
 --  might have is beyond the horizon), exactly the way the ply-4-only
 --  check once was -- but six plies deeper, where the error matters
 --  far less, and any fixed-depth check must cut off somewhere.
 procedure Decimo_Lance(Soma2l,Soma9l:integer; Refuted: in out Boolean) is
 begin
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
            --  Soma10l = Soma9l - Temporario20, same O(1) reasoning as
            --  every other running-sum update in this file.
            Soma10l:=Soma9l - Temporario20;

            if Soma10l < Soma2l then
               Refuted := True;
            end if;

            tabuleiro(e):=Temporario20;
            tabuleiro(d):=Temporario19;

            end if;
           end if;
           --  One refuting reply is enough evidence; stop looking.
           exit D_Loop when Refuted;
         end loop;
      end if;
 end loop D_Loop;
 end Decimo_Lance;

 --  Ply 9 (Nono_Lance): mirrors Setimo_Lance's shape one exchange
 --  deeper -- does the computer have an answer to the opponent's ply-8
 --  counter-capture that brings the sum back to at least Soma2l AND
 --  survives the opponent's final ply-10 reply (Decimo_Lance)?
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
            --  Soma9l = Soma8l - Temporario18, same O(1) reasoning as
            --  every other running-sum update in this file.
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
 --  deeper. Formerly the pessimistic leaf of the chain; since plies
 --  9/10 were added it verifies instead of assuming: an opponent ply-8
 --  reply that drops the sum below Soma2l only refutes the ply-7
 --  answer under test if the computer has NO ply-9 continuation
 --  (Nono_Lance) that recovers and survives ply 10. Replies that keep
 --  the sum at or above Soma2l need no answer and are skipped, which
 --  is what keeps the deep chain cheap in practice.
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
            --  Soma8l = Soma7l - Temporario16, same O(1) reasoning as
            --  every other running-sum update in this file.
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
 --  survives the opponent's ply-8 counter-play (Oitavo_Lance, itself
 --  verified down to the ply-10 leaf since plies 9/10 were added)?
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
            --  Soma7l = Soma6l - Temporario14, same O(1) reasoning as
            --  every other running-sum update in this file.
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
            --  Soma6l = Soma5l - Temporario12, same O(1) reasoning as
            --  every other running-sum update in this file.
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
 --  specific opponent reply" -- AND (since plies 6-8 were added) that
 --  answer survives the opponent's counter-reply, the computer's reply
 --  to that, and one final opponent reply (Sexto/Setimo/Oitavo_Lance).
 --  The search stops early via the named-loop exit the instant one
 --  surviving recovery is found, since one is enough.
 procedure Quinto_Lance(i,J,Soma2l,Soma4l:integer; Recovered: in out Boolean) is
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

            Analize4(i,J,Soma4l,Soma3l);

            Recovered := False;
            Quinto_Lance(i,J,Soma2l,Soma4l,Recovered);
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

            if N = L and Temporario4=1 and BackupPeao=false then Jogada_PerdeP(I,J):=false; end if;
            --Ou seja, se N (um lugar onde o computador pode jogar) for igual a L
            --(um lugar onde a pessoa teria jogado comendo um peao) ent�o o peao esta protegido.
            --O backupPeao=true e'para saber se estamos falando do mesmo peao.
            --O ultimo que foi visto.

            tabuleiro(n):=temporario6;
            tabuleiro(m):=temporario5;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!

            end if;
           end if;
         end loop;
      end if;
 end loop;
 end Terceiro_Lance;

 procedure Segundo_Lance(i,J,Soma1l:integer) is
 begin
 BackupPeao:=False; --Isso ta relacionado com o peao estar nao protegido.
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

            --  The opponent's trial reply (k,l) may just have captured
            --  the computer's king off the board (meaning the root move
            --  left it en prise -- Jogada_PerdeR accounts for that
            --  separately). In that case there is no king square to ask
            --  about, and the stale value left in Posicao_Do_Rei by an
            --  earlier trial -- or, on a process's very first search,
            --  its uninitialized garbage -- must never reach Validade:
            --  this exact call raised Constraint_Error when a checkmate
            --  position was the first thing a fresh engine process was
            --  asked to analyze (the original build script's blanket
            --  -gnatp suppressed the check and read garbage silently).
            --  Reset, rescan, and skip the check-exposure question
            --  entirely when the king is absent from the trial board.
            Posicao_Do_Rei := 0;
            for A in 1..64 loop
               if Tabuleiro(A)=999 then Posicao_Do_Rei:=A; end if;
            end loop;

            if Posicao_Do_Rei /= 0 and then Validade(L,Posicao_Do_Rei)=True then
               --Esse if acima e' so para nao ficar lento demais!
               --Devo aprimorar para nao ficar lento e jogar bem!!!
               Mate(I,J);

               Expoem_A_Xeque(I,J):=True;
            end if;

            tabuleiro(l):=temporario4;
            tabuleiro(k):=temporario3;--Tudo volta ao normal! Lembre-se, ele esta pensando e nao jogando!

            end if;
           end if;
         end loop;
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


 for A in 1..64 loop
   for B in 1..64 loop       --De inicio nenhuma jogada � boa ou ruim.
      Jogada_pegaR(A,B):=False;Jogada_PerdeR(A,B):=false;Jogada_ameacaR(A,B):=False;
      Jogada_PerdeD(A,B):=False;Jogada_PegaD(A,B):=False;Jogada_ameacaD(A,B):=False;
      Jogada_pegaT(A,B):=False;Jogada_ameacaT(A,B):=False;Jogada_PerdeT(A,B):=False;
      Jogada_pegaB(A,B):=False;Jogada_ameacaB(A,B):=False;Jogada_PerdeB(A,B):=False;
      Jogada_pegaC(A,B):=False;Jogada_ameacaC(A,B):=False;Jogada_PerdeC(A,B):=False;
      Jogada_pegaP(A,B):=False;Jogada_ameacaP(A,B):=False;Jogada_PerdeP(A,B):=False;
      Expoem_A_Xeque(A,B):=False; Comerei(A,B):=False;Exequemate(A,B):=False;
      Jogada_Promove_Maquina(A,B):=False; Jogada_Promove_humano(A,B):=False;
      Alinha(A,B):=False;
      MataEle2(A,B):=False;
      Jogada_Perde2P(A,B):=False; Jogada_Perde2B(A,B):=False; Jogada_Perde2C(A,B):=False;
      Jogada_Perde2T(A,B):=False; Jogada_Perde2D(A,B):=False; Jogada_Perde2R(A,B):=False;
      Jogada_Perde_Profunda(A,B):=False;
   end loop;
 end loop;

 for a in 1..8 loop
   for b in 1..8 loop
       quadro(a,b):=0;  --So para zerar quadro.
   end loop;
 end loop;


 --as letras do inicio do alfabeto, a,b,c,d,e,f,g,h.
 --serao sem importancia. Ja apartir do i serao usadas para memorizar
 --as jogadas e serao de vital importancia.

 --Aqui vou contar o numero de bispos.
 --Primeiro o numero de bispos meus.

  for A in 1..64 loop
     if Tabuleiro(A)=3 then
        Numero_B_Meu:=1;
        for B in 1..64 loop
           if Tabuleiro(B)=3 and B /= A then
              Numero_B_Meu:=2;
           end if;
        end loop;
     end if;
  end loop;

 --Agora o numero de bispos da pessoa.

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
             end if;
            end if;
         end loop;
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
    end loop;
 end loop;

 --  If the clock cut the ply-4..10 chain short, its verdicts exist for
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

 Somatoria_Tabuleiro:=0;
 for A in 1..64 loop
    Somatoria_Tabuleiro:=Somatoria_Tabuleiro + Tabuleiro(A);
 end loop; --No inicio a soma � zero.

 if Contagem_Empate >= 3 and Somatoria_Tabuleiro>0 then --O valor 3 pode ser ajustado.
    Perigo_Empate:=True; else  --O ">" � para evitar que passe disso sem empatar empatando depois!
    Perigo_Empate:=False;
 end if;

 Zerar_Contagem_Empate:=False;
 Somar_Contagem_Empate:=False;


 if cc=0 or dd=0 then   --Aqui da xeque mate nele!
 for a in 1..64 loop
   for b in 1..64 loop
    if mataele2(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False
    then --A principio pode trocar dama com dama caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);  --Veja entao que comer a Dama tem preferencia a dar cheque.
    end if;
   end loop;
 end loop;
 end if;


 if cc=0 or dd=0 then   --Esse if e' so para saber se ja nao jogou!
 for a in 1..64 loop    --Aqui come a Dama sem expor a Xeque e sem permetir promo��o.
   for b in 1..64 loop
    if Jogada_PegaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and (Jogada_PerdeD(A,B)=false or Soma0L>0)
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar dama com dama caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);  --Veja entao que comer a Dama tem preferencia a dar cheque.
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come a Dama.
   for b in 1..64 loop
    if Jogada_PegaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and (Jogada_PerdeD(A,B)=false or Soma0L>0)
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar dama com dama caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);  --Veja entao que comer a Dama tem preferencia a dar cheque.
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui se promove.
   for b in 1..64 loop
    if Jogada_Promove_maquina(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and (Jogada_PerdeD(A,B)=false or Soma0L>0)
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Isso e' Xeque com ameaca a Dama.
   for b in 1..64 loop
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False and
      Jogada_AmeacaD(A,B)  and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      Somar_Contagem_Empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Isso e' Xeque com ameaca a Torre.
   for b in 1..64 loop
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Jogada_AmeacaT(A,B)  and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      Somar_Contagem_Empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Isso e' Xeque com ameaca ao Bispo.
   for b in 1..64 loop
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Jogada_AmeacaB(A,B)  and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      Somar_Contagem_Empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Isso e' Xeque com ameaca a Cavalo.
   for b in 1..64 loop
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Jogada_AmeacaC(A,B)  and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      Somar_Contagem_Empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Isso e' Xeque!
   for b in 1..64 loop
    if Jogada_AmeacaR(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
      and Jogada_PerdeR(A,B)=false and Jogada_PerdeD(A,B)=false and Jogada_PerdeT(A,B)=false and
      Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and Jogada_PerdeP(A,B)=False
      and Exequemate(A,B)=False
    then  -- Ou seja, so vai dar Xeque se nao perder nada mesmo!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      Somar_Contagem_Empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Torre sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_PegaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    (Jogada_PerdeT(A,B)=False or Soma0L>0) and Exequemate(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and  Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar torre com torre caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Torre podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_PegaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    (Jogada_PerdeT(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar torre com torre caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Bispo sem expor a xeque.
   for b in 1..64 loop
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeT(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Bispo podendo expor a xeque.
   for b in 1..64 loop
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeT(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Exequemate(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Cavalo sem expor a xeque.
   for b in 1..64 loop
    if Jogada_PegaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeB(A,B)=False and
    Jogada_PerdeT(A,B)=False and
    (Jogada_PerdeC(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar cavalo com cavalo caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Cavalo podendo expor a xeque.
   for b in 1..64 loop
    if Jogada_PegaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and Jogada_PerdeB(A,B)=False and
    Jogada_PerdeT(A,B)=False and
    (Jogada_PerdeC(A,B)=False or Soma0L>0) and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar cavalo com cavalo caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Bispo perdendo cavalo em circustancias especificas.
   for b in 1..64 loop  --Sem expor a Xeque.
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Lance_Do_Jogo > 6 and Numero_B_inimigo=2
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Bispo perdendo cavalo em circustancias especificas.
   for b in 1..64 loop  --Podendo expor a Xeque.
    if Jogada_PegaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    (Jogada_PerdeB(A,B)=False or Soma0L>0) and Lance_Do_Jogo > 6 and Numero_B_inimigo=2
     and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar bispo com bispo caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;


 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Aqui ameaca Dama e torre sem expor a xeque.
   for b in 1..64 loop  --podendo perder peao.
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaT(A,B)=True and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Dama e torre podendo expor a xeque.
   for b in 1..64 loop  --podendo perder peao.
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaT(A,B)=True and Exequemate(A,B)=False and Jogada_PerdeP(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Aqui ameaca Dama e cavalo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_PerdeP(A,B)=False
    and Jogada_AmeacaC(A,B)=true and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Aqui ameaca Dama e cavalo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaC(A,B)=true and Exequemate(A,B)=False and Jogada_PerdeP(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Aqui ameaca Dama e bispo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaB(A,B)=True and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_PerdeP(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Aqui ameaca Dama e  bispo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_AmeacaB(A,B)=True and Exequemate(A,B)=False and Jogada_PerdeP(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 for a in 1..64 loop    --Aqui ameaca Dama sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_PerdeP(A,B)=False
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Dama podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaD(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False
    and Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Torre e Bispo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaB(A,B)=True and Expoem_A_Xeque(A,B)=false
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Torre e Bispo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaB(A,B)=True
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Torre e cavalo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Torre e cavalo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Bispo e cavalo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True and Exequemate(A,B)=False
    and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Bispo e cavalo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Jogada_AmeacaC(A,B)=True
    and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;


 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Peao sem expor a xeque!
   for b in 1..64 loop
    if Jogada_PegaP(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False
    and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar peao com peao caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui come Peao podendo expor a xeque!
   for b in 1..64 loop
    if Jogada_PegaP(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=False and Jogada_PerdeB(A,B)=False and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then --A principio pode trocar peao com peao caso esteja em vantagem!
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Torre sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Torre podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaT(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(a,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Bispo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False  and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Bispo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaB(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=False and
    Jogada_PerdeP(A,B)=False  and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;


 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui ameaca Cavalo com peao sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaC(A,B)=True and Valid_Cache(A,B)=True and Tabuleiro(a)=1 and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;


 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Cavalo sem expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
    and Jogada_Promove_Humano(A,B)=false
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False  then
 for a in 1..64 loop    --Aqui ameaca Cavalo podendo expor a Xeque.
   for b in 1..64 loop
    if Jogada_AmeacaC(A,B)=True and Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
    and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
    Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
    Jogada_PerdeP(A,B)=false and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=False
    then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 --  The four "no tactical criterion decides this" fallback blocks below
 --  (pawn/any-piece, with/without the Alinha check) each independently
 --  reset Best_Quiet_Score before their own scan: only one of the four
 --  actually runs its full scan in a given search (each is guarded by
 --  "cc=0 or dd=0", so once one of them finds any match at all, the
 --  later ones are skipped) but resetting is harmless and keeps each
 --  block self-contained. See Quiet_Move_Score above for what changed
 --  and why: the scan/match conditions themselves are untouched.
 if (cc=0 or dd=0) then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga peao que nao perca nada e nao exponha a Xeque.
   for b in 1..64 loop  --e sem alinhar dama e rei.
     if Valid_Cache(A,B)=True and Tabuleiro(A)=1 and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Alinha(A,B)=False and Jogada_Promove_Humano(A,B)=False then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca nada e nao exponha a Xeque.
   for b in 1..64 loop  --e sem alinhar dama e rei.
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Alinha(A,B)=False and Jogada_Promove_Humano(A,B)=False then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if (cc=0 or dd=0) and Perigo_Empate=False then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca nada e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga peao que nao perca nada e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=False and Tabuleiro(A)=1
     then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 --  Same tie-break as the "nao exponha a Xeque" tier above, applied to
 --  its "podendo expor a Xeque" (may expose to check) counterpart -- in
 --  practice this is the tier that most quiet opening/middlegame moves
 --  actually resolve through (Expoem_A_Xeque is rarely False this early),
 --  so this is where the edge-pawn-push bias actually needs fixing.
 if (cc=0 or dd=0) and Perigo_Empate=False  then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca nada podendo expor a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      somar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;


 if cc=0 or dd=0  then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga peao n�o perdendo nada podendo expor a Xeque.
   for b in 1..64 loop  --mas que nao alinhe Rei e Dama.
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Alinha(A,B)=false
     and Jogada_Promove_Humano(A,B)=False and Tabuleiro(A)=1
     then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0  then
 Best_Quiet_Score := Integer'First;
 for a in 1..64 loop    --Aqui joga peao n�o perdendo nada podendo expor a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and Jogada_PerdeC(A,B)=false and
     Jogada_PerdeP(A,B)=False and Exequemate(A,B)=False and Alinha(A,B)=false
     and Jogada_Promove_Humano(A,B)=False and Tabuleiro(A)=1
     then
      if Quiet_Move_Score(A, B) >= Best_Quiet_Score then
         cc:=A; dd:=B; Best_Quiet_Score := Quiet_Move_Score(A, B);
         --  Report only when the candidate is actually retained: before
         --  this was moved inside the tie-break, every scanned match
         --  printed an info line even when the tie-break rejected it,
         --  flooding the GUI with pv moves that were never the real
         --  candidate.
         Search_Integration.Report_UCI(A, B);
      end if;
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que perca peao e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and  Jogada_PerdeC(A,B)=false
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=false
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true; --A ideia � que se vou perder uma pe�a � pouco proavel que empate.
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que perca peao podendo expor a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=false and  Jogada_PerdeC(A,B)=false
     and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que perca cavalo ou peao e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que perca cavalo ou peao podendo expor  a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false and Jogada_PerdeB(A,B)=False
     and Exequemate(A,B)=False and Jogada_Promove_Humano(A,B)=false
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que perca bispo, cavalo ou peao e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false  and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que perca bispo, cavalo ou peao podendo expor a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False and
     Jogada_PerdeT(A,B)=false  and Exequemate(A,B)=False
     and Jogada_Promove_Humano(A,B)=false
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca dama e rei e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca dama e rei podendo expor a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca dama e rei e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False and Jogada_Promove_Humano(A,B)=False
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca dama e rei podendo expor a Xeque
   for b in 1..64 loop  --e pondedo promover o cara.
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=False and Jogada_PerdeD(A,B)=False
     and Exequemate(A,B)=False and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False
     then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca rei e nao exponha a Xeque.
   for b in 1..64 loop  --podendo promover o cara
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false and Exequemate(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca rei e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false  and Exequemate(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca Rei e n�o exponha a mate.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Exequemate(A,B)=False and jogada_perdeR(A,B)=False  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca o Rei e nao exponha a Xeque.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false  and Expoem_A_Xeque(A,B)=False and Jogada_Perde_Profunda(A,B)=False then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;

 if cc=0 or dd=0 then
 for a in 1..64 loop    --Aqui joga qualquer coisa que nao perca o Rei.
   for b in 1..64 loop
     if Valid_Cache(A,B)=True and Own_Piece(A) and Not_Own(B)
     and Jogada_PerdeR(a,B)=false  then
      cc:=A; dd:=B; Search_Integration.Report_UCI(A, B);
      zerar_contagem_empate:=true;
    end if;
   end loop;
 end loop;
 end if;


if cc=0 or dd=0 then
 Cc:=1; Dd:=1;
end if;


 if Zerar_Contagem_Empate then contagem_empate:=0; end if;
 if Somar_Contagem_Empate and not Zerar_Contagem_Empate then Contagem_Empate:=Contagem_Empate+1;
 end if;

end prechess2;  --Fim do programa propriamente dito.

end pprechess2;  --Fim do pacote pprechess2.
