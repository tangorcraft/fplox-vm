unit debug;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, chunk, value, common;

procedure disassembleChunk(const C: TChunk; const name: string);
function disassembleInstruction(const C: TChunk; const offset: integer): integer;

implementation

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
  printf('%-16s %4d "', [name, constant]);
  printValue(V);
  print('"'+NL);
end;

function closureInstruction(const op: OpCode; const C: TChunk; const constant: integer; const offset: integer): Integer;
var
  i: integer;
  name: string;
  func: PObjFunction;
  isLocal, index: integer;
begin
  Str(op, name);
  Result := offset + 1;
  print_constant(name, constant, C.constants.values[constant]);
  func := AS_FUNCTION(C.constants.values[constant]);
  for i := 0 to func^.fn.upvalueCount - 1 do
  begin
    isLocal := C.code[Result];
    inc(Result);
    index := C.code[Result];
    inc(Result);
    if isLocal = 0 then
      printf('%.4d      |                     upvalue %d'+NL,
             [Result - 2, index])
    else
      printf('%.4d      |                     local %d'+NL,
             [Result - 2, index]);
  end;
end;

function indexIntsruction(const op: OpCode; const C: TChunk; out index: integer; const offset: integer): integer;
var
  name: string;
begin
  Str(op, name);
  index := C.code[offset+1];
  Result := offset + 2;
  if op = OP_INDEX_LONG then
  begin
    index := (index shl 16) + (C.code[offset+2] shl 8) + C.code[offset+3];
    inc(Result, 2);
  end;
  printf('%-16s %4d'+NL, [name, index]);
end;

function constantIntsruction(const op: OpCode; const C: TChunk; const constant: integer; const offset: integer): integer; overload;
var
  name: String;
begin
  Str(op, name);
  print_constant(name, constant, C.constants.values[constant]);
  Result := offset + 1;
end;

function invokeIntsruction(const op: OpCode; const C: TChunk; const constant: integer; const offset: integer): integer; overload;
var
  name: String;
  argCount: Byte;
begin
  Str(op, name);
  argCount := C.code[offset + 1];
  printf('%-16s (%d args) %4d "', [name, argCount, constant]);
  printValue(C.constants.values[constant]);
  print('"'+NL);
  Result := offset + 2;
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
  indexConstant: Integer;
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
    OP_CLOSE_UPVALUE,
    OP_POP:
      Result := simpleIntsruction(instruction, offset);
    OP_CALL,
    OP_SET_UPVALUE,
    OP_GET_UPVALUE,
    OP_SET_LOCAL,
    OP_GET_LOCAL:
      Result := byteIntsruction(instruction, C, offset);
    OP_JUMP,
    OP_JUMP_IF_FALSE,
    OP_JUMP_IF_FALSE_POP:
      Result := jumpIntsruction(instruction, 1, C, offset);
    OP_LOOP:
      Result := jumpIntsruction(instruction, -1, C, offset);
    OP_INDEX,
    OP_INDEX_LONG: begin
      /// Index instruction
      Result := indexIntsruction(instruction, C, indexConstant, offset);

      printf('%.4d ', [Result]);

      if (Result > 0) and (C.lines[Result] = C.lines[Result-1]) then
        print('   | ')
      else
        printf('%4d ',[C.lines[Result]]);

      instruction := OpCode(C.code[Result]);
      case instruction of
        OP_CLASS,
        OP_METHOD,
        OP_CONSTANT,
        OP_SET_GLOBAL,
        OP_GET_GLOBAL,
        OP_SET_PORPERTY,
        OP_GET_PORPERTY,
        OP_DEFINE_GLOBAL:
          Result := constantIntsruction(instruction, C, indexConstant, Result);
        OP_CLOSURE:
          Result := closureInstruction(instruction, C, indexConstant, Result);
        OP_INVOKE:
          Result := invokeIntsruction(instruction, C, indexConstant, Result);

      else
        begin
          printf('Unknown opcode %d'+NL, [instruction]);
          Result := offset + 1;
        end;
      end;
      /// Index instruction end
    end;

  else
    begin
      printf('Unknown opcode %d'+NL, [instruction]);
      Result := offset + 1;
    end;
  end;
end;

end.

