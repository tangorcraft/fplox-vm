unit compiler;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, scanner,
  {$ifdef DEBUG_PRINT_CODE}debug,{$endif}
  chunk, object_, value, memory, common;

function compile(const source: string; const mgr: TObjectManager_Fun): PObjFunction;

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

  TLocal = record
    name: TToken;
    depth: Integer;
    isCaptured: Boolean;
  end;
  PLocal = ^TLocal;

  TFunctionType = (
    TYPE_FUNCTION,
    TYPE_INITIALIZER,
    TYPE_METHOD,
    TYPE_SCRIPT
  );

  TUpValue = record
    index: Byte;
    isLocal: Boolean;
  end;
  PUpValue = ^TUpValue;

  PCompilerState = ^TCompilerState;
  TCompilerState = record
    enclosing: PCompilerState;
    func: PObjFunction;
    funType: TFunctionType;

    locals: array[Byte] of TLocal;
    localCount: Integer;
    upvalues: array[Byte] of TUpValue;
    scopeDepth: Integer;
  end;

  PClassCompiler = ^TClassCompiler;
  TClassCompiler = record
    enclosing: PClassCompiler;
  end;

  { TCompiler }

  TCompiler = class
    scanner: TLoxScanner;
    parser: TParser;
    parseRules: array[TokenType] of TParseRule;
    current: PCompilerState;
    currentClass: PClassCompiler;
    MM: TObjectManager_Fun;

    constructor Create(const mgr: TObjectManager_Fun);
    destructor Destroy; override;

    procedure markCompilerRoots();

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
    procedure emitIndex(const Idx: Integer; const B: OpCode);
    procedure emitReturn();
    procedure emitConstant(const V: TValue);
    function emitJump(const B: OpCode): Integer;
    procedure patchJump(const offset: Integer);
    procedure emitLoop(const loopStart: integer);

    procedure initCompiler(const state: PCompilerState; const type_: TFunctionType);
    function endCompiler(): PObjFunction;
    procedure parsePrecedense(const P: TPrecedence);
    function identifierConstant(const name: TToken): Integer;
    procedure addLocal(const name: TToken);
    procedure markInitialized();
    procedure declareVariable();
    function parseVariable(const msg: PChar): Integer;
    procedure defineVariable(const global: Integer);
    function resolveLocal(const compiler: PCompilerState; const name: TToken): integer;
    function addUpvalue(const compiler: PCompilerState; const index: Byte;
      const isLocal: Boolean): Integer;
    function resolveUpvalue(const compiler: PCompilerState; const name: TToken;
      var arg: Integer): boolean;
    procedure namedVariable(const name: TToken; const canAssign: Boolean);
    function argumentList(): Byte;

    procedure expression();
    procedure beginScope();
    procedure endScope();
    procedure block();
    procedure expressionStatement();
    procedure printStatement();
    procedure ifStatement();
    procedure returnStatement();
    procedure whileStatement();
    procedure forStatement();
    procedure statement();
    procedure function_(const type_: TFunctionType);
    procedure method();
    procedure classDeclaration();
    procedure funDeclaration();
    procedure varDeclaration();
    procedure declaration();
    procedure synchronize();

    procedure number(const canAssign: Boolean);
    procedure literal(const canAssign: Boolean);
    procedure string_(const canAssign: Boolean);
    procedure variable(const canAssign: Boolean);
    procedure this_(const canAssign: Boolean);
    procedure unary(const canAssign: Boolean);
    procedure binary(const canAssign: Boolean);
    procedure grouping(const canAssign: Boolean);
    procedure call(const canAssign: Boolean);
    procedure dot(const canAssign: Boolean);

    procedure and_(const canAssign: Boolean);
    procedure or_(const canAssign: Boolean);

    function compile_(const source: string): PObjFunction;
  end;

function compile(const source: string; const mgr: TObjectManager_Fun): PObjFunction;
begin
  with TCompiler.Create(mgr) do
  try
    Result := compile_(source);
  finally
    Free;
  end;
