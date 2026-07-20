package pprechess2 is


--  (The legacy two-move hardcoded opening book and its
--  numero_de_meu_movimento counter were removed: hardcoded opening
--  positions are forbidden by this project's spec.)

Exequemate,Jogada_PegaP,Jogada_AmeacaP,Jogada_PerdeP:array(1..64,1..64) of Boolean; -- Peao.
Jogada_PegaB,Jogada_AmeacaB,Jogada_PerdeB:array(1..64,1..64) of Boolean; --Bispo.
Jogada_PegaC,Jogada_AmeacaC,Jogada_PerdeC:array(1..64,1..64) of Boolean; --Cavalo.
Jogada_PegaT, Jogada_AmeacaT,Jogada_PerdeT:array(1..64,1..64) of Boolean; --Torre.
Jogada_PegaD,Jogada_AmeacaD,Jogada_PerdeD:array(1..64,1..64) of Boolean; --Dama.
Jogada_PegaR,Jogada_AmeacaR,Jogada_PerdeR:array(1..64,1..64) of Boolean; -- Rei.
Jogada_Promove_Maquina, Jogada_Promove_Humano:array(1..64,1..64) of Boolean;--Promo��o.
Expoem_A_Xeque,Alinha:array(1..64,1..64) of Boolean;
Comerei:array(1..64,1..64) of boolean;
--  Initialized (0 = "not found on the board") rather than left as
--  uninitialized garbage: the body re-scans before every use and its
--  guards rely on 0 meaning "no king present in this trial position".
Posicao_Do_Rei:Integer:=0;
temporario1, Temporario2, temporario3, temporario4: integer;
temporario5, Temporario6: integer;
Soma0L,Soma1L,Soma2L,Soma3L:Integer;
Temporario7, Temporario8: integer;
Soma4L: Integer;
Temporario9, Temporario10: integer;
Soma5L: Integer;
--  Plies 6-10 (Sexto_Lance / Setimo_Lance / Oitavo_Lance / Nono_Lance /
--  Decimo_Lance): the same per-ply scratch pattern as every shallower
--  ply in this file. See the body's comments above Sexto_Lance for the
--  design: these plies verify that a ply-5 "recovery" move survives the
--  opponent's counter-reply (ply 6), the computer's answer to that
--  (ply 7), the opponent's next counter (ply 8), the computer's answer
--  to that (ply 9), and one final opponent reply (ply 10, the
--  deliberately pessimistic leaf).
Temporario11, Temporario12: integer;
Soma6L: Integer;
Temporario13, Temporario14: integer;
Soma7L: Integer;
Temporario15, Temporario16: integer;
Soma8L: Integer;
Temporario17, Temporario18: integer;
Soma9L: Integer;
Temporario19, Temporario20: integer;
Soma10L: Integer;

--  Ply 4 (added on top of the legacy engine's original fixed 3-ply
--  structure -- see README_UCI.md "Version 0.7.9 changelog" / "ply 4"
--  for the full design rationale). Quarto_Lance simulates the
--  opponent's reply to the computer's ply-3 move (Terceiro_Lance);
--  Analize4 records whether that reply recaptures material (informational
--  per-piece bookkeeping only, mirroring Analize2's Jogada_PerdeX one
--  move-pair deeper) but, since ply 5 was added, no longer decides
--  Jogada_Perde_Profunda by itself -- see the ply-5 note below.
Jogada_Perde2P, Jogada_Perde2B, Jogada_Perde2C,
Jogada_Perde2T, Jogada_Perde2D, Jogada_Perde2R : array(1..64,1..64) of Boolean;
--  True only if some ply-4 opponent reply captures material AND the
--  computer has NO ply-5 continuation (Quinto_Lance) that recovers back
--  to at least the material level from just before the ply-3 move --
--  i.e. a properly minimax-shaped check (opponent's reply is fixed,
--  computer's follow-up is chosen optimally), not a blanket "any
--  recapture is bad" flag, which would incorrectly reject perfectly
--  good trades (e.g. win a knight, get a bishop recaptured back --
--  fine, since Cavalo=4 > Bispo=3). Used as a blanket "this plan isn't
--  safe even after both sides' best replies" screen, the same role
--  Jogada_PerdeR already plays one ply up throughout the cascade.
Jogada_Perde_Profunda : array(1..64,1..64) of Boolean;

Contagem_Empate:integer:=0;
Somatoria_tabuleiro:Integer;
Perigo_Empate:Boolean;
Zerar_Contagem_Empate:Boolean;
Somar_Contagem_Empate:Boolean;

BackupPeao:Boolean;

MataEle2:array(1..64,1..64) of Boolean; --Quando der true a jogada acaba com ele.
Posicao_Do_Rei_Dele:Integer:=0; --Same 0="not found" convention as Posicao_Do_Rei.

Lance_Do_Jogo: Integer; --Serve para dar ideia do momento do jogo em que estamos.
--Por exemplo, no inicio cavalo vai valer mais que bispo.
--No fim, se houver pelo menos dois bispos, um bispo vai valer mais que um cavalo.

Numero_B_Inimigo, Numero_B_Meu: Integer; --Para contar o n. de bispos para o proposito acima referido.

Ingles:Boolean:=False;

--  Squares holding a person's piece that the computer ALREADY attacks
--  on the root board, computed once per search before any trial move.
--  Analize3 consults it so the threat tiers credit only NEWLY CREATED
--  material threats: re-attacking a piece that was already attacked
--  (e.g. shuffling a bishop between two squares that both hit the same
--  knight) is not a reason to move -- observed as a tempo-wasting
--  Bg4-Bh5-Bg4 shuffle in a reported game. Check threats (Ganho=999)
--  are exempt, leaving the mate machinery's inputs untouched.
Raiz_Ja_Ameacado : array(1..64) of Boolean;

--  Root-move exclusions, in the search's own (internal, possibly
--  mirrored) coordinates. Set by Prechess_UCI when its forced-mate
--  verification finds that the cascade's chosen move walks into a
--  short mate (Search_Integration.Has_Forced_Mate_Within_Two): the
--  offending move is vetoed here and the search re-run so the cascade
--  makes its next-best choice. Folded into Valid_Cache at the top of
--  the decision cascade, so every rule tier respects it through the
--  one predicate they all already consult. Cleared by Prechess_UCI
--  around each root selection; always all-False during PV probes.
Jogada_Vetada : array(1..64,1..64) of Boolean := (others => (others => False));

cc,dd:integer:=1;

 procedure Prechess2;

end pprechess2;
