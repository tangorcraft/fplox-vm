unit chunk;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, hash_table, hash_set, object_, value, memory, common;

type
  OpCode = (
    OP_HALT,
    OP_PRINT,
    OP_JUMP,
    OP_JUMP_IF_FALSE,
    OP_JUMP_IF_FALSE_POP,
    OP_LOOP,
    OP_CALL,
    OP_INHERIT,
    OP_CLOSE_UPVALUE,
    OP_RETURN,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_POP,
    OP_SET_LOCAL,
    OP_GET_LOCAL,
    OP_SET_UPVALUE,
    OP_GET_UPVALUE,
    OP_NOT,
    OP_NEGATE,
    OP_EQUAL,
    OP_GREATER,
    OP_LESS,
    OP_ADD,
    OP_SUBTRACT,
    OP_MULTIPLY,
    OP_DIVIDE,
    OP_INDEX,
    OP_INDEX_LONG,
    // special OP code that reads an index for the next upcode
    // must be folloed by one of these OP codes:
      OP_CONSTANT,
      OP_CLOSURE,
      OP_SET_GLOBAL,
      OP_GET_GLOBAL,
      OP_DEFINE_GLOBAL,
      OP_CLASS,
      OP_METHOD,
      OP_INVOKE,
      OP_GET_SUPER,
      OP_SUPER_INVOKE,
      OP_SET_PORPERTY,
      OP_GET_PORPERTY,

    OP_Invalid
  );

type

  { TChunk }

  TChunk = class(TMemArray)
  public
    code: PByte;
    constants: TValueArray;
    lines: array of Integer;
    MM: TObjectManager_SI;

    refCount: Integer;
    procedure reference(const countUp: Boolean);

    constructor Create(const objMgr: TObjectManager_SI);
    destructor Destroy; override;

    function addConstant(const V: TValue): Integer;

    procedure write(const B: Byte; const line: Integer); overload;
    procedure write(const B: OpCode; const line: Integer); overload;
    procedure write24(const I: Integer; const line: Integer);
  end;

  TNativeFn = procedure (const args: PValue; const argCount: Integer; var result: TValue);
  TFnData = record
    arity: Integer;
    name: PObjString;
    case Byte of
    0: (
      upvalueCount: integer;
      chunk: TChunk;
      );
    1: (
      nativeFn: TNativeFn;
      );
  end;
  TObjFunction = record
    obj: TLoxObj;
    fn: TFnData;
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
    obj: TLoxObj;
    func: TFnData;
    upvalues: PPObjUpvalue;
    upvalueCount: Integer;
  end;
  PObjClosure = ^TObjClosure;

  TObjClass = record
    obj: TLoxObj;
    name: PObjString;
    methods: THashTable;
  end;
  PObjClass = ^TObjClass;

  TObjInstance = record
    obj: TLoxObj;
    klass: PObjClass;
    fields: THashTable;
  end;
  PObjInstance = ^TObjInstance;

  TObjBoundMethod = record
    obj: TLoxObj;
    receiver: TValue;
    method: PObjClosure;
  end;
  PObjBoundMethod = ^TObjBoundMethod;

  { TObjectManager_Fun }

  TObjectManager_Fun = class(TObjectManager_SI)
  public
    function newClass(const name: PObjString): PObjClass;
    function newInstance_(const klass: PObjClass): PObjInstance;
    function newBoundMethod(const receiver: TValue; const method: PObjClosure): PObjBoundMethod;

    function newFunction(): PObjFunction;
    function newClosure(const func: TObjFunction): PObjClosure;
    function newNative(const fn: TNativeFn; const name: PObjString): PObjFunction;
    function newUpvalue(const slot: PValue): PObjUpvalue;
  end;

  ObjEx = record
  case Byte of
  0:(as_obj: PLoxObj);
  1:(as_string: PObjString);
  2:(as_closure: PObjClosure);
  3:(as_func: PObjFunction);
  4:(as_upvalue: PObjUpvalue);
  5:(as_class: PObjClass);
  6:(as_instance: PObjInstance);
  7:(as_bound_m: PObjBoundMethod);
  end;

function IS_FUNCTION(const V: TValue): Boolean; inline;
function IS_CLOSURE(const V: TValue): Boolean; inline;
function IS_NATIVE_FN(const V: TValue): Boolean; inline;
function IS_CLASS(const V: TValue): Boolean; inline;
function IS_INSTANCE(const V: TValue): Boolean; inline;
function IS_BOUND_METHOD(const V: TValue): Boolean; inline;

function AS_FUNCTION(const V: TValue): PObjFunction; inline;
function AS_CLOSURE(const V: TValue): PObjClosure; inline;
function AS_CLASS(const V: TValue): PObjClass; inline;
function AS_INSTANCE(const V: TValue): PObjInstance; inline;
function AS_BOUND_METHOD(const V: TValue): PObjBoundMethod; inline;

procedure printFunction(const V: PObjFunction; const err: Boolean = false);

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

function IS_CLASS(const V: TValue): Boolean;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_CLASS);
end;

function IS_INSTANCE(const V: TValue): Boolean;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_INSTANCE);
end;

