-------------------------------------------------------------------------------
--  PRECHESS UCI - MULTI-BUCKET TRANSPOSITION TABLE SPECIFICATION
--
--  Module:        TT_Table
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Layer & Transposition Engine)
--  Date:          2026
--
--  ARCHITECTURAL OVERVIEW:
--  `TT_Table` implements a high-performance, 4-way associative (4 buckets
--  per cluster) depth-preferred transposition table with generation-based
--  aging eviction.
--
--  CLUSTER ARCHITECTURE & MEMORY MAPPING:
--  The hash table is partitioned into N clusters, each containing exactly
--  `Bucket_Count = 4` consecutive `TT_Entry` records:
--
--    Cluster\_Index = Key \pmod{Num\_Clusters}
--    Base\_Slot     = Cluster\_Index \times 4
--    Slots          = [Base\_Slot .. Base\_Slot + 3]
--
--  REPLACEMENT POLICY HIERARCHY (in `Store_TT`):
--  1. Exact Key Refresh: If Key already resides in cluster [0..3], update it.
--  2. Empty Slot Fill:   If an unoccupied slot exists, populate it and bump
--                        the O(1) `Occupied_Count`.
--  3. Victim Eviction:   Identify the slot with the lowest search depth
--                        (shallower search); tie-break by oldest generation
--                        (earlier search epoch).
--
--  DYNAMIC HASHFULL TELEMETRY:
--  `Hash_Full_Permille` reports the exact share of slots holding entries of
--  the current generation [0 .. 1000], O(1) via a counter maintained by
--  Store_TT; any nonzero occupancy reports at least 1. It is generation-aware:
--  after `New_Generation`, prior-generation entries do not inflate the fresh
--  search's occupancy metric.
-------------------------------------------------------------------------------

with TT_Types; use TT_Types;

package TT_Table is

   ----------------------------------------------------------------------------
   --  SIZE BOUNDS (MEGABYTES)
   ----------------------------------------------------------------------------
   Min_Size_MB     : constant := 1;
   Max_Size_MB     : constant := 4096;
   --  0.9.9.17.12: 128 MB default for the shared legacy/reporting TT.
   --  The default-on Stage-7 verifier keeps its own fixed private table;
   --  sharing it with this table requires provenance-aware scores and is
   --  deliberately not implicit.
   Default_Size_MB : constant := 128;

   ----------------------------------------------------------------------------
   --  CLUSTER ASSOCIATIVITY
   ----------------------------------------------------------------------------
   --  Number of distinct entries per cluster. 4-way associativity provides
   --  an optimal trade-off between collision resistance and SIMD/cache-line fit.
   ----------------------------------------------------------------------------
   Bucket_Count : constant := 4;

   ----------------------------------------------------------------------------
   --  LIFECYCLE MANAGEMENT
   ----------------------------------------------------------------------------
   --  Allocates and formats the table at engine startup.
   procedure Init_TT (Size_MB : Natural);

   --  Dynamically resizes the table in response to `setoption name Hash value N`.
   --  Safe to invoke between searches; clears all entries and resets occupancy.
   procedure Resize_TT (Size_MB : Natural);

   --  Returns the current allocated size in megabytes (0 if allocation failed).
   function Current_Size_MB return Natural;

   --  Returns the number of multi-bucket clusters currently allocated (power of 2).
   function Cluster_Count return Hash_Key;

   --  Zeroes all slots and advances the generation epoch counter.
   --  Invoked on UCI `ucinewgame` to prevent cross-game probe pollution.
   procedure Clear_TT;

   --  N1/N2: Advances the generation epoch counter without wiping table entries.
   --  Invoked at the start of a search iteration or between positions.
   procedure New_Generation;

   ----------------------------------------------------------------------------
   --  SEARCH TRANSACTIONS
   ----------------------------------------------------------------------------
   --  Stores or refreshes a search node evaluation in the transposition table.
   --  Applies 4-way associative multi-bucket replacement rules.
   procedure Store_TT
     (Key   : Hash_Key;
      Depth : Integer;
      Score : Score_Type;
      Flag  : TT_Flag;
      Best  : Move_Type);

   --  Probes the table for an exact 64-bit Zobrist key match within its cluster.
   --  Returns True and populates `TT_Ent` on hit; returns False on miss.
   function Probe_TT (Key : Hash_Key; TT_Ent : out TT_Entry) return Boolean;

   ----------------------------------------------------------------------------
   --  TELEMETRY & AUDIT METRICS
   ----------------------------------------------------------------------------
   procedure Reset_TT_Counters;
   function TT_Probes return Long_Long_Integer;
   function TT_Stores return Long_Long_Integer;
   function TT_Hits   return Long_Long_Integer;
   function TT_Misses return Long_Long_Integer;

   --  Returns the exact number of bytes allocated in physical memory.
   function Current_Allocated_Bytes return Long_Long_Integer;

   --  Returns the exact table occupancy in permille [0 .. 1000] for UCI telemetry.
   function Hash_Full_Permille return Integer;

end TT_Table;