end;

{ TCompiler }

constructor TCompiler.Create(const mgr: TObjectManager_Fun);

  procedure init_rule(const token: TokenType; const prefix, infix: TParseProc; const precedence: TPrecedence);
  begin
    parseRules[token].prefix := prefix;
    parseRules[token].infix := infix;
    parseRules[token].precedence := precedence;
  end;

begin
  MM := mgr;
  current := nil;
  currentClass := nil;
  MM.registerMarker(@markCompilerRoots);
  init_rule(TOKEN_LEFT_PAREN   , @grouping, @call  , PREC_CALL);
  init_rule(TOKEN_RIGHT_PAREN  , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_LEFT_BRACE   , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_RIGHT_BRACE  , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_COMMA        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_DOT          , nil      , @dot   , PREC_CALL);
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
  init_rule(TOKEN_AND          , nil      , @and_  , PREC_AND);
  init_rule(TOKEN_CLASS        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_ELSE         , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_FALSE        , @literal , nil    , PREC_NONE);
  init_rule(TOKEN_FOR          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_FUN          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_IF           , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_NIL          , @literal , nil    , PREC_NONE);
  init_rule(TOKEN_OR           , nil      , @or_   , PREC_OR);
  init_rule(TOKEN_PRINT        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_RETURN       , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_SUPER        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_THIS         , @this_   , nil    , PREC_NONE);
  init_rule(TOKEN_TRUE         , @literal , nil    , PREC_NONE);
  init_rule(TOKEN_VAR          , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_WHILE        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_ERROR        , nil      , nil    , PREC_NONE);
  init_rule(TOKEN_EOF          , nil      , nil    , PREC_NONE);
end;

destructor TCompiler.Destroy;
begin
  MM.unregisterMarker(@markCompilerRoots);
  inherited Destroy;
end;

procedure TCompiler.markCompilerRoots();
var
  compiler: PCompilerState;
begin
  compiler := current;
  while compiler <> nil do
  begin
    MM.markObject(PLoxObj(compiler^.func));
    compiler := compiler^.enclosing;
  end;
end;

function TCompiler.currentChunk: TChunk;
begin
  Result := current^.func^.fn.chunk;
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

procedure TCompiler.emitIndex(const Idx: Integer; const B: OpCode);
begin
  if Idx > $ff then
    emitCodeLong(OP_INDEX_LONG, Idx)
  else
    emitCodeByte(OP_INDEX, Byte(Idx));
  emitCode(B);
end;

procedure TCompiler.emitReturn();
begin
  if current^.funType = TYPE_INITIALIZER then
    emitCodeByte(OP_GET_LOCAL, 0)
  else
    emitCode(OP_NIL);
  emitCode(OP_RETURN);
end;

procedure TCompiler.emitConstant(const V: TValue);
var
  constant: Integer;
begin
  constant := makeConstant(V);
  emitIndex(constant, OP_CONSTANT);
end;

function TCompiler.emitJump(const B: OpCode): Integer;
begin
  emitCode(B);
  emitByte($FF);
  emitByte($FF);
  Result := currentChunk().count - 2;
end;

procedure TCompiler.patchJump(const offset: Integer);
var
  jump: Integer;
begin
  // -2 to adjust for the bytecode for the jump offset itself.
  jump := currentChunk().count - offset - 2;

  if jump > high(UInt16) then
    error('Too much code to jump over.');

  currentChunk().code[offset] := (jump shr 8) and $FF;
  currentChunk().code[offset + 1] := jump and $FF;
end;

procedure TCompiler.emitLoop(const loopStart: integer);
var
  offset: integer;
begin
  emitCode(OP_LOOP);

  offset := currentChunk().count - loopStart +  2;
  if offset > high(UInt16) then
    error('Loop body too large.');

  emitByte((offset shr 8) and $ff);
  emitByte(offset and $ff);
end;

