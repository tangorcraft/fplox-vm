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

  TParseProc = procedure(const canAssign: Boolean) of object;
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
    function check(const type_: TokenType): Boolean;
    function match(const type_: TokenType): Boolean;
    function makeConstant(const V: TValue): Integer;
    procedure emitByte(const B: Byte);
    procedure emitLong(const B: Integer);
    procedure emitCode(const B: OpCode);
    procedure emitCodes(const B1, B2: OpCode);
    procedure emitCodeByte(const B1: OpCode; const B2: Byte);
    procedure emitCodeLong(const B1: OpCode; const B2: Integer);
    procedure emitCodeVar(const B_short, B_long: OpCode; const B2: Integer);
    procedure emitReturn();
    procedure emitConstant(const V: TValue);
    procedure endCompiler();
    procedure parsePrecedense(const P: TPrecedence);
    function identifierConstant(const name: TToken): Integer;
    function parseVariable(const msg: PChar): Integer;
    procedure defineVariable(const global: Integer);
    procedure expression();
    procedure expressionStatement();
    procedure printStatement();
    procedure statement();
    procedure varDeclaration();
    procedure declaration();
    procedure synchronize();
    procedure namedVariable(const name: TToken; const canAssign: Boolean);

    procedure number(const canAssign: Boolean);
    procedure literal(const canAssign: Boolean);
    procedure string_(const canAssign: Boolean);
    procedure variable(const canAssign: Boolean);
    procedure unary(const canAssign: Boolean);
    procedure binary(const canAssign: Boolean);
    procedure grouping(const canAssign: Boolean);

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
  init_rule(TOKEN_IDENTIFIER   , @variable, nil    , PREC_NONE);
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

function TCompiler.check(const type_: TokenType): Boolean;
begin
  Result := parser.current.type_ = type_;
end;

function TCompiler.match(const type_: TokenType): Boolean;
begin
  if not check(type_) then
    Exit(false);
  advance();
  Result := True;
end;

function TCompiler.makeConstant(const V: TValue): Integer;
begin
  Result := currentChunk().addConstant(V);
end;

procedure TCompiler.emitByte(const B: Byte);
begin
  currentChunk().write(B, parser.previous.line);
end;

procedure TCompiler.emitLong(const B: Integer);
begin
  currentChunk().write24(B, parser.previous.line);
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

procedure TCompiler.emitCodeByte(const B1: OpCode; const B2: Byte);
begin
  emitByte(ord(B1));
  emitByte(B2);
end;

procedure TCompiler.emitCodeLong(const B1: OpCode; const B2: Integer);
begin
  emitByte(ord(B1));
  emitLong(B2);
end;

procedure TCompiler.emitCodeVar(const B_short, B_long: OpCode; const B2: Integer);
begin
  if B2 > $ff then
    emitCodeLong(B_long, B2)
  else
    emitCodeByte(B_short, Byte(B2));
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
  canAssign: Boolean;
begin
  advance();
  ruleProc := parseRules[parser.previous.type_].prefix;
  if not Assigned(ruleProc) then
  begin
    error('Expect expression');
    Exit;
  end;

  canAssign := P <= PREC_ASSIGNMENT;
  ruleProc(canAssign);

  while (P <= parseRules[parser.current.type_].precedence) do
  begin
    advance();
    ruleProc := parseRules[parser.previous.type_].infix;
    if not Assigned(ruleProc) then
    begin
      error('Operation not allowed');
      Exit;
    end;
    ruleProc(canAssign);
  end;

  if canAssign and match(TOKEN_EQUAL) then
    error('Invalid assignment target.');
end;

function TCompiler.identifierConstant(const name: TToken): Integer;
begin
  Result := makeConstant(OBJ_VAL(currentChunk().objs.copyString(name.start, name.length)));
end;

function TCompiler.parseVariable(const msg: PChar): Integer;
begin
  consume(TOKEN_IDENTIFIER, msg);
  Result := identifierConstant(parser.previous);
end;

procedure TCompiler.defineVariable(const global: Integer);
begin
  emitCodeVar(OP_DEFINE_GLOBAL, OP_DEFINE_GLOBAL_LONG, global);
end;

procedure TCompiler.expression();
begin
  parsePrecedense(PREC_ASSIGNMENT);
end;

procedure TCompiler.expressionStatement();
begin
  expression();
  consume(TOKEN_SEMICOLON, 'Expect ";" after expression.');
  emitCode(OP_POP);
end;

procedure TCompiler.printStatement();
begin
  expression();
  consume(TOKEN_SEMICOLON, 'Expect ";" after value.');
  emitCode(OP_PRINT);
end;

procedure TCompiler.statement();
begin
  if match(TOKEN_PRINT) then
    printStatement()
  else
    expressionStatement();
end;

procedure TCompiler.varDeclaration();
var
  global: Integer;
begin
  global := parseVariable('Expect variable name.');

  if match(TOKEN_EQUAL) then
    expression()
  else
    emitCode(OP_NIL);
  consume(TOKEN_SEMICOLON, 'Expect ";" after variable declaration.');

  defineVariable(global);
end;

procedure TCompiler.declaration();
begin
  if match(TOKEN_VAR) then
    varDeclaration()
  else
    statement();

  if parser.panicMode then
    synchronize();
end;

procedure TCompiler.synchronize();
begin
  parser.panicMode := False;

  while parser.current.type_ <> TOKEN_EOF do
  begin
    if parser.previous.type_ = TOKEN_SEMICOLON then
      Exit;
    case parser.current.type_ of
      TOKEN_CLASS,
      TOKEN_FUN,
      TOKEN_VAR,
      TOKEN_FOR,
      TOKEN_IF,
      TOKEN_WHILE,
      TOKEN_PRINT,
      TOKEN_RETURN:
        Exit;
    end;
    advance();
  end;
end;

procedure TCompiler.number(const canAssign: Boolean);
var
  value: double;
begin
  value := strtod(copy(parser.previous.start, 1, parser.previous.length));
  emitConstant(NUMBER_VAL(value));
end;

procedure TCompiler.literal(const canAssign: Boolean);
begin
  case parser.previous.type_ of
    TOKEN_FALSE: emitCode(OP_FALSE);
    TOKEN_NIL: emitCode(OP_NIL);
    TOKEN_TRUE: emitCode(OP_TRUE);
  end;
end;

procedure TCompiler.string_(const canAssign: Boolean);
begin
  emitConstant(OBJ_VAL(currentChunk().objs.copyString(parser.previous.start + 1, parser.previous.length - 2)));
end;

procedure TCompiler.namedVariable(const name: TToken; const canAssign: Boolean);
var
  arg: Integer;
begin
  arg := identifierConstant(name);

  if canAssign and match(TOKEN_EQUAL) then
  begin
    expression();
    emitCodeVar(OP_SET_GLOBAL, OP_SET_GLOBAL_LONG, arg);
  end
  else
    emitCodeVar(OP_GET_GLOBAL, OP_GET_GLOBAL_LONG, arg);
end;

procedure TCompiler.variable(const canAssign: Boolean);
begin
  namedVariable(parser.previous, canAssign);
end;

procedure TCompiler.unary(const canAssign: Boolean);
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

procedure TCompiler.binary(const canAssign: Boolean);
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

procedure TCompiler.grouping(const canAssign: Boolean);
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
    while not match(TOKEN_EOF) do
      declaration();
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

