unit vm;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, compiler,
  {$ifdef DEBUG_TRACE_EXECUTION}debug,{$endif}
  chunk, hash_table, hash_set, object_, value, memory, common;

const
  FRAMES_MAX = 64;
  STACK_MAX = FRAMES_MAX * 1024;

type
  InterpretResult = (
    INTERPRET_OK,
    INTERPRET_HALT,
    INTERPRET_COMPILE_ERROR,
    INTERPRET_RUNTIME_ERROR
  );

  TCallFrame = record
    closure: PObjClosure;
    ip: PByte;
    slots: PValue;
  end;
  PCallFrame = ^TCallFrame;

  { TLoxVM }

  TLoxVM = class
  public
    stack: array[0..STACK_MAX] of TValue;
    stackTop: PValue;
    objs: TObjectManager_Fun;
    globals: THashTable;
    frames: array[0..FRAMES_MAX] of TCallFrame;
    frameCount: Integer;

    pause_callback: TMethod;
    halted: Boolean;

    procedure resetStack;
    procedure push(const V: TValue);
    function pop: TValue;
    procedure popN(const N: Integer);
    function peek(const distance: Integer): PValue;
    function call(const closure: PObjClosure; const argCount: Integer): Boolean;
    function callNative(const func: PObjFunction; const argCount: Integer): Boolean;
    function callValue(const callee: TValue; const argCount: Integer): Boolean;
    function captureUpvalue(const local: PValue): PObjUpvalue;
    procedure runtimeError(const Fmt: string; vars: array of const; const local_ip: PByte = nil);
  public
    constructor Create;
    destructor Destroy; override;

    procedure defineNative(const name: string; const arity: integer; const func: TNativeFn);

    procedure pause(const callback: TMethod);
    function is_paused: boolean;
    procedure stop;

    function interpret(const source: string): InterpretResult;
    function run(): InterpretResult;
  end;

implementation

const
   HoursPerDay = 24;
   MinsPerHour = 60;
   SecsPerMin  = 60;

   MinsPerDay  = HoursPerDay * MinsPerHour;
   SecsPerDay  = MinsPerDay * SecsPerMin;

procedure clockNative(const args: PValue; const argCount: Integer; var result: TValue);
begin
  result := NUMBER_VAL(Time() * SecsPerDay);
end;

{ TLoxVM }

procedure TLoxVM.resetStack;
begin
  stackTop := @stack[0];
  frameCount := 0;
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

procedure TLoxVM.popN(const N: Integer);
begin
  dec(stackTop, N);
end;

function TLoxVM.peek(const distance: Integer): PValue;
begin
  Result := stackTop - 1 - distance;
end;

function TLoxVM.call(const closure: PObjClosure; const argCount: Integer): Boolean;
var
  frame: PCallFrame;
begin
  if argCount <> closure^.func.arity then
  begin
    runtimeError('Expected %d arguments but got %d.', [closure^.func.arity, argCount]);
    Exit(false);
  end;

  if frameCount = FRAMES_MAX then
  begin
    runtimeError('Stack overflow.', []);
    Exit(false);
  end;

  frame := @frames[frameCount];
  inc(frameCount);
  frame^.closure := closure;
  frame^.ip := closure^.func.chunk.code;
  frame^.slots := stackTop - argCount - 1;
  Result := True;
end;

function TLoxVM.callNative(const func: PObjFunction; const argCount: Integer): Boolean;
var
  retVal: TValue;
begin
  // can set arity to -1 for native function to accept any number of arguments
  // since native function can't access VM object, it can't generate lox runtime errors
  if (func^.arity <> -1) and (argCount <> func^.arity) then
  begin
    runtimeError('Expected %d arguments but got %d.', [func^.arity, argCount]);
    Exit(false);
  end;

  retVal := NIL_VAL;
  func^.nativeFn(stackTop - argCount, argCount, retVal);
  dec(stackTop, argCount + 1);
  push(retVal);
  Result := True;