procedure TCompiler.initCompiler(const state: PCompilerState; const type_: TFunctionType);
var
  local: PLocal;
begin
  state^.enclosing := current;
  state^.func := nil;
  state^.funType := type_;
  state^.localCount := 0;
  state^.scopeDepth := 0;
  state^.func := MM.newFunction();
  current := state;
  if type_ <> TYPE_SCRIPT then
    current^.func^.fn.name := MM.copyString(parser.previous.start, parser.previous.length);

  local := @current^.locals[current^.localCount];
  inc(current^.localCount);
  local^.depth := 0;
  local^.isCaptured := false;
  if type_ <> TYPE_FUNCTION then
  begin
    local^.name.start := 'this';
    local^.name.length := 4;
  end
  else
  begin
    local^.name.start := '';
    local^.name.length := 0;
  end;
end;

function TCompiler.endCompiler: PObjFunction;
begin
  emitReturn();
  Result := current^.func;
  {$ifdef DEBUG_PRINT_CODE}
  if (not parser.hadError) and debugPrintCode then
  begin
    if Result^.fn.name = nil then
      disassembleChunk(currentChunk(), '<script>')
    else
      disassembleChunk(currentChunk(), Result^.fn.name^.chars);
  end;
  {$endif}
  current := current^.enclosing;
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
  Result := makeConstant(OBJ_VAL(currentChunk().MM.copyString(name.start, name.length)));
end;

procedure TCompiler.addLocal(const name: TToken);
var
  local: PLocal;
begin
  if current^.localCount = UINT8_COUNT then
  begin
    error('Too many local variables in function.');
    Exit;
  end;

  local := @current^.locals[current^.localCount];
  inc(current^.localCount);
  local^.name := name;
  local^.depth := -1;
  local^.isCaptured := false;
end;

procedure TCompiler.markInitialized();
begin
  if current^.scopeDepth = 0 then
    Exit;
  current^.locals[current^.localCount - 1].depth := current^.scopeDepth;
end;

procedure TCompiler.declareVariable();
var
  local: PLocal;
  i: Integer;
begin
  if current^.scopeDepth = 0 then
    Exit;

  //name := @parser.previous;
  for i := current^.localCount - 1 downto 0 do
  begin
    local := @current^.locals[i];
    if (local^.depth <> -1) and (local^.depth < current^.scopeDepth) then
      Break;

    if identifiersEqual(parser.previous, local^.name) then
      error('Already a variable with this name in this scope.');
  end;
  //addLocal(name^);
  addLocal(parser.previous);
end;

function TCompiler.parseVariable(const msg: PChar): Integer;
begin
  consume(TOKEN_IDENTIFIER, msg);

  declareVariable();
  if current^.scopeDepth > 0 then
    Exit(0);

  Result := identifierConstant(parser.previous);
end;

procedure TCompiler.defineVariable(const global: Integer);
begin
  if current^.scopeDepth > 0 then
  begin
    markInitialized();
    Exit;
  end;

  emitIndex(global, OP_DEFINE_GLOBAL);
end;

function TCompiler.resolveLocal(const compiler: PCompilerState; const name: TToken): integer;
var
  i: Integer;
  local: PLocal;
begin
  for i := compiler^.localCount - 1 downto 0 do
  begin
    local := @compiler^.locals[i];
    if identifiersEqual(name, local^.name) then
    begin
      if local^.depth = -1 then
        error('Can''t read local variable in its own initializer.');
      Exit(i);
    end;
  end;

  Result := -1;
end;

function TCompiler.addUpvalue(const compiler: PCompilerState; const index: Byte;
  const isLocal: Boolean): Integer;
var
  i: integer;
  upval: PUpValue;
begin
  Result := compiler^.func^.fn.upvalueCount;

  for i := 0 to Result - 1 do
  begin
    upval := @compiler^.upvalues[i];
    if (upval^.index = index) and (upval^.isLocal = isLocal) then
      Exit(i);
  end;

  if Result = UINT8_COUNT then
  begin
    error('Too many closure variables in function.');
    Exit(0);
  end;

  compiler^.upvalues[Result].isLocal := isLocal;
  compiler^.upvalues[Result].index := index;
  inc(compiler^.func^.fn.upvalueCount);
