{$define DEBUG}

{$ifdef DEBUG}
  {$define DEBUG_SIPHASH}
  {$define DEBUG_PRINT_CODE}
  {$define DEBUG_TRACE_EXECUTION}
{$endif}

{$define USE_SIPHASH} // use FNV_1a hash if not defined

