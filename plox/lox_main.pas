unit lox_main;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, vm, chunk, debug, common;

type

  { TLoxEngine }

  TLoxEngine = class
  private
    FChunk: TChunk;
    VM: TLoxVM;
  public
    constructor Create();
    destructor Destroy; override;

    function Execute(const source: string): Integer;
  end;

implementation

{ TLoxEngine }

constructor TLoxEngine.Create();
begin
  FChunk := TChunk.Create;
  VM := TLoxVM.Create;
end;

destructor TLoxEngine.Destroy;
begin
  FChunk.Free;
  VM.Free;
  inherited Destroy;
end;

function TLoxEngine.Execute(const source: string): Integer;
var
  constant: Integer;
begin
  constant := FChunk.addConstant(1.2);
  FChunk.write(OP_CONSTANT, 123);
  FChunk.write(constant, 123);

  constant := FChunk.addConstant(3.4);
  FChunk.write(OP_CONSTANT, 123);
  FChunk.write(constant, 123);

  FChunk.write(OP_ADD, 123);

  constant := FChunk.addConstant(5.6);
  FChunk.write(OP_CONSTANT, 123);
  FChunk.write(constant, 123);

  FChunk.write(OP_DIVIDE, 123);
  FChunk.write(OP_NEGATE, 123);
  FChunk.write(OP_RETURN, 123);

  disassembleChunk(FChunk, 'test chunk');
  vm.interpret(FChunk);
  Result := 0;
end;

end.

