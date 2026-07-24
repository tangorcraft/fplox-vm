unit value;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, memory, common;

type
  {$ifndef NAN_BOXING}
  ValueType = (
    VAL_NIL = 0, // this way we can simply zero memory on hash table
    VAL_BOOL,
    VAL_NUMBER,
    VAL_OBJ,

    VAL_Invalid
  );
  {$endif}

  ObjType = (
    OBJ_ERROR_MESSAGE, // native functions can return this to indicate runtime error
    OBJ_CLASS,
    OBJ_INSTANCE,
    OBJ_BOUND_METHOD,
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

  TErrorMsg = record
    obj: TLoxObj;
    message: string;
  end;
  PErrorMsg = ^TErrorMsg;

  TValue =
  {$ifdef NAN_BOXING}
    UInt64;
  {$else} record
    case type_: ValueType of
    VAL_BOOL: (as_bool_: Boolean);
    VAL_NUMBER: (as_number_: Double);
    VAL_OBJ: (as_obj_: PLoxObj);
  end;
  {$endif}
  PValue = ^TValue;

  { TValueArray }

  TValueArray = class(TMemArray)
  public
    values: PValue;

    constructor Create(const mgr: TMemoryManager);

    procedure write(const V: TValue);
    function find(const V: TValue): Integer;
  end;

procedure printValue(const V: TValue; const err: Boolean = false);
function isFalsey(const V: TValue): Boolean;
function valuesEqual(const A, B: TValue): Boolean;

function BOOL_VAL(const V: boolean): TValue;
function NUMBER_VAL(const V: double): TValue;
function OBJ_VAL(const V: Pointer): TValue;

function ERROR_MSG_VAL(const msg: string): TValue;
function ERROR_MSG_VAL(const fmt: string; args: array of const): TValue;
function ERROR_MSG_GET(var V: TValue): string;

const
  {$ifdef NAN_BOXING}
  SIGN_BIT  = UInt64($8000000000000000);
  QNAN      = UInt64($7ffc000000000000);
  QNAN_SIGN = QNAN or SIGN_BIT;
  QNAN_SIGN_INVERSE = not QNAN_SIGN;
  TAG_NIL = 1;
  TAG_FALSE = 2;
  TAG_TRUE = 3;

  NIL_VAL_INT = QNAN or TAG_NIL;
  TRUE_VAL_INT = QNAN or TAG_TRUE;
  FALSE_VAL_INT = QNAN or TAG_FALSE;

  NIL_VAL: TValue = NIL_VAL_INT;
  TRUE_VAL: TValue = TRUE_VAL_INT;
  FALSE_VAL: TValue = FALSE_VAL_INT;
  {$else}
  NIL_VAL: TValue = (type_: VAL_NIL; as_number_: 0.0;);
  TRUE_VAL: TValue = (type_: VAL_BOOL; as_bool_: true;);
  FALSE_VAL: TValue = (type_: VAL_BOOL; as_bool_: false;);
  {$endif}

function AS_OBJ(const A: TValue): PLoxObj; inline;
function AS_NUMBER(const A: TValue): Double; inline;
function AS_BOOL(const A: TValue): Boolean; inline;

implementation

uses
  object_;

function AS_OBJ(const A: TValue): PLoxObj;
begin
  {$ifdef NAN_BOXING}
  Result := PLoxObj(PtrUInt( A and QNAN_SIGN_INVERSE ));
  {$else}
  Result := A.as_obj_;
  {$endif}
end;

function AS_NUMBER(const A: TValue): Double;
var
  d: double absolute A;
begin
  {$ifdef NAN_BOXING}
  //Move(A.data, R, SizeOf(double));
  Result := d;
  {$else}
  Result := A.as_number_;
  {$endif}
end;

function AS_BOOL(const A: TValue): Boolean;
begin
  {$ifdef NAN_BOXING}
  Result := A = TRUE_VAL_INT;
  {$else}
  Result := A.as_bool_;
  {$endif}
end;

const
  b_to_s: array[Boolean] of string = ('false', 'true');

procedure printValue(const V: TValue; const err: Boolean);
begin
  {$ifdef NAN_BOXING}
  if V IS_BOOL_VAL then
    print(b_to_s[AS_BOOL(V)], err)
  else if V IS_NIL_VAL then
    print('nil', err)
  else if V IS_NUMBER_VAL then
    printf('%g',[AS_NUMBER(V)], err)
  else if V IS_OBJ_VAL then
    printObject(V, err);
  {$else}
  case V.type_ of
    VAL_BOOL: print(b_to_s[V.as_bool_], err);
    VAL_NIL: print('nil', err);
    VAL_NUMBER: printf('%g',[V.as_number_], err);
    VAL_OBJ: printObject(V, err);
  end;
  {$endif}
end;

function isFalsey(const V: TValue): Boolean;
begin
  Result := (V IS_NIL_VAL) or ((V IS_BOOL_VAL) and (not AS_BOOL(V)));
end;

function valuesEqual(const A, B: TValue): Boolean;
begin
  {$ifdef NAN_BOXING}
  if (A IS_NUMBER_VAL) and (B IS_NUMBER_VAL) then
    Result := AS_NUMBER(A) = AS_NUMBER(B)
  else
    Result := A = B;
  {$else}
  if a.type_ <> b.type_ then
    Exit(false);
  case a.type_ of
    VAL_BOOL: Exit(a.as_bool_ = b.as_bool_);
    VAL_NIL: Exit(True);
    VAL_NUMBER: Exit(a.as_number_ = b.as_number_);
    VAL_OBJ: Exit(AS_OBJ(A) = AS_OBJ(B));
  end;
  Result := false;
  {$endif}
end;

function BOOL_VAL(const V: boolean): TValue;
begin
  {$ifdef NAN_BOXING}
  if V then Result:=TRUE_VAL else Result:=FALSE_VAL;
  {$else}
  Result.type_ := VAL_BOOL;
  Result.as_bool_ := V;
  {$endif}
end;

function NUMBER_VAL(const V: double): TValue;
var
  i: UInt64 absolute V;
begin
  {$ifdef NAN_BOXING}
  //Move(V, R.data, SizeOf(double));
  Result := i;
  {$else}
  Result.type_ := VAL_NUMBER;
  Result.as_number_ := V;
  {$endif}
end;

function OBJ_VAL(const V: Pointer): TValue;
begin
  {$ifdef NAN_BOXING}
  Result := QNAN_SIGN or UInt64(PtrUInt(V));
  {$else}
  Result.type_ := VAL_OBJ;
  Result.as_obj_ := V;
  {$endif}
end;

function ERROR_MSG_VAL(const msg: string): TValue;
var
  pmsg: PErrorMsg;
begin
  New(pmsg);
  pmsg^.obj.type_ := OBJ_ERROR_MESSAGE;
  pmsg^.message := msg;
  Result := OBJ_VAL(PLoxObj(pmsg));
end;

function ERROR_MSG_VAL(const fmt: string; args: array of const): TValue;
begin
  Result := ERROR_MSG_VAL(format(fmt, args));
end;

function ERROR_MSG_GET(var V: TValue): string;
var
  pmsg: PErrorMsg;
begin
  if not ((V IS_OBJ_VAL) and (AS_OBJ(V)^.type_ = OBJ_ERROR_MESSAGE)) then
    Exit('<value is not an error message>');
  pmsg := PErrorMsg(AS_OBJ(V));
  Result := pmsg^.message;
  pmsg^.message := '';
  Dispose(pmsg);
  V := NIL_VAL;
end;

{ TValueArray }

constructor TValueArray.Create(const mgr: TMemoryManager);
begin
  inherited Create(mgr);
  Init(SizeOf(TValue));
  values := Grow;
end;

procedure TValueArray.write(const V: TValue);
begin
  if capacity < (count + 1) then
    values := Grow;
  values[count] := V;
  inc(count);
end;

function TValueArray.find(const V: TValue): Integer;
var
  i: Integer;
begin
  for i := 0 to count - 1 do
    if valuesEqual(values[i], V) then
      Exit(i);
  Result := -1;
end;

end.

