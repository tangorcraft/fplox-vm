unit common;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  TStringMethod = procedure (const S: string) of object;

var
  lox_output: TStringMethod;
  lox_error: TStringMethod;

const
  NL = #13; // new line
  NaN = Math.NaN;

procedure print(S: string; const err: Boolean = false);
procedure printf(const Fmt: string; vars: array of const; const err: Boolean = false);

function memcmp(const p1, p2: Pointer; const count: SizeInt): boolean;
procedure memcpy(const dest, source: Pointer; const count: SizeInt);
function strtod(const S: string): Double;

implementation

type
  TOutputProc = procedure(const S: string);
  TOutput = record
    line: string;
    proc: TOutputProc;
  end;
  POutput = ^TOutput;

var
  std: TOutput;
  stderr: TOutput;
const
  MAX_LINE = 120;

procedure internal_print(const S: string);
begin
  if Assigned(lox_output) then
    lox_output(S);
end;

procedure internal_print_err(const S: string);
begin
  if Assigned(lox_error) then
    lox_error(S);
end;

procedure print(S: string; const err: Boolean);
var
  i: Integer;
  output: POutput;
begin
  if err then output := @stderr else output := @std;
with output^ do
begin
  line := line + S;
  i := pos(NL, line);
  while i > 0 do
  begin
    s := copy(line, 1, i-1);
    proc(S);
    delete(line, 1, i);
    i := pos(NL, line);
  end;
  while length(line) > MAX_LINE do
  begin
    proc(copy(line, 1, MAX_LINE));
    delete(line, 1, MAX_LINE);
  end;
end;

end;

procedure printf(const Fmt: string; vars: array of const; const err: Boolean);
begin
  print(Format(Fmt, vars), err);
end;

function memcmp(const p1, p2: Pointer; const count: SizeInt): boolean;
begin
  Result := CompareByte(p1^, p2^, count) = 0;
end;

procedure memcpy(const dest, source: Pointer; const count: SizeInt);
begin
  Move(source^, dest^, count);
end;

function strtod(const S: string): Double;
var
  E: Integer;
begin
  try
    Val(S,Result,E);
  { on x87, a floating point exception may be pending in case of an invalid
    input value -> trigger it now }
  {$if defined(cpui386) or (defined(cpux86_64) and not(defined(win64))) or defined(cpui8086)}
    asm
      fwait
    end;
  {$endif}
  except
    E:=1;
  end;
  if (E<>0) then
    Result := NaN;
end;

initialization
  std.proc := @internal_print;
  stderr.proc := @internal_print_err;
end.

