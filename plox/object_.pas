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
  protected
    function allocateObject(const size: SizeInt; const type_: ObjType): Pointer;
    procedure freeObject(const O: PLoxObj);
    function allocateString(const start: PChar; const len: Integer; const hash: UInt32): PObjString;
    // moving to protected, should be only called from child class (string interning)
    function takeString(const chars: PChar; const len: Integer; const hash: UInt32): PObjString;
    function copyString(const start: PChar; const len: Integer; const hash: UInt32): PObjString;
  public
    objectsTop: PLoxObj;

    procedure collectGarbage();
    procedure registerMarker(const markRootsProc: TProcedureMethod);
    procedure unregisterMarker(const markRootsProc: TProcedureMethod);
    procedure markValue(const V: TValue);
    procedure markObject(const O: PLoxObj);

    constructor Create;
    destructor Destroy; override;
  end;

function OBJ_TYPE(const V: TValue): ObjType; inline;
function IS_STRING(const V: TValue): Boolean; inline;
function AS_STRING(const V: TValue): PObjString; inline;
function AS_CSTRING(const V: TValue): PChar; inline;

procedure printObject(const V: TValue);
function stringEqual(const A, B: TValue): Boolean;

implementation

uses
  chunk;

const
  markerSize = sizeof(TMarker);

function OBJ_TYPE(const V: TValue): ObjType; inline;
begin
  Result := V.as_obj^.type_;
end;

function IS_STRING(const V: TValue): Boolean; inline;
begin
  Result := (V.type_ = VAL_OBJ) and (V.as_obj^.type_ = OBJ_STRING);
end;

function AS_STRING(const V: TValue): PObjString; inline;
begin
  Result := PObjString(V.as_obj);
end;

function AS_CSTRING(const V: TValue): PChar; inline;
begin
  Result := PObjString(V.as_obj)^.chars;
end;

procedure printObject(const V: TValue);
begin
  case OBJ_TYPE(V) of
    OBJ_NATIVE_FN,
    OBJ_CLOSURE,
    OBJ_FUNCTION: printFunction(AS_FUNCTION(V));
    OBJ_UPVALUE: print('upvalue');
    OBJ_STRING: printf('"%s"',[AS_CSTRING(V)]);
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
  objectsTop := nil;
  firstMarker := nil;
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

  markRoots();

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
  if IS_OBJ(V) then
    markObject(V.as_obj);
end;

procedure TObjectManager.markObject(const O: PLoxObj);
begin
  if O = nil then
    Exit;
  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
  begin
    printf('%p mark ', [O], true);
    printValue(OBJ_VAL(O));
    print(NL);
  end;
  {$endif}
  O^.isMarked := True;
end;

end.

