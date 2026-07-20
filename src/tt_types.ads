package TT_Types is
   pragma Preelaborate;

   --  Real node counter, bumped once per legality check performed by
   --  Pvalidade.Validade (the one call site every part of the legacy
   --  search funnels through). Placed here, in the dependency-free leaf
   --  package, so both Pvalidade and Search_Integration can see it
   --  without creating a circular "with" between them. Purely additive
   --  instrumentation: it does not affect any search decision.
   Nodes_Searched : Long_Long_Integer := 0;

   type Hash_Key is mod 2**64;
   
   type Score_Type is range -1000000 .. 1000000;
   
   type TT_Flag is (Exact, Lower_Bound, Upper_Bound);
   
   type Move_Type is record
      From_Sq : Integer range 1 .. 64;
      To_Sq   : Integer range 1 .. 64;
      Prom    : Integer range -20 .. 20; -- 0 means no promotion, else piece value
   end record;

   type TT_Entry is record
      Key     : Hash_Key;
      Depth   : Integer;
      Score   : Score_Type;
      Flag    : TT_Flag;
      Best    : Move_Type;
   end record;
   
end TT_Types;
