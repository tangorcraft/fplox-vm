unit vm;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, compiler,
  {$ifdef DEBUG_TRACE_EXECUTION}debug,{$endif}
  chunk, hash_set, object_, value, memory, common;

const
  MAX_STACK = 1024;

type
  InterpretResult = (
    INTERPRET_OK,
    INTERPRET_HALT,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR
  );

  { TLoxVM }

  TLoxVM = class
  public
    FChunk: TChunk;
    ip: PByte;
    stack: array[0..MAX_STACK] of TValue;
    stackTop: PValue;
    objs: TObjectManager_SI;

    procedure resetStack;
    procedure push(const V: TValue);
    function pop: TValue;
    function peek(const distance: Integer): PValue;
    procedure runtimeError(const Fmt: string; vars: array of const);
  public
    constructor Create;
    destructor Destroy; override;

    function interpret(const source: string): InterpretResult;
    function run(): InterpretResult;
  end;

implementation

{ TLoxVM }

procedure TLoxVM.resetStack;
begin
  stackTop := @stack[0];
end;

procedure TLoxVM.push(const V: TValue);
begin
  stackTop^ := V;
  inc(stackTop);
end;

function TLoxVM.pop: TValue;
begin
  dec(stackTop);
  Result := stackTop^;
end;

function TLoxVM.peek(const distance: Integer): PValue;
begin
  Result := stackTop - 1 - distance;
end;

procedure TLoxVM.runtimeError(const Fmt: string; vars: array of const);
var
  instruction: SizeInt;
  line: Integer;
begin
  printf(Fmt, vars, True);
  print(NL, true);
  instruction := SizeInt(ip - FChunk.code) - 1;
  line := FChunk.lines[instruction];
  printf('[line %d] in script'+NL, [line], true);
end;

constructor TLoxVM.Create;
begin
  resetStack;
  objs := TObjectManager_SI.Create;
end;

destructor TLoxVM.Destroy;
begin
  objs.Free;
  inherited Destroy;
end;

function TLoxVM.interpret(const source: string): InterpretResult;
begin
  FChunk := TChunk.Create(objs);
  try
    if not compile(source, FChunk) then
      Exit(INTERPRET_COMPILE_ERROR);

    ip := FChunk.code;
    Result := run();
  finally
    FChunk.Free;
    FChunk := nil;
  end;
end;

function TLoxVM.run: InterpretResult;
var
  instruction: OpCode;
  valA, valB: TValue;
  pval: PValue;

  function READ_BYTE: Byte;
  begin
    Result := ip^;
    Inc(ip);
  end;

  function READ_Code: OpCode;
  begin
    Result := OpCode(ip^);
    Inc(ip);
  end;

  function READ_CONSTANT: TValue;
  begin
    Result := FChunk.constants.values[READ_BYTE];
  end;

  function READ_CONSTANT_LONG: TValue;
  var
    index: integer;
  begin
    index := (READ_BYTE shl 16) or (READ_BYTE shl 8) or READ_BYTE;
    Result := FChunk.constants.values[index];
  end;

  function BINARY_NUM_OP(): Boolean;
  var
    a, b: double;
  begin
    if not (IS_NUMBER(peek(0)^) and IS_NUMBER(peek(1)^)) then
    begin
      runtimeError('Operands must be numbers.',[]);
      Exit(false);
    end;
    b := pop().as_number; // order matters
    a := pop().as_number;
    case instruction of
      OP_GREATER : push(BOOL_VAL(a > b));
      OP_LESS    : push(BOOL_VAL(a < b));
      OP_ADD     : push(NUMBER_VAL(a + b));
      OP_SUBTRACT: push(NUMBER_VAL(a - b));
      OP_MULTIPLY: push(NUMBER_VAL(a * b));
      OP_DIVIDE  : push(NUMBER_VAL(a / b));
    end;
    Result := true;
  end;

  procedure concatenate();
  var
    a, b: PObjString;
    len: Integer;
    s: PChar;
  begin
    b := AS_STRING(pop());
    a := AS_STRING(pop());
    len := a^.length_ + b^.length_;
    s := GROW_ARRAY(nil, 0, len + 1, SizeOf(char));
    memcpy(s, a^.chars, SizeOf(char) * a^.length_);
    memcpy(s + a^.length_, b^.chars, SizeOf(char) * b^.length_);
    s[len] := #0;
    push(OBJ_VAL(objs.takeString(s, len)));
  end;

  {$ifdef DEBUG_TRACE_EXECUTION}
  procedure debug_trace;
  var
    slot: PValue;
  begin
    slot := @stack[0];
    print('stack:    ');
    while (slot < stackTop) do
    begin
      print('[ ');
      printValue(slot^);
      print(' ]');
      inc(slot);
    end;
    print(NL);
    disassembleInstruction(FChunk, PtrUInt(ip-FChunk.code));
  end;
  {$endif}

begin
  while True do
  begin
    {$ifdef DEBUG_TRACE_EXECUTION}
    debug_trace;
    {$endif}
    instruction := READ_Code;
    case instruction of
      OP_HALT:
        Exit(INTERPRET_HALT);
      OP_RETURN: begin
        printValue(pop());
        print(NL);
        Exit(INTERPRET_OK);
      end;
      OP_CONSTANT: begin
        valA := READ_CONSTANT;
        push(valA);
      end;
      OP_NIL: push(NIL_VAL);
      OP_TRUE: push(BOOL_VAL(true));
      OP_FALSE: push(BOOL_VAL(false));
      OP_NOT:
        push(BOOL_VAL(isFalsey(pop())));
      OP_NEGATE: begin
        pval := peek(0);
        if not IS_NUMBER(pval^) then
        begin
          runtimeError('Operand must be a number.',[]);
          Exit(INTERPRET_RUNTIME_ERROR);
        end;
        pval^.as_number := -(pval^.as_number);
      end;
      OP_EQUAL: begin
        valB := pop();
        valA := pop();
        push(BOOL_VAL(valuesEqual(valA, valB)));
      end;
      OP_GREATER,
      OP_LESS:
        if not BINARY_NUM_OP() then Exit(INTERPRET_RUNTIME_ERROR);
      OP_ADD: begin
        if IS_STRING(peek(0)^) and IS_STRING(peek(1)^) then
          concatenate()
        else if IS_NUMBER(peek(0)^) and IS_NUMBER(peek(1)^) then
        begin
          valB := pop();
          valA := pop();
          push(NUMBER_VAL(valA.as_number + valB.as_number));
        end
        else begin
          runtimeError('Operands must be two numbers or two strings.',[]);
          Exit(INTERPRET_RUNTIME_ERROR);
        end;
      end;
      OP_SUBTRACT,
      OP_MULTIPLY,
      OP_DIVIDE:
        if not BINARY_NUM_OP() then Exit(INTERPRET_RUNTIME_ERROR);
    end;
  end;
end;

end.

