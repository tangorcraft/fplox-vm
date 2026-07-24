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

// conditionals that affect build
{$define USE_SIPHASH} // use FNV_1a hash if not defined
{$define NAN_BOXING}

// global macros defines
{$ifdef NAN_BOXING}
{$define IS_BOOL_VAL:=data or 1 = TRUE_VAL_INT}
{$define IS_NUMBER_VAL:=data and QNAN <> QNAN}
{$define IS_NIL_VAL:=data = NIL_VAL_INT}
{$define IS_OBJ_VAL:=data and QNAN_SIGN = QNAN_SIGN}
{$else}
{$define IS_BOOL_VAL:=type_=VAL_BOOL}
{$define IS_NUMBER_VAL:=type_=VAL_NUMBER}
{$define IS_NIL_VAL:=type_=VAL_NIL}
{$define IS_OBJ_VAL:=type_=VAL_OBJ}
{$endif}

