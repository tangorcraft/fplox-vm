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

  TPrecedence = (
    PREC_NONE,
    PREC_ASSIGNMENT,  // =
    PREC_OR,          // or
    PREC_AND,         // and
    PREC_EQUALITY,    // == !=
    PREC_COMPARISON,  // < > <= >=
    PREC_TERM,        // + -
    PREC_FACTOR,      // * /
    PREC_UNARY,       // ! -
    PREC_CALL,        // . ()
    PREC_PRIMARY
  );

  TParseRule = record
    prefix: TProcedure;
    infix: TProcedure;
    precedence: TPrecedence;
  end;

function compile(const source: string; var C: TChunk): Boolean;
var
  scanner: TLoxScanner;
  parser: TParser;
  compilingChunk: TChunk;
  parseRules: array[TokenType] of TParseRule;

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

  procedure emitCode(const B: OpCode);
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
    emitCode(OP_RETURN);
  end;

  procedure emitConstant(const V: TValue);
  begin
    currentChunk().writeConstant(V, parser.previous.line);
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

  procedure parsePrecedense(const P: TPrecedence);
  begin

  end;

  procedure expression();
  begin
    parsePrecedense(PREC_ASSIGNMENT);
  end;

  procedure binary();
  var
    oper_type: TokenType;
  begin
    oper_type := parser.previous.type_;

    case oper_type of
      TOKEN_PLUS:  emitCode(OP_ADD);
      TOKEN_MINUS: emitCode(OP_SUBTRACT);
      TOKEN_STAR:  emitCode(OP_MULTIPLY);
      TOKEN_SLASH: emitCode(OP_DIVIDE);
    end;
  end;

  procedure unary();
  var
    oper_type: TokenType;
  begin
    oper_type := parser.previous.type_;

    parsePrecedense(PREC_UNARY);

    case oper_type of
      TOKEN_MINUS: emitCode(OP_NEGATE);
    end;
  end;

  procedure grouping();
  begin
    expression();
    consume(TOKEN_RIGHT_PAREN, 'Expect ")" after expression.');
  end;

  procedure init_rule(const token: TokenType; const prefix, infix: TProcedure; const precedence: TPrecedence);
  begin
    parseRules[token].prefix := prefix;
    parseRules[token].infix := infix;
    parseRules[token].precedence := precedence;
  end;

  procedure init_parseRules();
  begin
    init_rule(TOKEN_LEFT_PAREN   , @grouping, nil    , PREC_NONE);
    init_rule(TOKEN_RIGHT_PAREN  , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_LEFT_BRACE   , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_RIGHT_BRACE  , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_COMMA        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_DOT          , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_MINUS        , @unary   , @binary, PREC_TERM);
    init_rule(TOKEN_PLUS         , nil      , @binary, PREC_TERM);
    init_rule(TOKEN_SEMICOLON    , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_SLASH        , nil      , @binary, PREC_FACTOR);
    init_rule(TOKEN_STAR         , nil      , @binary, PREC_FACTOR);
    init_rule(TOKEN_BANG         , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_BANG_EQUAL   , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_EQUAL        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_EQUAL_EQUAL  , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_GREATER      , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_GREATER_EQUAL, nil      , nil    , PREC_NONE);
    init_rule(TOKEN_LESS         , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_LESS_EQUAL   , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_IDENTIFIER   , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_STRING       , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_NUMBER       , @number  , nil    , PREC_NONE);
    init_rule(TOKEN_AND          , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_CLASS        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_ELSE         , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_FALSE        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_FOR          , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_FUN          , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_IF           , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_NIL          , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_OR           , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_PRINT        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_RETURN       , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_SUPER        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_THIS         , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_TRUE         , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_VAR          , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_WHILE        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_ERROR        , nil      , nil    , PREC_NONE);
    init_rule(TOKEN_EOF          , nil      , nil    , PREC_NONE);
  end;

begin
  init_parseRules();
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

