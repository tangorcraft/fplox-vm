unit debug;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, chunk, value, common;

procedure disassembleChunk(const C: TChunk; const name: string);
function disassembleInstruction(const C: TChunk; const offset: integer): integer;

implementation

function simpleIntsruction(const name: string; const offset: integer): integer;
begin
  print(name+NL);
  Result := offset + 1;
end;

procedure print_constant(const name: string; const constant: integer; const V: TValue);
begin
  printf('%-16s %4d ', [name, constant]);
  printValue(V);
  print(NL);
end;

function constantIntsruction(const name: string; const C: TChunk; const offset: integer): integer;
var
  constant: Byte;
begin
  constant := C.code[offset+1];
  print_constant(name, constant, C.constants.values[constant]);
  Result := offset + 2;
end;

function constantLongIntsruction(const name: string; const C: TChunk; const offset: integer): integer;
var
  constant: integer;
begin
  constant := (C.code[offset+1] shl 16) + (C.code[offset+2] shl 8) + C.code[offset+3];
  print_constant(name, constant, C.constants.values[constant]);
  Result := offset + 4;
end;

procedure disassembleChunk(const C: TChunk; const name: string);
var
  offset: Integer;
begin
  printf('=== %s ==='+NL,[name]);

  offset := 0;
  while (offset < C.count) do
    offset := disassembleInstruction(C, offset);

  print('=== END ==='+NL);
end;

function disassembleInstruction(const C: TChunk; const offset: integer): integer;
var
  instruction: OpCode;
begin
  printf('%.4d ', [offset]);

  if (offset > 0) and (C.lines[offset] = C.lines[offset-1]) then
    print('   | ')
  else
    printf('%4d ',[C.lines[offset]]);

  instruction := OpCode(C.code[offset]);
  case (instruction) of
    OP_HALT:
      Result := simpleIntsruction('OP_HALT', offset);
    OP_RETURN:
      Result := simpleIntsruction('OP_RETURN', offset);
    OP_CONSTANT:
      Result := constantIntsruction('OP_CONSTANT', C, offset);
    OP_NEGATE:
      Result := simpleIntsruction('OP_NEGATE', offset);
    OP_ADD:
      Result := simpleIntsruction('OP_ADD', offset);
    OP_SUBTRACT:
      Result := simpleIntsruction('OP_SUBTRACT', offset);
    OP_MULTIPLY:
      Result := simpleIntsruction('OP_MULTIPLY', offset);
    OP_DIVIDE:
      Result := simpleIntsruction('OP_DIVIDE', offset);
    OP_CONSTANT_LONG:
      Result := constantLongIntsruction('OP_CONSTANT_LONG', C, offset);

  else
    begin
      printf('Unknown opcode %d'+NL, [instruction]);
      Result := offset + 1;
    end;
  end;
end;

end.

