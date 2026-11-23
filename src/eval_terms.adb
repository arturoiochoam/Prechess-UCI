-------------------------------------------------------------------------------
--  Gate G9 / Phase 8 - core positional term bodies.  See eval_terms.ads.
-------------------------------------------------------------------------------

with Pvalidade;
with Move_Validation;
with Pprechess2;

package body Eval_Terms is

   use Pvalidade;
   use Move_Validation;

   ---------------------------------------------------------------------------
   --  Term 1 - passed pawns: rank-scaled bonus tables, indexed by the rank
   --  the pawn stands on (1 .. 8).  Ranks 1 and 8 cannot legally hold a pawn;
   --  the table entries there are 0.
   ---------------------------------------------------------------------------
   --  (Passed_MG and Passed_EG declared in Eval_Terms spec)

   function Enemy_Pawn_Ahead (Sq : Integer; White : Boolean) return Boolean;
   --  True when at least one enemy pawn stands on the file of Sq or either
   --  adjacent file AND in front of Sq, i.e. the pawn on Sq is not passed.

   function Enemy_Pawn_Ahead (Sq : Integer; White : Boolean) return Boolean is
      F     : constant Integer := File_Of (Sq);
      R     : constant Integer := Rank_Of (Sq);
      Lo_F  : constant Integer := Integer'Max (1, F - 1);
      Hi_F  : constant Integer := Integer'Min (8, F + 1);
      Lo_R  : constant Integer := (if White then R + 1 else 1);
      Hi_R  : constant Integer := (if White then 8 else R - 1);
      Enemy : constant Integer := (if White then -1 else 1);
   begin
      for RR in Lo_R .. Hi_R loop
         for FF in Lo_F .. Hi_F loop
            if Tabuleiro (Square_Of (RR, FF)) = Enemy then
               return True;
            end if;
         end loop;
      end loop;
      return False;
   end Enemy_Pawn_Ahead;

   function Passed_Pawns return Integer is
      Phase : constant Integer := Pprechess2.Positional_Game_Phase;
      Total : Integer := 0;
      R     : Integer;
   begin
      for Sq in 1 .. 64 loop
         case Tabuleiro (Sq) is
            when 1 =>          -- White pawn
               R := Rank_Of (Sq);
               if not Enemy_Pawn_Ahead (Sq, True) then
                  Total := Total +
                    Pprechess2.Positional_Interpolate (Passed_MG (R), Passed_EG (R), Phase);
               end if;

            when -1 =>         -- Black pawn: mirror the rank, negate the bonus
               R := 9 - Rank_Of (Sq);
               if not Enemy_Pawn_Ahead (Sq, False) then
                  Total := Total -
                    Pprechess2.Positional_Interpolate (Passed_MG (R), Passed_EG (R), Phase);
               end if;

            when others =>
               null;
         end case;
      end loop;
      return Total;
   end Passed_Pawns;

   ---------------------------------------------------------------------------
   --  Term 2 - doubled / isolated pawns.
   --
   --  Doubled: charged once per extra pawn on a file (three pawns on a file
   --  are two doubled pawns).  Isolated: charged once per pawn whose two
   --  adjacent files hold no friendly pawn (a-file and h-file use the one
   --  neighbour they have).
   ---------------------------------------------------------------------------
   --  (Doubled_MG, Doubled_EG, Isolated_MG, Isolated_EG declared in Eval_Terms spec)

   function Doubled_Isolated_Pawns return Integer is
      type File_Counts is array (1 .. 8) of Natural;

      Phase   : constant Integer := Pprechess2.Positional_Game_Phase;
      W_Count : File_Counts := [others => 0];
      B_Count : File_Counts := [others => 0];
      Total   : Integer := 0;
      F       : Integer;

      function Friendly_Neighbour (Counts : File_Counts;
                                   File   : Integer) return Boolean;
      --  True when a friendly pawn stands on an adjacent file.

      function Friendly_Neighbour (Counts : File_Counts;
                                   File   : Integer) return Boolean is
      begin
         return (File > 1 and then Counts (File - 1) > 0)
           or else (File < 8 and then Counts (File + 1) > 0);
      end Friendly_Neighbour;

   begin
      --  Pass 1 - how many pawns of each colour stand on each file.
      for Sq in 1 .. 64 loop
         case Tabuleiro (Sq) is
            when 1  => W_Count (File_Of (Sq)) := W_Count (File_Of (Sq)) + 1;
            when -1 => B_Count (File_Of (Sq)) := B_Count (File_Of (Sq)) + 1;
            when others => null;
         end case;
      end loop;

      --  Pass 2a - doubled pawns, charged per file (not per pawn).
      for FF in 1 .. 8 loop
         if W_Count (FF) > 1 then
            Total := Total +
              Pprechess2.Positional_Interpolate
                (Doubled_MG * (W_Count (FF) - 1), Doubled_EG * (W_Count (FF) - 1), Phase);
         end if;
         if B_Count (FF) > 1 then
            Total := Total -
              Pprechess2.Positional_Interpolate
                (Doubled_MG * (B_Count (FF) - 1), Doubled_EG * (B_Count (FF) - 1), Phase);
         end if;
      end loop;

      --  Pass 2b - isolated pawns, charged per pawn.
      for Sq in 1 .. 64 loop
         case Tabuleiro (Sq) is
            when 1 =>
               F := File_Of (Sq);
               if not Friendly_Neighbour (W_Count, F) then
                  Total := Total +
                    Pprechess2.Positional_Interpolate (Isolated_MG, Isolated_EG, Phase);
               end if;

            when -1 =>
               F := File_Of (Sq);
               if not Friendly_Neighbour (B_Count, F) then
                  Total := Total -
                    Pprechess2.Positional_Interpolate (Isolated_MG, Isolated_EG, Phase);
               end if;

            when others =>
               null;
         end case;
      end loop;

      return Total;
   end Doubled_Isolated_Pawns;

   ---------------------------------------------------------------------------
   --  Term 3 - rooks on open / semi-open files.  Charged per rook, so two
   --  rooks doubled on an open file each collect the bonus.
   ---------------------------------------------------------------------------
   --  (Open_MG, Open_EG, Semi_Open_MG, Semi_Open_EG declared in Eval_Terms spec)

   function Rook_Files return Integer is
      type File_Pawns is array (1 .. 8) of Boolean;

      Phase     : constant Integer := Pprechess2.Positional_Game_Phase;
      W_Pawn    : File_Pawns := [others => False];
      B_Pawn    : File_Pawns := [others => False];
      W_Rook_Sq : array (1 .. 16) of Integer;   -- at most 8 legal + promoted
      B_Rook_Sq : array (1 .. 16) of Integer;
      W_N       : Natural := 0;
      B_N       : Natural := 0;
      Total     : Integer := 0;
      F         : Integer;
   begin
      --  Pass 1 - pawn occupancy per file, and the rook squares.
      for Sq in 1 .. 64 loop
         case Tabuleiro (Sq) is
            when 1  => W_Pawn (File_Of (Sq)) := True;
            when -1 => B_Pawn (File_Of (Sq)) := True;
            when 7  =>
               W_N := W_N + 1;
               W_Rook_Sq (W_N) := Sq;
            when -7 =>
               B_N := B_N + 1;
               B_Rook_Sq (B_N) := Sq;
            when others => null;
         end case;
      end loop;

      --  Pass 2 - score each rook by the pawn cover of its own file.
      for I in 1 .. W_N loop
         F := File_Of (W_Rook_Sq (I));
         if not W_Pawn (F) then
            if not B_Pawn (F) then
               Total := Total +
                 Pprechess2.Positional_Interpolate (Open_MG, Open_EG, Phase);
            else
               Total := Total +
                 Pprechess2.Positional_Interpolate (Semi_Open_MG, Semi_Open_EG, Phase);
            end if;
         end if;
      end loop;

      for I in 1 .. B_N loop
         F := File_Of (B_Rook_Sq (I));
         if not B_Pawn (F) then
            if not W_Pawn (F) then
               Total := Total -
                 Pprechess2.Positional_Interpolate (Open_MG, Open_EG, Phase);
            else
               Total := Total -
                 Pprechess2.Positional_Interpolate (Semi_Open_MG, Semi_Open_EG, Phase);
            end if;
         end if;
      end loop;

      return Total;
   end Rook_Files;

   ---------------------------------------------------------------------------
   --  Term 5 - king safety, cheap version.  Six cheap file lookups for the
   --  shield and four Is_Square_Attacked probes for the pressure, per king:
   --  the search calls Evaluate at every leaf, so the cost has to stay small.
   ---------------------------------------------------------------------------
   --  (Shield_MG, Shield_EG, Pressure_MG, Pressure_EG declared in Eval_Terms spec)

   function King_Safety return Integer is
      Phase : constant Integer := Pprechess2.Positional_Game_Phase;

      function One_King (White : Boolean) return Integer is
         Ksq      : constant Integer := Find_King (White);
         Kr, Kf   : Integer;
         Shield   : Integer := 0;
         Pressure : Integer := 0;
         R, F, Pc : Integer;
      begin
         if Ksq = 0 then
            return 0;
         end if;

         Kr := Rank_Of (Ksq);
         Kf := File_Of (Ksq);

         --  Shield: friendly pawns on the king file and the two neighbouring
         --  files, one and two ranks in front of the king.
         for DF in -1 .. 1 loop
            for DR in 1 .. 2 loop
               F  := Kf + DF;
               R  := (if White then Kr + DR else Kr - DR);
               if F in 1 .. 8 and then R in 1 .. 8 then
                  Pc := Tabuleiro (Square_Of (R, F));
                  if (White and then Pc = 1) or else (not White and then Pc = -1) then
                     Shield := Shield + 1;
                  end if;
               end if;
            end loop;
         end loop;

         --  Pressure: the king square itself and the three squares directly
         --  in front of it, each counted once if the enemy attacks it.
         for DR in 0 .. 1 loop
            for DF in -1 .. 1 loop
               if DR = 0 and then DF /= 0 then
                  null;                       --  only the king square itself
               else
                  R := (if White then Kr + DR else Kr - DR);
                  F := Kf + DF;
                  if R in 1 .. 8 and then F in 1 .. 8
                    and then Is_Square_Attacked (Square_Of (R, F),
                                                 By_White => not White)
                  then
                     Pressure := Pressure + 1;
                  end if;
               end if;
            end loop;
         end loop;

         return Pprechess2.Positional_Interpolate (Shield_MG, Shield_EG, Phase)
                  * Shield
              - Pprechess2.Positional_Interpolate (Pressure_MG, Pressure_EG, Phase)
                  * Pressure;
      end One_King;

   begin
      return One_King (True) - One_King (False);
   end King_Safety;

end Eval_Terms;
