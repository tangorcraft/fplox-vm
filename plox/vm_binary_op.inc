begin
  if not (IS_NUMBER(PEEK_v0) and IS_NUMBER(PEEK_v1)) then
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

