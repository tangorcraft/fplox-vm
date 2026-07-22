unit value;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, memory, common;

type
  ValueType = (
    VAL_NIL = 0, // this way we can simply zero memory on hash table
    VAL_BOOL,
    VAL_NUMBER,
    VAL_OBJ,

    VAL_Invalid
  );

  ObjType = (
    OBJ_CLASS,
    OBJ_NATIVE_FN,
    OBJ_CLOSURE,
    OBJ_FUNCTION,
    OBJ_UPVALUE,
    OBJ_STRING
  );

  PLoxObj = ^TLoxObj;
  TLoxObj = record
    type_: ObjType;
    isMarked: boolean;
    size: SizeInt;
    next: PLoxObj;
  end;

  TValue = record
    case type_: ValueType of
    VAL_BOOL: (as_bool: Boolean);
    VAL_NUMBER: (as_number: Double);
    VAL_OBJ: (as_obj: PLoxObj);
  end;
  PValue = ^TValue;

  { TValueArray }

  TValueArray = class(TMemArray)
  public
    values: PValue;

    constructor Create(const mgr: TMemoryManager);

    procedure write(V: TValue);
  end;

procedure printValue(const V: TValue; const err: Boolean = false);
function isFalsey(const V: TValue): Boolean;
function valuesEqual(const A, B: TValue): Boolean;

function BOOL_VAL(const V: boolean): TValue;
function NUMBER_VAL(const V: double): TValue;
function OBJ_VAL(const V: Pointer): TValue;
const
  NIL_VAL: TValue = (type_: VAL_NIL; as_number: 0.0;);
  TRUE_VAL: TValue = (type_: VAL_BOOL; as_bool: true;);
  FALSE_VAL: TValue = (type_: VAL_BOOL; as_bool: false;);

{$inline on}

function IS_BOOL(const V: TValue): Boolean; inline;
function IS_NUMBER(const V: TValue): Boolean; inline;
function IS_NIL(const V: TValue): Boolean; inline;
function IS_OBJ(const V: TValue): Boolean; inline;

implementation

uses
  object_;

const
  b_to_s: array[Boolean] of string = ('false', 'true');

procedure printValue(const V: TValue; const err: Boolean);
begin
  case V.type_ of
    VAL_BOOL: print(b_to_s[V.as_bool], err);
    VAL_NIL: print('nil', err);
    VAL_NUMBER: printf('%g',[V.as_number], err);
    VAL_OBJ: printObject(V, err);
  end;
end;

function isFalsey(const V: TValue): Boolean;
begin
  Result := IS_NIL(V) or (IS_BOOL(V) and (not V.as_bool))
end;

function valuesEqual(const A, B: TValue): Boolean;
begin
  if a.type_ <> b.type_ then
    Exit(false);
  case a.type_ of
    VAL_BOOL: Exit(a.as_bool = b.as_bool);
    VAL_NIL: Exit(True);
    VAL_NUMBER: Exit(a.as_number = b.as_number);
    VAL_OBJ: Exit(A.as_obj = B.as_obj);
  end;
  Result := false;
end;


function BOOL_VAL(const V: boolean): TValue;
begin
  Result.type_ := VAL_BOOL;
  Result.as_bool := V;
end;

function NUMBER_VAL(const V: double): TValue;
begin
  Result.type_ := VAL_NUMBER;
  Result.as_number := V;
end;

function OBJ_VAL(const V: Pointer): TValue;
begin
  Result.type_ := VAL_OBJ;
  Result.as_obj := V;
end;

function IS_BOOL(const V: TValue): Boolean; inline;
begin
  Result := V.type_ = VAL_BOOL;
end;

function IS_NUMBER(const V: TValue): Boolean; inline;
begin
  Result := V.type_ = VAL_NUMBER;
end;

function IS_NIL(const V: TValue): Boolean; inline;
begin
  Result := V.type_ = VAL_NIL;
end;

function IS_OBJ(const V: TValue): Boolean; inline;
begin
  Result := V.type_ = VAL_OBJ;
end;

{$inline off}

{ TValueArray }

constructor TValueArray.Create(const mgr: TMemoryManager);
begin
  inherited Create(mgr);
  Init(SizeOf(TValue));
  values := Grow;
end;

procedure TValueArray.write(V: TValue);
begin
  if capacity < (count + 1) then
    values := Grow;
  values[count] := V;
  inc(count);
end;

end.

