unit chunk;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, hash_set, object_, value, memory, common;

type
  OpCode = (
    OP_HALT,
    OP_PRINT,
    OP_JUMP,
    OP_JUMP_IF_FALSE,
    OP_JUMP_IF_FALSE_POP,
    OP_LOOP,
    OP_CALL,
    OP_CLOSURE,
    OP_CLOSURE_LONG,
    OP_CLOSE_UPVALUE,
    OP_RETURN,
    OP_CONSTANT,
    OP_CONSTANT_LONG,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_POP,
    OP_SET_LOCAL,
    OP_GET_LOCAL,
    OP_SET_UPVALUE,
    OP_GET_UPVALUE,
    OP_SET_GLOBAL,
    OP_SET_GLOBAL_LONG,
    OP_GET_GLOBAL,
    OP_GET_GLOBAL_LONG,
    OP_DEFINE_GLOBAL,
    OP_DEFINE_GLOBAL_LONG,
    OP_NOT,
    OP_NEGATE,
    OP_EQUAL,
    OP_GREATER,
    OP_LESS,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,

    OP_Invalid
  );

type

  { TChunk }

  TChunk = class(TMemArray)
  public
    code: PByte;
    constants: TValueArray;
    lines: array of Integer;
    objs: TObjectManager_SI;

    constructor Create(const aObjs: TObjectManager_SI);
    destructor Destroy; override;

    function addConstant(const V: TValue): Integer;

    procedure write(const B: Byte; const line: Integer); overload;
    procedure write(const B: OpCode; const line: Integer); overload;
    procedure write24(const I: Integer; const line: Integer);
    procedure writeConstant(const V: TValue; const line: Integer);
  end;

  TNativeFn = procedure (const args: PValue; const argCount: Integer; var result: TValue);
  TObjFunction = record
    obj: TLoxObj;
    arity: Integer;
    upvalueCount: integer;
    name: PObjString;
    case Byte of
    0: (chunk: TChunk);
    1: (nativeFn: TNativeFn);
  end;
  PObjFunction = ^TObjFunction;

  PObjUpvalue = ^TObjUpvalue;
  TObjUpvalue = record
    obj: TLoxObj;
    location: PValue;
    closed: TValue;
    next: PObjUpvalue;
  end;
  PPObjUpvalue = ^PObjUpvalue;

  // this way ObjClosure can be safely passed to anything that expect ObjFunction
  // no much  memory overhead since chunk is not a record that is allocated in ObjFunction, but a separate object
  TObjClosure = record
    func: TObjFunction;
    upvalues: PPObjUpvalue;
    upvalueCount: Integer;
  end;
  PObjClosure = ^TObjClosure;

  TObjChunk = record
    obj: TLoxObj;
    chunk: TChunk;
  end;
  PObjChunk = ^TObjChunk;

  { TObjectManager_Fun }

  TObjectManager_Fun = class(TObjectManager_SI)
  private
    function newChunk(): TChunk;
  public
    function newFunction(): PObjFunction;
    function newClosure(const fn: TObjFunction): PObjClosure;
    function newNative(const fn: TNativeFn): PObjFunction;
    function newUpvalue(const slot: PValue): PObjUpvalue;
  end;

{$inline on}

function IS_FUNCTION(const V: TValue): Boolean; inline;
function IS_CLOSURE(const V: TValue): Boolean; inline;
function IS_NATIVE_FN(const V: TValue): Boolean; inline;
function AS_FUNCTION(const V: TValue): PObjFunction; inline;
function AS_CLOSURE(const V: TValue): PObjClosure; inline;
procedure printFunction(const V: PObjFunction);

implementation

function IS_FUNCTION(const V: TValue): Boolean; inline;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_FUNCTION);
end;

function IS_CLOSURE(const V: TValue): Boolean;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_CLOSURE);
end;

function IS_NATIVE_FN(const V: TValue): Boolean; inline;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_NATIVE_FN);
end;

