package Pvalidade is

   subtype Square is Integer range 1 .. 64;
   type Board_Array is array (Square) of Integer;

   Tabuleiro : Board_Array;

   function Validade(A,B: in Integer) return Boolean
     with Pre => A in Square and then B in Square;

end Pvalidade;
