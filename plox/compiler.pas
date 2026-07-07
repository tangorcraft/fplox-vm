unit compiler;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, scanner,
  {$ifdef DEBUG_PRINT_CODE}debug,{$endif}
  chunk, object_, value, memory, common;

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

  TParseProc = procedure of object;
  TParseRule = record
    prefix: TParseProc;
    infix: TParseProc;
    precedence: TPrecedence;
  end;
  PParseRule = ^TParseRule;

  { TCompiler }

  TCompiler = class
    scanner: TLoxScanner;
    parser: TParser;
    compilingChunk: TChunk;
    parseRules: array[TokenType] of TParseRule;

    constructor Create;

    function currentChunk: TChunk;
    procedure errorAt(const T: TToken; const msg: PChar);
    procedure error(const msg: PChar);
    procedure errorAtCurrent(const msg: PChar);
    procedure advance();
    procedure consume(const type_: TokenType; const msg: PChar);
    procedure emitByte(const B: Byte);
    procedure emitCode(const B: OpCode);
    procedure emitCodes(const B1, B2: OpCode);
    procedure emitReturn();
    procedure emitConstant(const V: TValue);
    procedure endCompiler();
    procedure parsePrecedense(const P: TPrecedence);
    procedure expression();
    procedure number();
    procedure literal();
    procedure string_();
    procedure unary();
    procedure binary();
    procedure grouping();
    function compile_(const source: string; var C: TChunk): Boolean;
  end;

function compile(const source: string; var C: TChunk): Boolean;
begin
  with TCompiler.Create do
  try
    Result := compile_(source, C);
  finally
    Free;
  end;
end;

{ TCompiler }

constructor TCompiler.Create;

  procedure init_rule(const token: TokenType; const prefix, infix: TParseProc; const precedence: TPrecedence);
  begin
    parseRules[token].prefix := prefix;
    parseRules[token].infix := infix;
    parseRules[token].precedence := precedence;
  end;

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
  init_rule(TOKEN_BANG         , @unary   , nil    , PREC_NONE);
  init_rule(TOKEN_BANG_EQUAL   , nil      , @binary, PREC_EQUALITY);
  init_rule(TOKEN_EQUAL        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_EQUAL_EQUAL  , nil      , @binary, PREC_EQUALITY);
  init_rule(TOKEN_GREATER      , nil      , @binary, PREC_COMPARISON);
  init_rule(TOKEN_GREATER_EQUAL, nil      , @binary, PREC_COMPARISON);
  init_rule(TOKEN_LESS         , nil      , @binary, PREC_COMPARISON);
  init_rule(TOKEN_LESS_EQUAL   , nil      , @binary, PREC_COMPARISON);
  init_rule(TOKEN_IDENTIFIER   , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_STRING       , @string_ , nil    , PREC_NONE);
  init_rule(TOKEN_NUMBER       , @number  , nil    , PREC_NONE);
  init_rule(TOKEN_AND          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_CLASS        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_ELSE         , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_FALSE        , @literal , nil    , PREC_NONE);
  init_rule(TOKEN_FOR          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_FUN          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_IF           , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_NIL          , @literal , nil    , PREC_NONE);
  init_rule(TOKEN_OR           , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_PRINT        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_RETURN       , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_SUPER        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_THIS         , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_TRUE         , @literal , nil    , PREC_NONE);
  init_rule(TOKEN_VAR          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_WHILE        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_ERROR        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_EOF          , nil      , nil    , PREC_NONE);
end;

function TCompiler.currentChunk: TChunk;
begin
  Result := compilingChunk;
end;

procedure TCompiler.errorAt(const T: TToken; const msg: PChar);
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

procedure TCompiler.error(const msg: PChar);
begin
  errorAt(parser.previous, msg);
end;

procedure TCompiler.errorAtCurrent(const msg: PChar);
begin
  errorAt(parser.current, msg);
end;

procedure TCompiler.advance();
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

