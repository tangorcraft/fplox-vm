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

  { TObjectManager }

  TObjectManager = class
  protected
    function allocateObject(const size: SizeInt; const type_: ObjType): Pointer;
    function allocateString(const start: PChar; const len: Integer; const hash: UInt32): PObjString;
    // moving to protected, should be only called from child class (string interning)
    function takeString(const chars: PChar; const len: Integer; const hash: UInt32): PObjString;
    function copyString(const start: PChar; const len: Integer; const hash: UInt32): PObjString;
  public
    objectsTop: PLoxObj;

    constructor Create;
    destructor Destroy; override;
  end;

{$inline on}

function OBJ_TYPE(const V: TValue): ObjType; inline;
function IS_STRING(const V: TValue): Boolean; inline;
function AS_STRING(const V: TValue): PObjString; inline;
function AS_CSTRING(const V: TValue): PChar; inline;

procedure printObject(const V: TValue);
function stringEqual(const A, B: TValue): Boolean;

implementation

uses
  chunk;

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

{$inline off}

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

procedure freeObject(const O: PLoxObj);
begin
  case O^.type_ of
    OBJ_CHUNK: begin
      PObjChunk(O)^.chunk.Free;
    end;
    OBJ_CLOSURE: begin
      with PObjClosure(O)^ do
        FREE_ARRAY(upvalues, upvalueCount, sizeof(PObjUpvalue));
    end;
    OBJ_STRING: begin
      with PObjString(O)^ do
        FREE_ARRAY(chars, length_ + 1, SizeOf(Char));
    end;
  end;
  FREE_(O, O^.size);
end;

{ TObjectManager }

function TObjectManager.allocateObject(const size: SizeInt; const type_: ObjType): Pointer;
begin
  Result := ALLOCATE(size);
  PLoxObj(Result)^.type_ := type_;
  PLoxObj(Result)^.size := size;
  PLoxObj(Result)^.next := objectsTop;
  objectsTop := Result;
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
end;

destructor TObjectManager.Destroy;
var
  next: PLoxObj;
begin
  while objectsTop <> nil do
  begin
    next := objectsTop^.next;
    freeObject(objectsTop);
    objectsTop := next;
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

end.

