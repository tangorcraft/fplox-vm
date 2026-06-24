unit lox_main;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, chunk, debug, common;

type

  { TLoxEngine }

  TLoxEngine = class
  private
    FChunk: TChunk;
  public
    constructor Create();
    destructor Destroy; override;

    function Execute(const args: array of const): Integer;
  end;

implementation

{ TLoxEngine }

constructor TLoxEngine.Create();
begin
  FChunk := TChunk.Create;
end;

destructor TLoxEngine.Destroy;
begin
  FChunk.Free;
  inherited Destroy;
end;

function TLoxEngine.Execute(const args: array of const): Integer;
var
  constant: Integer;
begin
  constant := FChunk.addConstant(1.2);
  FChunk.write(OP_CONSTANT, 123);
  FChunk.write(constant, 123);
  FChunk.write(OP_RETURN, 123);

  disassembleChunk(FChunk, 'test chunk');
  Result := 0;
end;

end.

