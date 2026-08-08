with TT_Types;

package body Pvalidade is

 function validade(a,b: in integer) return boolean is

  --A variavel resultado (do tipo boolean) ja esta declarada no programa.
  resultado:boolean := False;
  ai,aj,bi,Bj:Integer;
  retaL1, retaL2:integer;

  procedure peaoanda is
  begin
    if tabuleiro(a)=1 then  --peao do computador.
       if aj=bj and bi - ai =1 then resultado:=true; else resultado:=false; end if;
       --Aqui tento programar os dois pulinhos iniciais para o computador.
       if Aj=Bj and Bi=4 and Ai=2 and Tabuleiro(16 + Aj)=0 then
          Resultado:=True;
       end if;
    else   --peao da pessoa.
       if aj=bj and ai - bi =1 then resultado:=true; else resultado:=false; end if;
       --Aqui tento programar os dois pulinhos iniciais para a pessoa.
       if Aj=Bj and Bi=5 and Ai=7 and Tabuleiro(40 + Aj)=0 then
          Resultado:=True;
       end if;
    end if;
  end peaoanda;
--Mas por hora nao vou ensinar a comer o peao desse jeito.
--Quando um deles der dois pulos.

  procedure peaocome is
  begin
    if tabuleiro(a)=1 then  --peao do computador.
       if bi - ai =1 and (bj -aj =1 or bj -aj = -1) then resultado:=true; else resultado:=false; end if;
    else    --peao da pessoa.
       if ai - bi =1 and (bj -aj =1 or bj -aj = -1) then resultado:=true; else resultado:=false; end if;
    end if;
  end peaocome;

  procedure peao  is
  begin
   if tabuleiro(b) = 0 then
    peaoanda ; else
    peaocome ; end if;
  end peao;

  procedure bispo  is --Nao uso explicitamente o valor 3 pois o procedimento dama tambem chamara isso.
    soma, diferenca: integer:=0;  --Atribui zero para o compilador nao reclamar.
  begin            --Eu vou ter que ver se existe pecas no meio!
                   --E mais ou menos parecido com o procedimento torre, talvez seja mais claro la.
                   --Aqui ele vai procurar por pecas intermediarias.

   retaL1:=0;retaL2:=0;
   soma:=ai + aj;      --Tanto faz usar a ou b.
   diferenca:=ai - aj; --Se mudasse para aj - ai deveria mudar tambem ai em baixo.

    -- Diagonal onde rank + file e' constante. Varre apenas entre a origem e o destino.
    if aj < bj then
       for e in aj + 1 .. bj - 1 loop
          if soma - e >=1 and soma - e <= 8 then
             if tabuleiro((soma - e - 1)*8 + e) /= 0 then
                retaL1:=1;
             end if;
          end if;
       end loop;
    elsif bj < aj then
       for e in bj + 1 .. aj - 1 loop
          if soma - e >=1 and soma - e <= 8 then
             if tabuleiro((soma - e - 1)*8 + e) /= 0 then
                retaL1:=1;
             end if;
          end if;
       end loop;
    end if;

    -- Diagonal onde rank - file e' constante. Varre apenas entre a origem e o destino.
    if aj < bj then
       for e in aj + 1 .. bj - 1 loop
          if diferenca + e >=1 and diferenca + e <= 8 then
             if tabuleiro((diferenca + e - 1)*8 + e) /=0 then
                retaL2:=1;
             end if;
          end if;
       end loop;
    elsif bj < aj then
       for e in bj + 1 .. aj - 1 loop
          if diferenca + e >=1 and diferenca + e <= 8 then
             if tabuleiro((diferenca + e - 1)*8 + e) /=0 then
                retaL2:=1;
             end if;
          end if;
       end loop;
    end if;


   if (aj + ai = bj + bi and retaL1 = 0) or  (aj - ai = bj - bi and retaL2 = 0) then
    resultado:=true;
   else
    resultado:=false;
   end if;

  end bispo;

  procedure cavalo  is  --Aqui nao importa de quem e' o cavalo.
  begin                 --Aqui, como no caso do peao que come, eu teria problemas de parede
                        --na versao 1..64. Por isso aqui uso sistema de 1..8,1..8.

     if ((bj - aj)**2 = 4 and (bi - ai)**2 = 1) or ((bj - aj)**2 = 1 and (bi - ai)**2 = 4) then
     --Acima o **2 e' ao quadrado, usei isso para sumir com o sinal mantendo a simetria,
     --modulo faria o mesmo.
          resultado:=true;
     else resultado:=false;
     end if;
  end cavalo;

  procedure torre  is  --Nao usar explicitamente o valor 7 pois o procedimento dama tambem chamara isso.
  retaI,retaJ:integer;
  begin             --Eu vou ter que ver se existe pecas no meio!
       --Essa parte vai ver se existe intermediarios.
       --Direcao I (rank). Varre apenas entre a origem e o destino.
       retaI:=0; retaJ:=0;
       if aj < bj then
          for c in aj + 1 .. bj - 1 loop
             if tabuleiro((ai - 1)*8 + c) /= 0 then
                retaI:=1;
             end if;
          end loop;
       elsif bj < aj then
          for c in bj + 1 .. aj - 1 loop
             if tabuleiro((ai - 1)*8 + c) /= 0 then
                retaI:=1;
             end if;
          end loop;
       end if;
       --Direcao J (file). Varre apenas entre a origem e o destino.
       if ai < bi then
          for c in ai + 1 .. bi - 1 loop
             if tabuleiro((c - 1)*8 + aj) /= 0 then
                retaJ:=1;
             end if;
          end loop;
       elsif bi < ai then
          for c in bi + 1 .. ai - 1 loop
             if tabuleiro((c - 1)*8 + aj) /= 0 then
                retaJ:=1;
             end if;
          end loop;
       end if;
       --Essa parte de baixo autoriza o jogo se tiverem alinhados e nao houver intermediarios
       if bj = aj  and retaJ=0 then
       resultado:=true; else
            if bi = ai and retaI=0 then
            resultado:=true; else
            resultado:=false;
            end if;
       end if;
  end torre;

  procedure dama  is  --Esse provavelmente e' o procedimento mais facil
  begin
    torre ;
    if resultado=false then
    bispo ;
    end if;
  end dama;

  procedure rei  is   --Nao vou me preocupar com a regra de que o Rei nao pode ser exposto a xeque.
  begin               --ou a que tem de sair do xeque aqui.
     if ((bj - aj = 0) or (bj -aj)**2 =1) and ((bi - ai = 0) or (bi -ai)**2 =1) then
     resultado:=true; else
     resultado:=false;     --Tambem aqui nao me preocupo com Roque.
     end if;
  end rei;

  procedure disposicao   is
  --O procedimento disposicao serve para mudar do formato 1..64
  --para o formato 1..8,1..8. Ele muda de tabuleiro(a) ou tabuleiro(b) para Quadro(ai,aj) ou
  --Quadro(bi,bj), mas tomo cuidado para nao alterar as variaveis a e b!
  --Claro, tambem muda as variaveis a e b para ai,aj,bi,bj.
  begin
  --Eu tenho a e b no formato 1..64 e quero ai,aj,bi,bj no formato 1..8,1..8.
  ai:= (a + 7 - ((a + 7) mod 8))/8;       --O mod da o resto!
  bi:= (b +7 - ((b + 7) mod 8))/8;        --Esse coisa tem de ser repetida para cada lance!
  aj:= a - 8 * (ai - 1);
  bj:= b - 8 * (bi - 1);

  --  The original also rebuilt the whole 8x8 Quadro mirror of Tabuleiro
  --  here, on EVERY Validade call -- a 64-square copy per node, paid
  --  tens of millions of times per deep search. Since Quadro was always
  --  rebuilt from Tabuleiro at call entry, every quadro(r,c) read in
  --  the piece handlers was exactly tabuleiro((r-1)*8 + c) at that
  --  moment; the handlers now index Tabuleiro directly and the rebuild
  --  is gone. Behavior is identical by construction (verified
  --  byte-for-byte on the bestmove battery with identical node counts);
  --  only the redundant copy is removed. The Quadro variable itself was
  --  write-only (zeroed once per search, never read), so it too was
  --  removed in 0.7.9.3 along with its zeroing loop.
  end disposicao;

  begin  --Funcao Validade

  -- Reject out-of-range squares before any board indexing.
  if A < 1 or A > 64 or B < 1 or B > 64 then
     return False;
  end if;

  -- Short-circuit null move, empty source, and same-colour capture
  -- before paying for piece-specific geometry.
  if A = B then
     return False;
  end if;
  if Tabuleiro(A) = 0 then
     return False;
  end if;
  if Tabuleiro(A) * Tabuleiro(B) > 0 then
     return False;
  end if;

  TT_Types.Nodes_Searched := TT_Types.Nodes_Searched + 1;

  --O que e' a funcao validade?
  --De inicio eu pensava apenas em pegar uma peca de uma das 64 casas e por numa das outras.
  --O programa faz isso literalemente, mas dai consulta a funcao validade para ver se a jogada e'
  --permitida ou nao. A funcao validade vai responder com um true ou false.

  disposicao;
  case abs Tabuleiro (A) is
     when 1   => peao;
     when 3   => bispo;
     when 4   => cavalo;
     when 7   => torre;
     when 20  => dama;
     when 999 => rei;
     when others => resultado := False;
  end case;

  return resultado;

 end validade;  --Fim da funcao Validade.

end Pvalidade;
