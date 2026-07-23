begin
  if not ((PEEK_v0.IS_NUMBER_VAL) and (PEEK_v1.IS_NUMBER_VAL)) then
  begin
    runtimeError('Operands must be numbers.',[], local_ip);
    Exit(INTERPRET_RUNTIME_ERROR);
  end;
  temp.D := pop().as_number; // order matters
  push( MACRO_VAL (
    pop().as_number // a
    MACRO_OP
    temp.D // b
  ));
end;