end;

function TLoxVM.callValue(const callee: TValue; const argCount: Integer): Boolean;
begin
  if IS_OBJ(callee) then
    case OBJ_TYPE(callee) of
      OBJ_CLOSURE:
        Exit(call(AS_CLOSURE(callee), argCount));
      OBJ_NATIVE_FN:
        Exit(callNative(AS_FUNCTION(callee), argCount));
    end;
  runtimeError('Can only call functions and classes.', []);
  Result := false;
end;

function TLoxVM.captureUpvalue(const local: PValue): PObjUpvalue;
begin
  Result := objs.newUpvalue(local);
end;

procedure TLoxVM.runtimeError(const Fmt: string; vars: array of const; const local_ip: PByte);
var
  frame: PCallFrame;
  func: PObjFunction;
  instruction: SizeInt;
  line, i: Integer;
begin
  printf(Fmt, vars, True);
  print(NL, true);

  if local_ip <> nil then
    frames[frameCount - 1].ip := local_ip;
  for i := frameCount - 1 downto 0 do
  begin
    frame := @frames[i];
    func := @frame^.closure^.func;
    instruction := SizeInt(frame^.ip - func^.chunk.code) - 1;
    line := func^.chunk.lines[instruction];
    printf('[line %d] in ', [line], true);
    if func^.name = nil then
      print('script'+NL, true)
    else
      printf('%s()'+NL, [func^.name^.chars], true);
  end;

  resetStack();
end;

constructor TLoxVM.Create;
begin
  resetStack;
  objs := TObjectManager_Fun.Create;
  globals := THashTable.Create(objs);

  defineNative('clock', 0, @clockNative);
end;

destructor TLoxVM.Destroy;
begin
  globals.Free;
  objs.Free;
  inherited Destroy;
end;

procedure TLoxVM.defineNative(const name: string; const arity: integer; const func: TNativeFn);
begin
  push(OBJ_VAL(objs.copyString(PChar(name), length(name))));
  push(OBJ_VAL(objs.newNative(func)));
  AS_FUNCTION(stack[1])^.arity := arity;
  AS_FUNCTION(stack[1])^.name := AS_STRING(stack[0]);
  globals.tableSet(AS_STRING(stack[0]), stack[1]);
  popN(2);
end;

procedure TLoxVM.pause(const callback: TMethod);
begin
  pause_callback := callback;
end;

function TLoxVM.is_paused: boolean;
begin
  Result := Assigned(pause_callback);
end;

procedure TLoxVM.stop;
begin
  halted := true;
end;

function TLoxVM.interpret(const source: string): InterpretResult;
var
  func: PObjFunction;
  closure: PObjClosure;
begin
  func := compile(source, objs);
  if func = nil then
    Exit(INTERPRET_COMPILE_ERROR);

  push(OBJ_VAL(func));
  closure := objs.newClosure(func^);
  pop();
  push(OBJ_VAL(closure));
  call(closure, 0);

  Result := run();
end;

{$inline on}

type
  TTempUnion = record
    case Byte of
    0: (name: PObjString);
    1: (chunk: PObjChunk);
    2: (closure: PObjClosure);
    3: (func: PObjFunction);
    4: (B: byte);
    5: (W: word);
    6: (D: double);
    7: (pval: PValue);
    //8: (val: TValue);
  end;