end;

function TCompiler.resolveUpvalue(const compiler: PCompilerState; const name: TToken;
  var arg: Integer): boolean;
var
  local, upvalue: Integer;
begin
  if compiler^.enclosing = nil then
    Exit(false);

  local := resolveLocal(compiler^.enclosing, name);
  if local <> -1 then
  begin
    compiler^.enclosing^.locals[local].isCaptured := true;
    arg := addUpvalue(compiler, Byte(local), true);
    Exit(true);
  end;

  upvalue := -1;
  if resolveUpvalue(compiler^.enclosing, name, upvalue) then
  begin
    arg := addUpvalue(compiler, Byte(upvalue), false);
    Exit(true);
  end;

  Result := false;
end;

procedure TCompiler.namedVariable(const name: TToken; const canAssign: Boolean);
var
  arg: Integer;
  getOp, setOp: OpCode;
begin
  arg := resolveLocal(current, name);
  if arg <> -1 then
  begin
    getOp := OP_GET_LOCAL;
    setOp := OP_SET_LOCAL;
  end
  else
  if resolveUpvalue(current, name, arg) then
  begin
    getOp := OP_GET_UPVALUE;
    setOp := OP_SET_UPVALUE;
  end
  else
  begin
    arg := identifierConstant(name);
    if canAssign and match(TOKEN_EQUAL) then
    begin
      expression();
      emitIndex(arg, OP_SET_GLOBAL);
    end
    else
      emitIndex(arg, OP_GET_GLOBAL);
    Exit;
  end;

  if canAssign and match(TOKEN_EQUAL) then
  begin
    expression();
    emitCodeByte(setOp, arg);
  end
  else
    emitCodeByte(getOp, arg);
end;

function TCompiler.argumentList(): Byte;
begin
  Result := 0;
  if not check(TOKEN_RIGHT_PAREN) then
  repeat
    expression();
    if Result = 255 then
      error('Can''t have more than 255 arguments.');
    inc(Result);
  until not match(TOKEN_COMMA);
  consume(TOKEN_RIGHT_PAREN, 'Expect ")" after arguments.');
end;

procedure TCompiler.expression();
begin
  parsePrecedense(PREC_ASSIGNMENT);
end;

procedure TCompiler.beginScope();
begin
  inc(current^.scopeDepth);
end;

procedure TCompiler.endScope();
begin
  dec(current^.scopeDepth);

  while (current^.localCount > 0) and
        (current^.locals[current^.localCount - 1].depth > current^.scopeDepth)
  do begin
    if current^.locals[current^.localCount - 1].isCaptured then
      emitCode(OP_CLOSE_UPVALUE)
    else
      emitCode(OP_POP);
    dec(current^.localCount);
  end;
end;

procedure TCompiler.block();
begin
  while (not check(TOKEN_RIGHT_BRACE)) and (not check(TOKEN_EOF)) do
    declaration();

  consume(TOKEN_RIGHT_BRACE, 'Expect "}" after block.');
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

procedure TCompiler.ifStatement();
var
  thenJump, elseJump: Integer;
begin
  consume(TOKEN_LEFT_PAREN, 'Expect "(" after "if".');
  expression();
  consume(TOKEN_RIGHT_PAREN, 'Expect ")" after condition.');

  thenJump := emitJump(OP_JUMP_IF_FALSE);
  emitCode(OP_POP);
  statement();

  elseJump := emitJump(OP_JUMP);

  patchJump(thenJump);
  emitCode(OP_POP);

  if match(TOKEN_ELSE) then
    statement();
  patchJump(elseJump);
end;

