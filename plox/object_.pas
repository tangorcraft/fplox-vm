unit object_;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, value, memory, common;

type
  TObjString = record
    obj: TLoxObj;
    length_: Integer;
    chars: PChar;
    hash: UInt32;
  end;
  PObjString = ^TObjString;

  PMarker = ^TMarker;
  TMarker = record
    markRoots: TProcedureMethod;
    next: PMarker;
  end;

  { TObjectManager }

  TObjectManager = class(TMemoryManager)
  private
    firstMarker: PMarker;
    procedure markRoots();
  private
    grayStack: array of PLoxObj;
    grayCapacity: Integer;
    grayCount: Integer;
    procedure traceReferences();
    procedure blackenObject(const obj: PLoxObj);
    procedure sweep();
  protected
    sweepStringInternProc: TProcedureMethod;
    function allocateObject(const size: SizeInt; const type_: ObjType): Pointer;
    procedure freeObject(const O: PLoxObj);
    function allocateString(const start: PChar; const len: Integer; const hash: UInt32): PObjString;
    // moving to protected, should be only called from child class (string interning)
    function takeString(const chars: PChar; const len: Integer; const hash: UInt32): PObjString;
    function copyString(const start: PChar; const len: Integer; const hash: UInt32): PObjString;
  public
    objectsTop: PLoxObj;
    temporary: PLoxObj;

    procedure collectGarbage();
    procedure registerMarker(const markRootsProc: TProcedureMethod);
    procedure unregisterMarker(const markRootsProc: TProcedureMethod);
    procedure markValue(const V: TValue);
    procedure markObject(const O: PLoxObj);
    procedure markArray(const arr: TValueArray);

    constructor Create;
    destructor Destroy; override;
  end;

function OBJ_TYPE(const V: TValue): ObjType; inline;
function IS_STRING(const V: TValue): Boolean; inline;
function AS_STRING(const V: TValue): PObjString; inline;
function AS_CSTRING(const V: TValue): PChar; inline;

procedure printObject(const V: TValue; const err: Boolean = false);
function stringEqual(const A, B: TValue): Boolean;

implementation

uses
  chunk;

const
  markerSize = sizeof(TMarker);

function OBJ_TYPE(const V: TValue): ObjType; inline;
begin
  Result := AS_OBJ(V)^.type_;
end;

function IS_STRING(const V: TValue): Boolean; inline;
begin
  Result := (V IS_OBJ_VAL) and (AS_OBJ(V)^.type_ = OBJ_STRING);
end;

function AS_STRING(const V: TValue): PObjString;
begin
  Result := PObjString(AS_OBJ(V));
end;

function AS_CSTRING(const V: TValue): PChar;
begin
  Result := AS_STRING(V)^.chars;
end;

procedure printObject(const V: TValue; const err: Boolean);
begin
  case OBJ_TYPE(V) of
    OBJ_CLASS: printf('<class %s>', [AS_CLASS(V)^.name^.chars], err);
    OBJ_INSTANCE: printf('<instance of %s>', [AS_INSTANCE(V)^.klass^.name^.chars], err);
    OBJ_BOUND_METHOD: printFunction(PObjFunction(AS_BOUND_METHOD(V)^.method), err);
    OBJ_NATIVE_FN,
    OBJ_CLOSURE,
    OBJ_FUNCTION: printFunction(AS_FUNCTION(V), err);
    OBJ_UPVALUE: print('<upvalue>', err);
    OBJ_STRING: printf('%s',[AS_CSTRING(V)], err);
  end;
end;

function stringEqual(const A, B: TValue): Boolean;
var
  strA, strB: PObjString;
begin
  strA := AS_STRING(A);
  strB := AS_STRING(B);
  Result :=
    (strA^.length_ = strB^.length_) and
    (strcomp(strA^.chars, strB^.chars) = 0);
end;

{ TObjectManager }

{$ifdef DEBUG_LOG_GC}
function obj_type_str(const T: ObjType): string; begin str(T, Result); end;
{$endif}