function TLoxVM.run: InterpretResult;
var
  instruction: OpCode;
  local_ip: PByte;
  frame: PCallFrame;
  valA, valB: TValue;
  temp: TTempUnion;
  i: Integer;

  function READ_BYTE: Byte; inline;
  begin
    Result := local_ip^;
    Inc(local_ip);
  end;

  function READ_Code: OpCode; inline;
  begin
    Result := OpCode(local_ip^);
    Inc(local_ip);
  end;

  function READ_SHORT: Word; inline;
  begin
    Result := (local_ip[0] shl 8) or local_ip[1];
    Inc(local_ip, 2);
  end;

  function READ_CONSTANT: TValue;
  begin
    Result := frame^.closure^.func.chunk.constants.values[READ_BYTE];
  end;

  function READ_CONSTANT_LONG: TValue;
  var
    index: integer;
  begin
    index := (READ_BYTE shl 16) or (READ_BYTE shl 8) or READ_BYTE;
    Result := frame^.closure^.func.chunk.constants.values[index];
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
    disassembleInstruction(frame^.closure^.func.chunk, PtrUInt(local_ip - frame^.closure^.func.chunk.code));
  end;
  {$endif}

begin
  halted := false;
  frame := @frames[frameCount - 1];
  local_ip := frame^.ip;
  while True do
  begin
    {$ifdef DEBUG_TRACE_EXECUTION}
    if debugTraceExecution then
      debug_trace;
    {$endif}

    if halted then
      Exit(INTERPRET_HALT);
    while Assigned(pause_callback) do
    begin
      pause_callback();
      if halted then
        Exit(INTERPRET_HALT);
      sleep(1);
    end;

    instruction := READ_Code;
    case instruction of
      OP_HALT:
        Exit(INTERPRET_HALT);
      OP_PRINT: begin
        printValue(pop());
        print(NL);
      end;
      OP_JUMP: begin
        temp.W := READ_SHORT(); // offset
        inc(local_ip, temp.W);
      end;
      OP_JUMP_IF_FALSE: begin
        temp.W := READ_SHORT();
        if isFalsey(peek(0)^) then
          inc(local_ip, temp.W);
      end;
      OP_JUMP_IF_FALSE_POP: begin
        temp.W := READ_SHORT();
        if isFalsey(pop()) then
          inc(local_ip, temp.W);
      end;
      OP_LOOP: begin
        temp.W := READ_SHORT;
        Dec(local_ip, temp.W);
      end;
      OP_CALL: begin
        temp.B := READ_BYTE(); // argCount
        frame^.ip := local_ip;
        if not callValue(peek(temp.B)^, temp.B) then
          Exit(INTERPRET_RUNTIME_ERROR);
        frame := @frames[frameCount - 1];
        local_ip := frame^.ip;
      end;
      OP_CLOSURE,
      OP_CLOSURE_LONG: begin
        if instruction = OP_CLOSURE then
          temp.func := AS_FUNCTION(READ_CONSTANT)
        else
          temp.func := AS_FUNCTION(READ_CONSTANT_LONG);
        temp.closure := objs.newClosure(temp.func^);
        push(OBJ_VAL(temp.closure));
        for i := 0 to temp.closure^.upvalueCount - 1 do
        begin
          if READ_BYTE() = 1 then // isLocal
            temp.closure^.upvalues[i] := captureUpvalue(frame^.slots + READ_BYTE()) // index
          else
            temp.closure^.upvalues[i] := frame^.closure^.upvalues[READ_BYTE()]; // index
        end;
      end;
      OP_RETURN: begin
        valA := pop();
        dec(frameCount);
        if frameCount = 0 then
        begin
          pop();
          Exit(INTERPRET_OK);
        end;

        stackTop := frame^.slots;
        push(valA);
        frame := @frames[frameCount - 1];
        local_ip := frame^.ip;
      end;
      OP_CONSTANT: begin
        valA := READ_CONSTANT;
        push(valA);
      end;
      OP_CONSTANT_LONG: begin
        valA := READ_CONSTANT_LONG;
        push(valA);
      end;
      OP_NIL: push(NIL_VAL);
      OP_TRUE: push(BOOL_VAL(true));
      OP_FALSE: push(BOOL_VAL(false));
      OP_POP: pop();
      OP_SET_LOCAL: begin
        temp.B := READ_BYTE; // slot
        frame^.slots[temp.B] := peek(0)^;
      end;
      OP_GET_LOCAL: begin
        temp.B := READ_BYTE; // slot
        push(frame^.slots[temp.B]);
      end;
      OP_SET_UPVALUE: begin
        temp.B := READ_BYTE; // slot
        frame^.closure^.upvalues[temp.B]^.location^ := peek(0)^;
      end;
      OP_GET_UPVALUE: begin
        temp.B := READ_BYTE; // slot
        push(frame^.closure^.upvalues[temp.B]^.location^);
      end;
      OP_SET_GLOBAL,
      OP_SET_GLOBAL_LONG: begin
        if instruction = OP_SET_GLOBAL then
          temp.name := AS_STRING(READ_CONSTANT)
        else
          temp.name := AS_STRING(READ_CONSTANT_LONG);
        // tableSet return True if key is new, i.e. don't exist in hash table
        // no value is set then if mustExist is also True
        if globals.tableSet(temp.name, peek(0)^, true) then
        begin
          // so no need for deletion
          // but is it faster this way?
          runtimeError('Undefined variable "%s".',[temp.name^.chars], local_ip);
          Exit(INTERPRET_RUNTIME_ERROR);
        end;
      end;
      OP_GET_GLOBAL,
      OP_GET_GLOBAL_LONG: begin
        if instruction = OP_GET_GLOBAL then
          temp.name := AS_STRING(READ_CONSTANT)
        else
          temp.name := AS_STRING(READ_CONSTANT_LONG);
        if not globals.tableGet(temp.name, valA) then
        begin
          runtimeError('Undefined variable "%s".',[temp.name^.chars], local_ip);
          Exit(INTERPRET_RUNTIME_ERROR);
        end;
        push(valA);
      end;
      OP_DEFINE_GLOBAL: begin
        temp.name := AS_STRING(READ_CONSTANT);
        globals.tableSet(temp.name, peek(0)^);
        pop();
      end;
      OP_DEFINE_GLOBAL_LONG: begin
        temp.name := AS_STRING(READ_CONSTANT_LONG);
        globals.tableSet(temp.name, peek(0)^);
        pop();
      end;
      OP_NOT:
        push(BOOL_VAL(isFalsey(pop())));
      OP_NEGATE: begin
        temp.pval := peek(0);
        if not IS_NUMBER(temp.pval^) then
        begin
          runtimeError('Operand must be a number.',[], local_ip);
          Exit(INTERPRET_RUNTIME_ERROR);
        end;
        temp.pval^.as_number := -(temp.pval^.as_number);
      end;
      OP_EQUAL: begin
        valB := pop();
        valA := pop();
        push(BOOL_VAL(valuesEqual(valA, valB)));
      end;
      {$macro on}
      OP_GREATER:
        {$define MACRO_VAL:=BOOL_VAL}
        {$define MACRO_OP:=>}
        {$i vm_binary_op.inc}
      OP_LESS:
        {$define MACRO_VAL:=BOOL_VAL}
        {$define MACRO_OP:=<}
        {$i vm_binary_op.inc}
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
          runtimeError('Operands must be two numbers or two strings.',[], local_ip);
          Exit(INTERPRET_RUNTIME_ERROR);
        end;
      end;
      OP_SUBTRACT:
        {$define MACRO_VAL:=NUMBER_VAL}
        {$define MACRO_OP:=-}
        {$i vm_binary_op.inc}
      OP_MULTIPLY:
        {$define MACRO_VAL:=NUMBER_VAL}
        {$define MACRO_OP:=*}
        {$i vm_binary_op.inc}
      OP_DIVIDE:
        {$define MACRO_VAL:=NUMBER_VAL}
        {$define MACRO_OP:=/}
        {$i vm_binary_op.inc}

      {$undef MACRO_VAL}
      {$undef MACRO_OP}
      {$macro off}
    end;
  end;
end;

end.

