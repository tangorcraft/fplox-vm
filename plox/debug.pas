unit debug;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, chunk, value, common;

procedure disassembleChunk(const C: TChunk; const name: string);
function disassembleInstruction(const C: TChunk; const offset: integer): integer;

implementation

function simpleIntsruction(const name: string; const offset: integer): integer; overload;
begin
  print(name+NL);
  Result := offset + 1;
end;

function simpleIntsruction(const op: OpCode; const offset: integer): integer; overload;
var
  name: String;
begin
  Str(op, name);
  print(name+NL);
  Result := offset + 1;
end;

function byteIntsruction(const op: OpCode; const C: TChunk; const offset: integer): integer;
var
  slot: Byte;
  name: string;
begin
  Str(op, name);
  slot := C.code[offset+1];
  printf('%-16s %4d'+NL, [name, slot]);
  Result := offset + 2;
end;

function jumpIntsruction(const op: OpCode; const sign: Integer; const C: TChunk;
  const offset: integer): integer;
var
  jump: word;
  name: string;
begin
  Str(op, name);
  jump := Word(C.code[offset + 1]) shl 8;
  jump := jump or C.code[offset + 2];
  printf('%-16s %4d -> %d'+NL, [name, offset, offset + 3 + sign * jump]);
  Result := offset + 3;
end;

procedure print_constant(const name: string; const constant: integer; const V: TValue);
begin
  printf('%-16s %4d ', [name, constant]);
  printValue(V);
  print(NL);
end;

function constantIntsruction(const op: OpCode; const C: TChunk; const offset: integer): integer;
var
  constant: Byte;
  name: string;
begin
  Str(op, name);
  constant := C.code[offset+1];
  print_constant(name, constant, C.constants.values[constant]);
  Result := offset + 2;
end;

function constantLongIntsruction(const op: OpCode; const C: TChunk; const offset: integer): integer;
var
  constant: integer;
  name: string;
begin
  Str(op, name);
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
    OP_HALT,
    OP_PRINT,
    OP_RETURN,
    OP_NOT,
    OP_NEGATE,
    OP_EQUAL,
    OP_GREATER,
    OP_LESS,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_POP:
      Result := simpleIntsruction(instruction, offset);
    OP_CONSTANT,
    OP_SET_GLOBAL,
    OP_GET_GLOBAL,
    OP_DEFINE_GLOBAL:
      Result := constantIntsruction(instruction, C, offset);
    OP_CONSTANT_LONG,
    OP_SET_GLOBAL_LONG,
    OP_GET_GLOBAL_LONG,
    OP_DEFINE_GLOBAL_LONG:
      Result := constantLongIntsruction(instruction, C, offset);
    OP_SET_LOCAL,
    OP_GET_LOCAL:
      Result := byteIntsruction(instruction, C, offset);
    OP_JUMP,
    OP_JUMP_IF_FALSE,
    OP_JUMP_IF_FALSE_POP:
      Result := jumpIntsruction(instruction, 1, C, offset);
    OP_LOOP:
      Result := jumpIntsruction(instruction, -1, C, offset);

  else
    begin
      printf('Unknown opcode %d'+NL, [instruction]);
      Result := offset + 1;
    end;
  end;
end;

end.