procedure TObjectManager.markRoots();
var
  M: PMarker;
begin
  M := firstMarker;
  while M <> nil do
  begin
    M^.markRoots();
    M := M^.next;
  end;
end;

procedure TObjectManager.traceReferences();
var
  obj: PLoxObj;
begin
  while grayCount > 0 do
  begin
    dec(grayCount);
    obj := grayStack[grayCount];
    blackenObject(obj);
  end;
end;

procedure TObjectManager.blackenObject(const obj: PLoxObj);
var
  tmp: ObjEx;
  i: Integer;
begin
  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
  begin
    printf('%p blacken ', [obj], true);
    printValue(OBJ_VAL(obj), true);
    print(NL, true);
  end;
  {$endif}

  tmp.as_obj := obj;
  case obj^.type_ of
    OBJ_CLASS: begin
      markObject(PLoxObj(tmp.as_class^.name));
      tmp.as_class^.methods.markTable();
    end;
    OBJ_INSTANCE: begin
      markObject(PLoxObj(tmp.as_instance^.klass));
      tmp.as_instance^.fields.markTable();
    end;
    OBJ_BOUND_METHOD: begin
      markValue(tmp.as_bound_m^.receiver);
      markObject(PLoxObj(tmp.as_bound_m^.method));
    end;
    OBJ_NATIVE_FN: begin
      markObject(PLoxObj(tmp.as_func^.fn.name));
    end;
    OBJ_CLOSURE: begin
      markObject(PLoxObj(tmp.as_closure^.func.name));
      markArray(tmp.as_closure^.func.chunk.constants);
      for i := 0 to tmp.as_closure^.upvalueCount - 1 do
        markObject(PLoxObj(tmp.as_closure^.upvalues[i]));
    end;
    OBJ_FUNCTION: begin
      markObject( PLoxObj(tmp.as_func^.fn.name) );
      markArray(tmp.as_func^.fn.chunk.constants);
    end;
    OBJ_UPVALUE:
      markValue(tmp.as_upvalue^.closed);
    //OBJ_STRING: Exit;
  end;
end;

procedure TObjectManager.sweep();
var
  previous, obj, unreached: PLoxObj;
begin
  previous := nil;
  obj := objectsTop;
  while obj <> nil do
  begin
    if obj^.isMarked then
    begin
      obj^.isMarked := false;
      previous := obj;
      obj := obj^.next;
    end
    else
    begin
      unreached := obj;
      obj := obj^.next;
      if previous <> nil then
        previous^.next := obj
      else
        objectsTop := obj;

      freeObject(unreached);
    end;
  end;
end;

function TObjectManager.allocateObject(const size: SizeInt; const type_: ObjType): Pointer;
begin
  Result := ALLOCATE(size);
  PLoxObj(Result)^.type_ := type_;
  PLoxObj(Result)^.isMarked := false;
  PLoxObj(Result)^.size := size;
  PLoxObj(Result)^.next := objectsTop;
  objectsTop := Result;

  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
    printf('%p allocate %u for %s'+NL, [result, size, obj_type_str(type_)], true);
  {$endif}
end;

procedure TObjectManager.freeObject(const O: PLoxObj);
begin
  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
    printf('%p free type %s'+NL, [O, obj_type_str(O^.type_)], true);
  {$endif}

  case O^.type_ of
    OBJ_CLASS: begin
      PObjClass(O)^.methods.Free;
    end;
    OBJ_INSTANCE: begin
      PObjInstance(O)^.fields.Free;
    end;
    OBJ_FUNCTION: begin
      PObjFunction(O)^.fn.chunk.reference(false);
    end;
    OBJ_CLOSURE: begin
      with PObjClosure(O)^ do
      begin
        func.chunk.reference(false);
        FREE_ARRAY(upvalues, upvalueCount, sizeof(PObjUpvalue));
      end;
    end;
    OBJ_STRING: begin
      with PObjString(O)^ do
        FREE_ARRAY(chars, length_ + 1, SizeOf(Char));
    end;
  end;
  FREE_(O, O^.size);
