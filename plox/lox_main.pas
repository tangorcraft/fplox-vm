unit lox_main;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, vm, chunk, debug, common;

type

  { TLoxEngine }

  TLoxEngine = class
  private
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
  VM := TLoxVM.Create;
end;

destructor TLoxEngine.Destroy;
begin
  VM.Free;
  inherited Destroy;
end;

function TLoxEngine.Execute(const source: string): Integer;
begin

  case vm.interpret(source) of
    INTERPRET_OK:
      Exit(0);
    INTERPRET_HALT:
      print('HALT: Code execution terminated.'+NL);
    INTERPRET_COMPILE_ERROR:
      Exit(65);
    INTERPRET_RUNTIME_ERROR:
      Exit(70);
  end;

  Result := 0;
end;

end.

