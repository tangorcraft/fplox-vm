unit vm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, compiler, debug, chunk, value, common;

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

    procedure resetStack;
    procedure push(const V: TValue);
    function pop: TValue;
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

constructor TLoxVM.Create;
begin
  resetStack;
end;

destructor TLoxVM.Destroy;
begin
  inherited Destroy;
end;

function TLoxVM.interpret(const source: string): InterpretResult;
begin
  FChunk := TChunk.Create();
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
  instruction: Byte;
  constant: TValue;

  function READ_BYTE: Byte;
  begin
    Result := ip^;
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

  procedure BINARY_OP();
  var
    a, b: TValue;
  begin
    b := pop(); // order matters
    a := pop();
    case instruction of
      OP_ADD     : push(a+b);
      OP_SUBTRACT: push(a-b);
      OP_MULTIPLY: push(a*b);
      OP_DIVIDE  : push(a/b);
    end;
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
    instruction := READ_BYTE;
    case instruction of
      OP_HALT:
        Exit(INTERPRET_HALT);
      OP_RETURN: begin
        printValue(pop());
        print(NL);
        Exit(INTERPRET_OK);
      end;
      OP_CONSTANT: begin
        constant := READ_CONSTANT;
        push(constant);
      end;
      OP_NEGATE:
        push(-pop());
      OP_ADD,
      OP_SUBTRACT,
      OP_MULTIPLY,
      OP_DIVIDE:
        BINARY_OP();
    end;
  end;
end;

end.

