{$define DEBUG}

{$ifdef DEBUG}
  {.$define DEBUG_SIPHASH}
  {$define DEBUG_PRINT_CODE}
  {$define DEBUG_TRACE_EXECUTION}
  {$define DEBUG_HASH_TABLE}
  {$define DEBUG_STRESS_GC}
  {$define DEBUG_LOG_GC}
{$endif}

// defining these options globally
{$macro on}
{$inline on}
// while these options are defined in the Lazarus project
// but plox folder can be used separately as a module for different project

{$define USE_SIPHASH} // use FNV_1a hash if not defined