procedure TCompiler.returnStatement();
begin
  if current^.funType = TYPE_SCRIPT then
    error('Can''t return from top-level code.');

  if match(TOKEN_SEMICOLON) then
    emitReturn()
  else begin
    if current^.funType = TYPE_INITIALIZER then
      error('Can''t return a value from an initializer.');
    expression();
    consume(TOKEN_SEMICOLON, 'Expect ";" after return value.');
    emitCode(OP_RETURN);
  end;
end;

procedure TCompiler.whileStatement();
var
  exitJump, loopStart: integer;
begin
  loopStart := currentChunk().count;
  consume(TOKEN_LEFT_PAREN, 'Expect "(" after "while".');
  expression();
  consume(TOKEN_RIGHT_PAREN, 'Expect ")" after condition.');

  exitJump := emitJump(OP_JUMP_IF_FALSE);
  emitCode(OP_POP);
  statement();
  emitLoop(loopStart);

  patchJump(exitJump);
  emitCode(OP_POP);
end;

procedure TCompiler.forStatement();
var
  loopStart, exitJump, bodyJump,
  incrementStart: Integer;
begin
  beginScope();
  consume(TOKEN_LEFT_PAREN, 'Expect "(" after "for".');
  if match(TOKEN_SEMICOLON) then
    begin {No initializer.} end
  else if match(TOKEN_VAR) then
    varDeclaration()
  else
    expressionStatement();

  loopStart := currentChunk().count;
  exitJump := -1;
  if not match(TOKEN_SEMICOLON) then
  begin
    expression();
    consume(TOKEN_SEMICOLON, 'Expect ";" after loop condition.');

    exitJump := emitJump(OP_JUMP_IF_FALSE);
    emitCode(OP_POP);
  end;

  if not match(TOKEN_RIGHT_PAREN) then
  begin
    bodyJump := emitJump(OP_JUMP);
    incrementStart := currentChunk().count;
    expression();
    emitCode(OP_POP);
    consume(TOKEN_RIGHT_PAREN, 'Expect ")" after for clauses.');

    emitLoop(loopStart);
    loopStart := incrementStart;
    patchJump(bodyJump);
  end;

  statement();
  emitLoop(loopStart);

  if exitJump <> -1 then
  begin
    patchJump(exitJump);
    emitCode(OP_POP);
  end;

  endScope();
end;

procedure TCompiler.statement();
begin
  if match(TOKEN_PRINT) then
    printStatement()
  else if match(TOKEN_FOR) then
    forStatement()
  else if match(TOKEN_IF) then
    ifStatement()
  else if match(TOKEN_RETURN) then
    returnStatement()
  else if match(TOKEN_WHILE) then
    whileStatement()
  else if match(TOKEN_LEFT_BRACE) then
  begin
    beginScope();
    block();
    endScope();
  end
  else
    expressionStatement();
end;

procedure TCompiler.function_(const type_: TFunctionType);
var
  compiler: TCompilerState;
  func: PObjFunction;
  constant, i: Integer;
begin
  initCompiler(@compiler, type_);
  beginScope();

  consume(TOKEN_LEFT_PAREN, 'Expect "(" after function name.');
  if not check(TOKEN_RIGHT_PAREN) then
  repeat
    inc(current^.func^.fn.arity);
    if current^.func^.fn.arity > 255 then
      errorAtCurrent('Can''t have more than 255 parameters.');
    constant := parseVariable('Expect parameter name.');
    defineVariable(constant);
  until not match(TOKEN_COMMA);
  consume(TOKEN_RIGHT_PAREN, 'Expect ")" after parameters.');
  consume(TOKEN_LEFT_BRACE, 'Expect "{" before function body.');
  block();

  func := endCompiler();
  emitIndex(makeConstant(OBJ_VAL(func)), OP_CLOSURE);

  for i := 0 to func^.fn.upvalueCount - 1 do
  begin
    if compiler.upvalues[i].isLocal then
      emitByte(1)
    else
      emitByte(0);
    emitByte(compiler.upvalues[i].index);
  end;
end;

