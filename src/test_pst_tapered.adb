with Ada.Text_IO; use Ada.Text_IO;
with Pvalidade; use Pvalidade;
with pprechess2;

procedure Test_PST_Tapered is

   procedure Assert (Cond : Boolean; Msg : String) is
   begin
      if not Cond then
         Put_Line ("TEST_PST_TAPERED: FAIL - " & Msg);
         raise Program_Error;
      end if;
   end Assert;

   function Sq (Rank, File : Integer) return Integer is
     ((Rank - 1) * 8 + File);

   procedure Clear_Board is
   begin
      Tabuleiro := (others => 0);
   end Clear_Board;

   procedure Set_Starting_Material is
   begin
      Clear_Board;
      Tabuleiro (Sq (1, 1)) := 7;    Tabuleiro (Sq (1, 8)) := 7;
      Tabuleiro (Sq (1, 2)) := 4;    Tabuleiro (Sq (1, 7)) := 4;
      Tabuleiro (Sq (1, 3)) := 3;    Tabuleiro (Sq (1, 6)) := 3;
      Tabuleiro (Sq (1, 4)) := 20;   Tabuleiro (Sq (1, 5)) := 999;
      for F in 1 .. 8 loop
         Tabuleiro (Sq (2, F)) := 1;
         Tabuleiro (Sq (7, F)) := -1;
      end loop;
      Tabuleiro (Sq (8, 1)) := -7;   Tabuleiro (Sq (8, 8)) := -7;
      Tabuleiro (Sq (8, 2)) := -4;   Tabuleiro (Sq (8, 7)) := -4;
      Tabuleiro (Sq (8, 3)) := -3;   Tabuleiro (Sq (8, 6)) := -3;
      Tabuleiro (Sq (8, 4)) := -20;  Tabuleiro (Sq (8, 5)) := -999;
   end Set_Starting_Material;

begin
   Set_Starting_Material;
   Assert (pprechess2.Positional_Game_Phase = 0,
           "full material must be pure middlegame phase 0");

   Clear_Board;
   Tabuleiro (Sq (1, 5)) := 999;
   Tabuleiro (Sq (8, 5)) := -999;
   for F in 1 .. 8 loop
      Tabuleiro (Sq (2, F)) := 1;
      Tabuleiro (Sq (7, F)) := -1;
   end loop;
   Assert (pprechess2.Positional_Game_Phase = 256,
           "kings and pawns only must be pure endgame phase 256");

   Clear_Board;
   Tabuleiro (Sq (1, 5)) := 999;
   Tabuleiro (Sq (8, 5)) := -999;
   Tabuleiro (Sq (1, 4)) := 20;
   Tabuleiro (Sq (8, 4)) := -20;
   declare
      Queen_Phase : constant Integer := pprechess2.Positional_Game_Phase;
   begin
      Tabuleiro (Sq (1, 1)) := 7;
      Tabuleiro (Sq (8, 1)) := -7;
      Assert (pprechess2.Positional_Game_Phase < Queen_Phase,
              "adding rooks must move phase back toward middlegame");
   end;

   Assert (pprechess2.Positional_Interpolate (10, 30, 0) = 10,
           "phase 0 interpolation must return MG value");
   Assert (pprechess2.Positional_Interpolate (10, 30, 256) = 30,
           "phase 256 interpolation must return EG value");

   Assert (pprechess2.Positional_Test_Score (999, Sq (4, 4), 256) >
           pprechess2.Positional_Test_Score (999, Sq (4, 4), 0),
           "central king square must improve in endgame versus middlegame");

   Assert (pprechess2.Positional_Test_Score (1, Sq (4, 5), 0) >
           pprechess2.Positional_Test_Score (1, Sq (3, 2), 0),
           "opening pawn tie-break must prefer central play over b-pawn shuffles");

   Put_Line ("TEST_PST_TAPERED: PASS");
end Test_PST_Tapered;
