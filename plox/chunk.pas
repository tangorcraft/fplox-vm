unit chunk;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, hash_set, object_, value, memory;

type
  OpCode = (
    OP_HALT,
    OP_PRINT,
    OP_RETURN,
    OP_CONSTANT,
    OP_CONSTANT_LONG,
    OP_NIL,
    OP_TRUE,
    OP_FALSE,
    OP_POP,
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

implementation

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

end.

