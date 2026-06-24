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
  print(name+#13);
  Result := offset + 1;
end;

function constantIntsruction(const name: string; const C: TChunk; const offset: integer): integer;
var
  constant: Byte;
begin
  constant := C.code[offset+1];
  printf('%-16s %4d ', [name, constant]);
  printValue(C.constants.values[constant]);
  print(#13);
  Result := offset + 2;
end;

procedure disassembleChunk(const C: TChunk; const name: string);
var
  offset: Integer;
begin
  printf('=== %s ==='#13,[name]);

  offset := 0;
  while (offset < C.count) do
    offset := disassembleInstruction(C, offset);
end;

function disassembleInstruction(const C: TChunk; const offset: integer): integer;
var
  instruction: Byte;
begin
  printf('%.4d ', [offset]);

  if (offset > 0) and (C.lines[offset] = C.lines[offset-1]) then
    print('   | ')
  else
    printf('%4d ',[C.lines[offset]]);

  instruction := C.code[offset];
  case (instruction) of
    OP_RETURN:
      Result := simpleIntsruction('OP_RETURN', offset);
    OP_CONSTANT:
      Result := constantIntsruction('OP_CONSTANT', C, offset);

  else
    begin
      printf('Unknown opcode %d'#13, [instruction]);
      Result := offset + 1;
    end;
  end;
end;

end.

