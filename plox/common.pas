unit common;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

type
  TStringMethod = procedure (const S: string) of object;

var
  lox_output: TStringMethod;

procedure print(S: string);
procedure printf(const Fmt: string; vars: array of const);

implementation

var
  line: string;
const
  MAX_LINE = 120;

procedure internal_print(const S: string); inline;
begin
  if Assigned(lox_output) then
    lox_output(S);
end;

procedure print(S: string);
var
  i: Integer;
begin
  line := line + S;
  i := pos(#13, line);
  while i > 0 do
  begin
    s := copy(line, 1, i-1);
    internal_print(S);
    delete(line, 1, i);
    i := pos(#13, line);
  end;
  while length(line) > MAX_LINE do
  begin
    internal_print(copy(line, 1, MAX_LINE));
    delete(line, 1, MAX_LINE);
  end;
end;

procedure printf(const Fmt: string; vars: array of const);
begin
  print(Format(Fmt, vars));
end;

end.