function AS_FUNCTION(const V: TValue): PObjFunction; inline;
begin
  Result := PObjFunction(V.as_obj);
end;

function AS_CLOSURE(const V: TValue): PObjClosure;
begin
  Result := PObjClosure(V.as_obj);
end;

procedure printFunction(const V: PObjFunction);
begin
  if V^.name = nil then
    print('<script>')
  else if V^.obj.type_ = OBJ_NATIVE_FN then
    printf('<nativeFn %s>', [V^.name^.chars])
  else
    printf('<fn %s>', [V^.name^.chars]);
end;

{ TChunk }

constructor TChunk.Create(const aObjs: TObjectManager_SI);
begin
  Init(SizeOf(Byte));
  code := Grow;
  SetLength(lines, capacity);
  constants := TValueArray.Create();
  objs := aObjs;
end;

destructor TChunk.Destroy;
begin
  constants.Free;
  SetLength(lines, 0);
  inherited Destroy;
end;

function TChunk.addConstant(const V: TValue): Integer;
begin
  constants.write(V);
  Result := constants.count - 1;
end;

procedure TChunk.write(const B: Byte; const line: Integer);
begin
  if capacity < (count + 1) then
  begin
    code := Grow;
    SetLength(lines, capacity);
  end;
  code[count] := B;
  lines[count] := line;
  inc(count);
end;

procedure TChunk.write(const B: OpCode; const line: Integer);
begin
  write(ord(B), line);
end;

procedure TChunk.write24(const I: Integer; const line: Integer);
begin
  write((I shr 16) and $FF, line);
  write((I shr 8) and $FF, line);
  write(I and $FF, line);
end;

procedure TChunk.writeConstant(const V: TValue; const line: Integer);
begin
  if constants.count < 255 then
  begin
    write(OP_CONSTANT, line);
    write(addConstant(V), line);
  end
  else
  begin
    write(OP_CONSTANT_LONG, line);
    write24(addConstant(V), line);
  end;
end;

{ TObjectManager_Fun }

function TObjectManager_Fun.newChunk(): TChunk;
var
  obj: PObjChunk;
begin
  Result := TChunk.Create(self);
  obj := allocateObject(sizeof(TObjChunk), OBJ_CHUNK);
  obj^.chunk := Result;
end;

function TObjectManager_Fun.newFunction(): PObjFunction;
begin
  Result := allocateObject(sizeof(TObjFunction), OBJ_FUNCTION);
  Result^.arity := 0;
  Result^.upvalueCount := 0;
  Result^.name := nil;
  Result^.chunk := newChunk();
end;

function TObjectManager_Fun.newClosure(const fn: TObjFunction): PObjClosure;
var
  obj: TLoxObj;
  upvalues: PPObjUpvalue;
begin
  upvalues := ALLOC_AND_ZERO_ARRAY(fn.upvalueCount, sizeof(PObjUpvalue));

  Result := allocateObject(sizeof(TObjClosure), OBJ_CLOSURE);
  obj := Result^.func.obj; // make sure fn will not overwrite TLoxObj header of closure object
  Result^.func := fn;
  Result^.func.obj := obj;
  Result^.upvalues := upvalues;
  Result^.upvalueCount := fn.upvalueCount;
end;

function TObjectManager_Fun.newNative(const fn: TNativeFn): PObjFunction;
begin
  Result := allocateObject(sizeof(TObjFunction), OBJ_NATIVE_FN);
  Result^.arity := 0;
  Result^.name := nil;
  Result^.nativeFn := fn;
end;

function TObjectManager_Fun.newUpvalue(const slot: PValue): PObjUpvalue;
begin
  Result := allocateObject(sizeof(TObjUpvalue), OBJ_UPVALUE);
  Result^.location := slot;
  Result^.closed := NIL_VAL;
  Result^.next := nil;
end;

end.