procedure TCompiler.method();
var
  constant: Integer;
begin
  consume(TOKEN_IDENTIFIER, 'Expect method name.');
  constant := identifierConstant(parser.previous);

  if (parser.previous.length = 4) and
     memcmp(parser.previous.start, PChar('init'), 4)
  then
    function_(TYPE_INITIALIZER)
  else
    function_(TYPE_METHOD);
  emitIndex(constant, OP_METHOD);
end;

procedure TCompiler.classDeclaration();
var
  nameConstant: integer;
  klassName: TToken;
  classCompiler: TClassCompiler;
begin
  consume(TOKEN_IDENTIFIER, 'Expect class name.');
  klassName := parser.previous;
  nameConstant := identifierConstant(parser.previous);
  declareVariable();

  emitIndex(nameConstant, OP_CLASS);
  defineVariable(nameConstant);

  classCompiler.enclosing := currentClass;
  currentClass := @classCompiler;

  namedVariable(klassName, false);
  consume(TOKEN_LEFT_BRACE, 'Expect "{" before class body.');
  while not check(TOKEN_RIGHT_BRACE) and not check(TOKEN_EOF) do
    method();
  consume(TOKEN_RIGHT_BRACE, 'Expect "}" after class body.');
  emitCode(OP_POP);

  currentClass := currentClass^.enclosing;
end;

procedure TCompiler.funDeclaration();
var
  global: Integer;
begin
  global := parseVariable('Expect function name.');
  markInitialized();
  function_(TYPE_FUNCTION);
  defineVariable(global);
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
  if match(TOKEN_CLASS) then
     classDeclaration()
  else if match(TOKEN_FUN) then
    funDeclaration()
  else if match(TOKEN_VAR) then
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
  emitConstant(OBJ_VAL(currentChunk().MM.copyString(parser.previous.start + 1, parser.previous.length - 2)));
end;

procedure TCompiler.variable(const canAssign: Boolean);
begin
  namedVariable(parser.previous, canAssign);
end;

procedure TCompiler.this_(const canAssign: Boolean);
begin
  if currentClass = nil then
  begin
    error('Can''t use "this" outside of a class.');
    Exit;
  end;
  variable(false);
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

procedure TCompiler.call(const canAssign: Boolean);
var
  argCount: Byte;
begin
  argCount := argumentList();
  emitCodeByte(OP_CALL, argCount);
end;

procedure TCompiler.dot(const canAssign: Boolean);
var
  name: Integer;
begin
  consume(TOKEN_IDENTIFIER, 'Expect property name after ".".');
  name := identifierConstant(parser.previous);

  if canAssign and match(TOKEN_EQUAL) then
  begin
    expression();
    emitIndex(name, OP_SET_PORPERTY);
  end
  else
  begin
    emitIndex(name, OP_GET_PORPERTY);
  end;
end;

procedure TCompiler.and_(const canAssign: Boolean);
var
  endJump: Integer;
begin
  endJump := emitJump(OP_JUMP_IF_FALSE);

  emitCode(OP_POP);
  parsePrecedense(PREC_AND);

  patchJump(endJump);
end;

procedure TCompiler.or_(const canAssign: Boolean);
var
  elseJump, endJump: Integer;
begin
  elseJump := emitJump(OP_JUMP_IF_FALSE);
  endJump := emitJump(OP_JUMP);

  patchJump(elseJump);
  emitCode(OP_POP);

  parsePrecedense(PREC_OR);
  patchJump(endJump);
end;

function TCompiler.compile_(const source: string): PObjFunction;
var
  state: TCompilerState;
begin
  parser.hadError := false;
  parser.panicMode := false;

  initCompiler(@state, TYPE_SCRIPT);
  scanner := TLoxScanner.Create(source);
  try
    advance();
    while not match(TOKEN_EOF) do
      declaration();
  finally
    scanner.Free;
  end;
  Result := endCompiler();
  if parser.hadError then
    Result := nil;
end;

end.