function IS_BOUND_METHOD(const V: TValue): Boolean;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_BOUND_METHOD);
end;

function AS_FUNCTION(const V: TValue): PObjFunction; inline;
begin
  Result := PObjFunction(V.as_obj);
end;

function AS_CLOSURE(const V: TValue): PObjClosure;
begin
  Result := PObjClosure(V.as_obj);
end;

function AS_CLASS(const V: TValue): PObjClass;
begin
  Result := PObjClass(V.as_obj);
end;

function AS_INSTANCE(const V: TValue): PObjInstance;
begin
  Result := PObjInstance(V.as_obj);
end;

function AS_BOUND_METHOD(const V: TValue): PObjBoundMethod;
begin
  Result := PObjBoundMethod(V.as_obj);
end;

procedure printFunction(const V: PObjFunction; const err: Boolean);
begin
  if V^.fn.name = nil then
    print('<script>', err)
  else if V^.obj.type_ = OBJ_NATIVE_FN then
    printf('<nativeFn %s>', [V^.fn.name^.chars], err)
  else
    printf('<fn %s>', [V^.fn.name^.chars], err);
end;

{ TChunk }

procedure TChunk.reference(const countUp: Boolean);
begin
  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
  begin
    if countUp then
      printf('%p reference count %d + 1'+NL, [pointer(self), refCount], true)
    else
      printf('%p reference count %d - 1'+NL, [pointer(self), refCount], true);
  end;
  {$endif}
  if countUp then
    inc(refCount)
  else
  begin
    dec(refCount);
    if refCount <= 0 then
      Free;
  end;
end;

constructor TChunk.Create(const objMgr: TObjectManager_SI);
begin
  inherited Create(objMgr);
  Init(SizeOf(Byte));
  code := Grow;
  SetLength(lines, capacity);
  constants := TValueArray.Create(objMgr);
  MM := objMgr;
  refCount := 0;
end;

destructor TChunk.Destroy;
begin
  constants.Free;
  SetLength(lines, 0);
  inherited Destroy;
end;

function TChunk.addConstant(const V: TValue): Integer;
begin
  Result := constants.find(V);
  if Result <> -1 then
    Exit;
  if (V.IS_OBJ_VAL) then
    MM.temporary := V.as_obj;
  constants.write(V);
  Result := constants.count - 1;
  MM.temporary := nil;
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

{ TObjectManager_Fun }

function TObjectManager_Fun.newClass(const name: PObjString): PObjClass;
begin
  Result := allocateObject(sizeof(TObjClass), OBJ_CLASS);
  Result^.name := name;
  Result^.methods := THashTable.Create(Self);
end;

function TObjectManager_Fun.newInstance_(const klass: PObjClass): PObjInstance;
begin
  Result := allocateObject(sizeof(TObjInstance), OBJ_INSTANCE);
  Result^.klass := klass;
  Result^.fields := THashTable.Create(Self);
end;

function TObjectManager_Fun.newBoundMethod(const receiver: TValue;
  const method: PObjClosure): PObjBoundMethod;
begin
  Result := allocateObject(sizeof(TObjBoundMethod), OBJ_BOUND_METHOD);
  Result^.receiver := receiver;
  Result^.method := method;
end;

function TObjectManager_Fun.newFunction(): PObjFunction;
var
  chunk: TChunk;
begin
  chunk := TChunk.Create(Self);
  // since GC can be called on any allocation I create TChunk before allocating ObjFunction
  // this way GC will not collect new ObjFunction when TChunk allocates memory on creation
  // GC will not manage TChunk object directly, TChunk will use reference count
  Result := allocateObject(sizeof(TObjFunction), OBJ_FUNCTION);
  Result^.fn.arity := 0;
  Result^.fn.upvalueCount := 0;
  Result^.fn.name := nil;
  Result^.fn.chunk := chunk;
  Result^.fn.chunk.reference(true);
end;

function TObjectManager_Fun.newClosure(const func: TObjFunction): PObjClosure;
var
  upvalues: PPObjUpvalue;
begin
  upvalues := ALLOC_AND_ZERO_ARRAY(func.fn.upvalueCount, sizeof(PObjUpvalue));

  Result := allocateObject(sizeof(TObjClosure), OBJ_CLOSURE);
  Result^.func := func.fn;
  Result^.func.chunk.reference(true);
  Result^.upvalues := upvalues;
  Result^.upvalueCount := func.fn.upvalueCount;
end;

function TObjectManager_Fun.newNative(const fn: TNativeFn;
  const name: PObjString): PObjFunction;
begin
  Result := allocateObject(sizeof(TObjFunction), OBJ_NATIVE_FN);
  Result^.fn.arity := 0;
  Result^.fn.name := name;
  Result^.fn.nativeFn := fn;
end;

function TObjectManager_Fun.newUpvalue(const slot: PValue): PObjUpvalue;
begin
  Result := allocateObject(sizeof(TObjUpvalue), OBJ_UPVALUE);
  Result^.location := slot;
  Result^.closed := NIL_VAL;
  Result^.next := nil;
end;

end.

