unit value;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, memory, common;

type
  ValueType = (
    VAL_BOOL,
    VAL_NIL,
    VAL_NUMBER,

    VAL_Invalid
  );

  TValue = record
    case type_: ValueType of
    VAL_BOOL: (as_bool: Boolean);
    VAL_NUMBER: (as_number: Double);
  end;
  PValue = ^TValue;

  { TValueArray }

  TValueArray = class(TMemArray)
  public
    values: PValue;

    constructor Create();

    procedure write(V: TValue);
  end;

procedure printValue(const V: TValue);
function isFalsey(const V: TValue): Boolean;
function valuesEqual(const A, B: TValue): Boolean;

function BOOL_VAL(const V: boolean): TValue;
function NUMBER_VAL(const V: double): TValue;
const NIL_VAL: TValue = (type_: VAL_NIL; as_number: 0.0;);
function IS_BOOL(const V: TValue): Boolean;
function IS_NUMBER(const V: TValue): Boolean;
function IS_NIL(const V: TValue): Boolean;

implementation

const
  b_to_s: array[Boolean] of string = ('false', 'true');

procedure printValue(const V: TValue);
begin
  case V.type_ of
    VAL_BOOL: print(b_to_s[V.as_bool]);
    VAL_NIL: print('nil');
    VAL_NUMBER: printf('%g',[V.as_number]);
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

function IS_BOOL(const V: TValue): Boolean;
begin
  Result := V.type_ = VAL_BOOL;
end;

function IS_NUMBER(const V: TValue): Boolean;
begin
  Result := V.type_ = VAL_NUMBER;
end;

function IS_NIL(const V: TValue): Boolean;
begin
  Result := V.type_ = VAL_NIL;
end;

{ TValueArray }

constructor TValueArray.Create();
begin
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

