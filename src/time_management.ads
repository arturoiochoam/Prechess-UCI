-------------------------------------------------------------------------------
--  PRECHESS UCI - TIME CONTROL & SEARCH BUDGET MANAGEMENT
--
--  Module:        Time_Management
--  Language:      Ada 2022 (ISO/IEC 8652:2023)
--  Standard:      GNAT Community / FSF GCC (-gnat2022)
--  Author:        Arthur Matheus (UCI Time Management Layer)
--  Date:          2026
--
--  ARCHITECTURAL OVERVIEW:
--  `Time_Management` models standard UCI time-control modalities and dynamically
--  allocates real-time milliseconds budgets for search iterations.
--
--  TIME CONTROL PROTOCOLS & FORMULAE:
--  1. Fixed Depth (`go depth N`): `Time_Allocated = \infty`.
--  2. Move Time (`go movetime T`): `Time_Allocated = T - Overhead`.
--  3. Tournament (`wtime/btime ... movestogo N`):
--       Target = \lfloor Time\_Left / N \rfloor + Inc - Overhead
--  4. Sudden Death / Blitz (`wtime/btime ...` without `movestogo`):
--       Target = \lfloor Time\_Left / Assumed\_Moves \rfloor + Inc - Overhead
--       (where `Assumed_Moves = 30`).
--  5. Infinite (`go infinite`): `Time_Allocated = \infty`.
--
--  SAFETY MARGIN:
--  - Fixed safety buffer `Overhead_Ms = 20` ms protects against GUI latency,
--    pipe buffering, and process context switches, eliminating clock forfeits.
-------------------------------------------------------------------------------

with Ada.Real_Time; use Ada.Real_Time;

package Time_Management is

   ----------------------------------------------------------------------------
   --  TIME CONTROL MODALITIES
   ----------------------------------------------------------------------------
   type Time_Control_Type is
     (Fixed_Depth,
      Time_Per_Move,
      Tournament,
      All_In,
      Infinite);

   Search_Start_Time   : Time := Clock;
   Time_Allocated      : Time_Span := Time_Span_Last;
   Allocated_Budget_Ms : Integer := Integer'Last;
   Current_Control     : Time_Control_Type := Infinite;

   --  Requested depth specified by `go depth N` (0 if unbounded).
   Requested_Depth   : Integer := 0;

   --  Explicit node limit specified by `go nodes N` (0 if unbounded).
   Nodes_Limit       : Long_Long_Integer := 0;

   --  Set to True when time runs out, node limit is reached, or UCI `stop` is received.
   --  Marked Atomic and Volatile to support task-safe cooperative search cancellation.
   Search_Aborted    : Boolean := False with Atomic, Volatile;

   ----------------------------------------------------------------------------
   --  SEARCH LIFECYCLE MANAGEMENT
   ----------------------------------------------------------------------------
   --  Initializes time & node budgeting upon receiving a UCI `go` command.
   procedure Start_Search
     (WTime, BTime, WInc, BInc, Moves_To_Go, Move_Time, Depth : Integer;
      Is_White : Boolean;
      Infinite : Boolean;
      Nodes    : Long_Long_Integer := 0);

   --  Sets explicit node evaluation limit.
   procedure Set_Node_Limit (Limit : Long_Long_Integer) with Inline;

   --  Returns True if node evaluation budget has been exhausted.
   function Node_Limit_Reached return Boolean with Inline;

   --  Periodic time/node check invoked during search iterations.
   --  Sets `Search_Aborted := True` if `Elapsed_Ms >= Time_Allocated` or node limit reached.
   procedure Check_Time;

   --  Explicitly forces immediate search termination upon UCI `stop`.
   procedure Stop_Search;

   ----------------------------------------------------------------------------
   --  TELEMETRY & BUDGET QUERIES
   ----------------------------------------------------------------------------
   --  Returns milliseconds elapsed since `Start_Search` was invoked.
   function Elapsed_Ms return Integer;

   --  Returns milliseconds allocated for the current search iteration.
   function Allocated_Ms return Integer with Inline;

   --  0.9.9.17.16: temporarily reserves part of a bounded move budget for
   --  the Stage-7 verifier so the legacy cascade cannot consume the whole
   --  allocation. Restore_Time_Budget returns the original allocation before
   --  the verifier computes its own remaining-time budget. Both are no-ops
   --  for unbounded controls and when no reservation is active.
   procedure Reserve_Time_Slice (Reserve_Ms : Integer);
   procedure Restore_Time_Slice;

   --  T2: Dynamic safety overhead scaling with remaining clock time.
   function Effective_Overhead_Ms (Time_Left_Ms : Long_Long_Integer) return Long_Long_Integer;

   --  T2: Minimum defined floor for bullet time scrambles to prevent 1 ms collapse.
   Scramble_Budget_Floor : constant Long_Long_Integer := 20;

   --  Configurable UCI `Move Overhead` bounds and current margin (ms).
   Min_Move_Overhead_Ms     : constant := 10;
   Max_Move_Overhead_Ms     : constant := 500;
   Default_Move_Overhead_Ms : constant := 30;
   procedure Set_Move_Overhead (Ms : Integer);
   function Move_Overhead return Integer with Inline;

   --  Evaluates whether executing another PV-extension probe is permitted.
   --  For tournament/blitz games, PV probes are restricted to the first 25%
   --  of the allocated time budget to preserve search speed.
   function Allow_PV_Probe return Boolean;

end Time_Management;