end;

function TObjectManager.allocateString(const start: PChar; const len: Integer;
  const hash: UInt32): PObjString;
begin
  Result := allocateObject(sizeof(TObjString), OBJ_STRING);
  Result^.chars := start;
  Result^.length_ := len;
  Result^.hash := hash;
end;

constructor TObjectManager.Create;
begin
  inherited Create;
  objectsTop := nil;
  firstMarker := nil;
  grayCapacity := 32; // a bit of starting amount
  grayCount := 0;
  SetLength(grayStack, grayCapacity);
  collectGarbageProc := @collectGarbage;
end;

destructor TObjectManager.Destroy;
var
  nextO: PLoxObj;
  nextM: PMarker;
begin
  while objectsTop <> nil do
  begin
    nextO := objectsTop^.next;
    freeObject(objectsTop);
    objectsTop := nextO;
  end;
  while firstMarker <> nil do
  begin
    nextM := firstMarker^.next;
    FREE_(firstMarker, markerSize);
    firstMarker := nextM;
  end;
  SetLength(grayStack, 0);
  inherited Destroy;
end;

function TObjectManager.takeString(const chars: PChar; const len: Integer;
  const hash: UInt32): PObjString;
begin
  Result := allocateString(chars, len, hash);
end;

function TObjectManager.copyString(const start: PChar; const len: Integer;
  const hash: UInt32): PObjString;
var
  heapChars: PChar;
  cnt: SizeInt;
begin
  cnt := sizeof(Char) * (len + 1);
  heapChars := ALLOCATE(cnt);
  Move(start^, heapChars^, cnt);
  heapChars[len] := #0;
  Result := allocateString(heapChars, len, hash);
end;

procedure TObjectManager.collectGarbage();
begin
  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
    print('-- gc begin'+NL, true);
  {$endif}

  markObject(temporary);
  markRoots();
  traceReferences();
  if Assigned(sweepStringInternProc) then
    sweepStringInternProc();
  sweep();

  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
    print('-- gc end'+NL, true);
  {$endif}
end;

procedure TObjectManager.registerMarker(const markRootsProc: TProcedureMethod);
var
  M: PMarker;
begin
  M := ALLOCATE(markerSize);
  M^.markRoots := markRootsProc;
  M^.next := firstMarker;
  firstMarker := M;
end;

procedure TObjectManager.unregisterMarker(const markRootsProc: TProcedureMethod);
var
  prev: ^PMarker;
  curr: PMarker;
begin
  prev := @firstMarker;
  curr := firstMarker;
  while curr <> nil do
  begin
    if curr^.markRoots = markRootsProc then
    begin
      prev^ := curr^.next;
      FREE_(curr, markerSize);
      Exit;
    end;
    prev := @curr^.next;
    curr := curr^.next;
  end;
end;

procedure TObjectManager.markValue(const V: TValue);
begin
  if V IS_OBJ_VAL then
    markObject(AS_OBJ(V));
end;

procedure TObjectManager.markObject(const O: PLoxObj);
begin
  if O = nil then
    Exit;
  if O^.isMarked then
    Exit;

  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
  begin
    printf('%p mark ', [O], true);
    printValue(OBJ_VAL(O), true);
    print(NL, true);
  end;
  {$endif}

  O^.isMarked := True;

  if O^.type_ in [OBJ_STRING] then
    Exit;

  if grayCapacity < (grayCount + 1) then
  begin
    grayCapacity := GROW_CAPACITY(grayCapacity);
    SetLength(grayStack, grayCapacity);
  end;

  grayStack[grayCount] := O;
  inc(grayCount);
end;

procedure TObjectManager.markArray(const arr: TValueArray);
var
  i: Integer;
begin
  for i := 0 to arr.count - 1 do
    markValue(arr.values[i]);
end;

end.