procedure TCompiler.consume(const type_: TokenType; const msg: PChar);
begin
  if parser.current.type_ = type_ then
  begin
    advance();
    Exit;
  end;

  errorAtCurrent(msg);
end;

procedure TCompiler.emitByte(const B: Byte);
begin
  currentChunk().write(B, parser.previous.line);
end;

procedure TCompiler.emitCode(const B: OpCode);
begin
  currentChunk().write(B, parser.previous.line);
end;

procedure TCompiler.emitCodes(const B1, B2: OpCode);
begin
  emitByte(ord(B1));
  emitByte(ord(B2));
end;

procedure TCompiler.emitReturn();
begin
  emitCode(OP_RETURN);
end;

procedure TCompiler.emitConstant(const V: TValue);
begin
  currentChunk().writeConstant(V, parser.previous.line);
end;

procedure TCompiler.endCompiler();
begin
  emitReturn();
end;

procedure TCompiler.parsePrecedense(const P: TPrecedence);
var
  ruleProc: TParseProc;
begin
  advance();
  ruleProc := parseRules[parser.previous.type_].prefix;
  if not Assigned(ruleProc) then
  begin
    error('Expect expression');
    Exit;
  end;

  ruleProc();

  while (P <= parseRules[parser.current.type_].precedence) do
  begin
    advance();
    ruleProc := parseRules[parser.previous.type_].infix;
    if not Assigned(ruleProc) then
    begin
      error('Operation not allowed');
      Exit;
    end;
    ruleProc();
  end;
end;

procedure TCompiler.expression();
begin
  parsePrecedense(PREC_ASSIGNMENT);
end;

procedure TCompiler.number();
var
  value: double;
begin
  value := strtod(copy(parser.previous.start, 1, parser.previous.length));
  emitConstant(NUMBER_VAL(value));
end;

procedure TCompiler.literal();
begin
  case parser.previous.type_ of
    TOKEN_FALSE: emitCode(OP_FALSE);
    TOKEN_NIL: emitCode(OP_NIL);
    TOKEN_TRUE: emitCode(OP_TRUE);
  end;
end;

procedure TCompiler.string_();
begin
  emitConstant(OBJ_VAL(currentChunk().objs.copyString(parser.previous.start + 1, parser.previous.length - 2)));
end;

procedure TCompiler.unary();
var
  oper_type: TokenType;
begin
  oper_type := parser.previous.type_;

  parsePrecedense(PREC_UNARY);

  case oper_type of
    TOKEN_BANG: emitCode(OP_NOT);
    TOKEN_MINUS: emitCode(OP_NEGATE);
  end;
end;

procedure TCompiler.binary();
var
  oper_type: TokenType;
begin
  oper_type := parser.previous.type_;
  parsePrecedense(Succ(parseRules[oper_type].precedence));

  case oper_type of
    TOKEN_BANG_EQUAL:    emitCodes(OP_EQUAL, OP_NOT);
    TOKEN_EQUAL_EQUAL:   emitCode(OP_EQUAL);
    TOKEN_GREATER:       emitCode(OP_GREATER);
    TOKEN_GREATER_EQUAL: emitCodes(OP_LESS, OP_NOT);
    TOKEN_LESS:          emitCode(OP_LESS);
    TOKEN_LESS_EQUAL:    emitCodes(OP_GREATER, OP_NOT);
    TOKEN_PLUS:  emitCode(OP_ADD);
    TOKEN_MINUS: emitCode(OP_SUBTRACT);
    TOKEN_STAR:  emitCode(OP_MULTIPLY);
    TOKEN_SLASH: emitCode(OP_DIVIDE);
  end;
end;

procedure TCompiler.grouping();
begin
  expression();
  consume(TOKEN_RIGHT_PAREN, 'Expect ")" after expression.');
end;

function TCompiler.compile_(const source: string; var C: TChunk): Boolean;
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
  {$ifdef DEBUG_PRINT_CODE}
  if Result then
    disassembleChunk(currentChunk(), 'code');
  {$endif}
end;

end.

