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

type

  { TChunk }

  TChunk = class(TMemArray)
  public
    code: PByte;
    constants: TValueArray;
    lines: array of Integer;

    constructor Create();
    destructor Destroy; override;

    procedure write(const B: Byte; const line: Integer);
    function addConstant(const V: TValue): Integer;
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

function TChunk.addConstant(const V: TValue): Integer;
begin
  constants.write(V);
  Result := constants.count - 1;
end;

end.

