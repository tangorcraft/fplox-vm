unit compiler;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, scanner, debug, chunk, value, memory, common;

function compile(const source: string; var C: TChunk): Boolean;

implementation

type
  TParser = record
    current: TToken;
    previous: TToken;
    hadError: Boolean;
    panicMode: Boolean;
  end;

function compile(const source: string; var C: TChunk): Boolean;
var
  scanner: TLoxScanner;
  parser: TParser;
  compilingChunk: TChunk;

  function currentChunk: TChunk;
  begin
    Result := compilingChunk;
  end;

  procedure errorAt(const T: TToken; const msg: PChar);
  begin
    if parser.panicMode then Exit;
    parser.panicMode := true;
    printf('[line %d] Error', [T.line], true);

    if T.type_ = TOKEN_EOF then
      print(' at end', true)
    else if T.type_ = TOKEN_ERROR then
      begin end // nothing ?
    else
      printf(' at "%.*s"', [T.length, T.start], true);

    printf(': %s'+NL, [msg], true);
    parser.hadError := true;
  end;

  procedure error(const msg: PChar);
  begin
    errorAt(parser.previous, msg);
  end;

  procedure errorAtCurrent(const msg: PChar);
  begin
    errorAt(parser.current, msg);
  end;

  procedure advance();
  begin
    parser.previous := parser.current;
    while true do
    begin
      parser.current := scanner.scanToken();
      if parser.current.type_ <> TOKEN_ERROR then
        Break;
      errorAtCurrent(parser.current.start);
    end;
  end;

  procedure consume(const type_: TokenType; const msg: PChar);
  begin
    if parser.current.type_ = type_ then
    begin
      advance();
      Exit;
    end;

    errorAtCurrent(msg);
  end;

  procedure emitByte(const B: Byte);
  begin
    currentChunk().write(B, parser.previous.line);
  end;

  procedure emitBytes(const B1, B2: Byte);
  begin
    emitByte(B1);
    emitByte(B2);
  end;

  procedure emitReturn();
  begin
    emitByte(OP_RETURN);
  end;

  procedure emitConstant(const V: TValue);
  begin
    emitByte(OP_CONSTANT);
    currentChunk().writeConstant(value, parser.previous.line);
  end;

  procedure endCompiler();
  begin
    emitReturn();
  end;

  procedure number();
  var
    value: double;
  begin
    value := strtod(copy(parser.previous.start, 1, parser.previous.length));
    emitConstant(value);
  end;

  procedure expression();
  begin

  end;

begin
  parser.hadError := false;
  parser.panicMode := false;

  compilingChunk := C;
  scanner := TLoxScanner.Create(source);
  try
    advance();
    expression();
    consume(TOKEN_EOF, 'Expect end of expression.');
  finally
    scanner.Free;
  end;
  endCompiler();
  Result := not parser.hadError;
end;

end.

