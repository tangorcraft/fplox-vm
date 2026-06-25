unit compiler;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, scanner, common;

procedure compile(const source: string);

implementation

procedure compile(const source: string);
var
  scanner: TLoxScanner;
  line: Integer;
  token: TToken;
begin
  scanner := TLoxScanner.Create(source);
  line := -1;
  while true do
  begin
    token := scanner.scanToken();
    if line <> token.line then
    begin
      printf('%4d ',[token.line]);
      line := token.line;
    end
    else
      print('   | ');
    printf('%2d %.*s'+NL,[ord(token.type_), token.length, token.start]);
    if token.type_ = TOKEN_EOF then Break;
  end;
  scanner.Free;
end;

end.

