unit chunk;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, memory, value;

const
  OP_HALT = 0;
  OP_RETURN = 1;
  OP_CONSTANT = 2;
  OP_NEGATE = 3;
  OP_ADD = 4;
  OP_SUBTRACT = 5;
  OP_MULTIPLY = 6;
  OP_DIVIDE = 7;
  OP_CONSTANT_LONG = 8;

type

  { TChunk }

  TChunk = class(TMemArray)
  public
    code: PByte;
    constants: TValueArray;
    lines: array of Integer;

    constructor Create();
    destructor Destroy; override;

    function addConstant(const V: TValue): Integer;

    procedure write(const B: Byte; const line: Integer);
    procedure write24(const I: Integer; const line: Integer);
    procedure writeConstant(const V: TValue; const line: Integer);
  end;

implementation

{ TChunk }

constructor TChunk.Create();
begin
  Init(SizeOf(Byte));
  code := Grow;
  SetLength(lines, capacity);
  constants := TValueArray.Create();
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

