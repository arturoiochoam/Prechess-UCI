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
--  Plies 6-16 (Sexto_Lance through Decimo_Sexto_Lance): the same
--  per-ply scratch pattern as every shallower ply in this file. These
--  plies verify that a ply-5 "recovery" move survives five more complete
--  opponent/computer exchanges and one final opponent reply at ply 16.
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
Temporario21, Temporario22: integer;
Soma11L: Integer;
Temporario23, Temporario24: integer;
Soma12L: Integer;
Temporario25, Temporario26: integer;
Soma13L: Integer;
Temporario27, Temporario28: integer;
Soma14L: Integer;
Temporario29, Temporario30: integer;
Soma15L: Integer;
Temporario31, Temporario32: integer;
Soma16L: Integer;

--  (Ply-4 Analize4 and its Jogada_Perde2* flags removed in 0.7.9.3:
--   written but never consumed by any cascade tier. Jogada_Perde_Profunda
--   below is the live ply-4 verdict.)
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
Perigo_Empate:Boolean;
Zerar_Contagem_Empate:Boolean;
Somar_Contagem_Empate:Boolean;

BackupPeao:Boolean;

MataEle2:array(1..64,1..64) of Boolean; --Quando der true a jogada acaba com ele.
Posicao_Do_Rei_Dele:Integer:=0; --Same 0="not found" convention as Posicao_Do_Rei.

Lance_Do_Jogo: Integer:=0; --Serve para dar ideia do momento do jogo em que estamos.
--Por exemplo, no inicio cavalo vai valer mais que bispo.
--No fim, se houver pelo menos dois bispos, um bispo vai valer mais que um cavalo.

Numero_B_Inimigo: Integer; --Bispo count for the opponent (legacy bishop-value heuristic).

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

 function Positional_Game_Phase return Integer
   with Post => Positional_Game_Phase'Result in 0 .. 256;

 function Positional_Interpolate (MG, EG, Phase : Integer) return Integer
   with Pre => Phase in 0 .. 256;

 function Positional_Test_Score (Piece, Sq, Phase : Integer) return Integer
   with Pre => Sq in 1 .. 64 and then Phase in 0 .. 256;

 procedure Prechess2;

end pprechess2;
