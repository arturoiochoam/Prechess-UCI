with TT_Types;

package body Pvalidade is

 function validade(a,b: in integer) return boolean is

  --A variavel resultado (do tipo boolean) ja esta declarada no programa.
  resultado:boolean;
  ai,aj,bi,Bj:Integer;
  retaL1, retaL2:integer;

  procedure peaoanda is
     Passantl,Passantp:Integer;
  begin
     if Aj+1<9 then Passantp:=Aj+1; else Passantp:=8; end if; --P quer dizer plus, o relacionado ao 8.
     if Aj-1>0 then Passantl:=Aj-1; else Passantl:=1; end if; --L e' de less. Isso e' so para evitar
     -- erro no caso do valor n�o estar no intervalo 1..8.
    if tabuleiro(a)=1 then  --peao do computador.
       if aj=bj and bi - ai =1 then resultado:=true; else resultado:=false; end if;
       --Aqui tento programar os dois pulinhos iniciais para o computador.
       if Aj=Bj and Bi=4 and Ai=2 and Tabuleiro(16 + Aj)=0 and  Tabuleiro(24 + Passantp)/=-1 and
       Tabuleiro(24 + Passantl)/=-1--O peao inimigo estaria na 4 ameacando a 3.
        --Eu fiz isso para evitar ser comido En passant. Assim posso dizer que o programa suporta em
        --certo sentido o en passant, por que nunca permite que ocorra!
       then Resultado:=True; end if;
    else   --peao da pessoa.
       if aj=bj and ai - bi =1 then resultado:=true; else resultado:=false; end if;
       --Aqui tento programar os dois pulinhos iniciais para a pessoa.
       if Aj=Bj and Bi=5 and Ai=7 and Tabuleiro(40 + Aj)=0 then Resultado:=True; end if;
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

  procedure bispo  is --N�o uso explicitamente o valor 3 pois o procedimento dama tamb�m chamara isso.
    soma, diferenca: integer:=0;  --Atribui zero para o compilador nao reclamar.
  begin            --Eu vou ter que ver se existe pe�as no meio!
                   --� mais ou menos parecido com o procedimento torre, talvez seja mais claro la.
                   --Aqui ele vai procurar por pe�as intermediarias.

   retaL1:=0;retaL2:=0;
   soma:=ai + aj;      --Tanto faz usar a ou b.
   diferenca:=ai - aj; --Se mudasse para aj - ai deveria mudar tamb�m ai em baixo.

    for e in 1..8 loop
       if soma - e >=1 and soma - e <= 8 then   --&
         if tabuleiro((soma - e - 1)*8 + e) /= 0 and ((aj < e and e < bj) or (aj > e and e > bj))
         --soma - e poderia tar assumindo valores nao permitidos. Dai o if &
         then        --Poderia usar ai e bi, da na mesma.
         retaL1:=1;
         end if;
       end if;
    end loop;

    for e in 1..8 loop
       if diferenca + e >=1 and diferenca + e <= 8 then
         if tabuleiro((diferenca + e - 1)*8 + e) /=0 and ((aj < e and e < bj) or (aj > e and e > bj)) then
         --Tive duvida quando ao dife + e.
         retaL2:=1;
         end if;
       end if;
    end loop;


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

  procedure torre  is  --N�o usar explicitamente o valor 7 pois o procedimento dama tambem chamara isso.
  retaI,retaJ:integer;
  begin             --Eu vou ter que ver se existe pe�as no meio!
       --Essa parte vai ver se existe intermediarios.
       --Dire��o I.
       retaI:=0; retaJ:=0;
       for c in 1..8 loop
         if tabuleiro((ai - 1)*8 + c) /= 0 and ((aj < c and c < bj) or (bj < c  and c < aj)) then
          retaI:=1;
         end if;
       end loop;       --Ta havendo um problema, a torre nao ta comendo.
       --Direcao J.
       for c in 1..8 loop
         if tabuleiro((c - 1)*8 + aj) /= 0 and ((ai < c and c < bi) or (bi < c and c < ai)) then
          retaJ:=1;
         end if;
       end loop;
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
    bispo ;
    if resultado=false then
    torre ;
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
  --  only the redundant copy is removed. The Quadro variable itself
  --  stays in the spec for the legacy GUI's own use.
  end disposicao;

  begin  --Funcao Validade

  TT_Types.Nodes_Searched := TT_Types.Nodes_Searched + 1;

  --O que � a fun�ao validade?
  --De inicio eu pensava apenas em pegar uma pe�a de uma das 64 casas e por numa das outras.
  --O programa faz isso literalemente, mas dai consulta a funcao validade para ver se a jogada e'
  --permitida ou nao. A funcao validade vai responder com um true ou false.

  --Abaixo havia originalmente um case, mas ele nao funcionou por razoes um tanto desconhecidas.

  if tabuleiro(a)=1    then disposicao; peao;   end if;
  if tabuleiro(a)=-1   then disposicao; peao;   end if;
  if tabuleiro(a)=3    then disposicao; bispo;  end if;
  if tabuleiro(a)=-3   then disposicao; bispo;  end if;
  if tabuleiro(a)=4    then disposicao; cavalo; end if;
  if tabuleiro(a)=-4   then disposicao; cavalo; end if;
  if tabuleiro(a)=7    then disposicao; torre;  end if;
  if tabuleiro(a)=-7   then disposicao; torre;  end if;
  if tabuleiro(a)=20   then disposicao; dama;   end if;
  if tabuleiro(a)=-20  then disposicao; dama;   end if;
  if tabuleiro(a)=999  then disposicao; rei;    end if;
  if tabuleiro(a)=-999 then disposicao; rei;    end if;


  if Tabuleiro(A)*Tabuleiro(B) > 0 then resultado:=False; end if; --So para ter certeza que nao joga
                                                                  --em casa com pe�a da mesma cor.
  if Tabuleiro(A)=0 or A=B then Resultado:=False; end if;

  return resultado;

 end validade;  --Fim da funcao Validade.

end Pvalidade;
