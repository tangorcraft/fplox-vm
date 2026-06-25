unit scanner;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, common;

type
  TokenType = (
  // Single-character tokens.
  TOKEN_LEFT_PAREN, TOKEN_RIGHT_PAREN,
  TOKEN_LEFT_BRACE, TOKEN_RIGHT_BRACE,
  TOKEN_COMMA, TOKEN_DOT, TOKEN_MINUS, TOKEN_PLUS,
  TOKEN_SEMICOLON, TOKEN_SLASH, TOKEN_STAR,
  // One or two character tokens.
  TOKEN_BANG, TOKEN_BANG_EQUAL,
  TOKEN_EQUAL, TOKEN_EQUAL_EQUAL,
  TOKEN_GREATER, TOKEN_GREATER_EQUAL,
  TOKEN_LESS, TOKEN_LESS_EQUAL,
  // Literals.
  TOKEN_IDENTIFIER, TOKEN_STRING, TOKEN_NUMBER,
  // Keywords.
  TOKEN_AND, TOKEN_CLASS, TOKEN_ELSE, TOKEN_FALSE,
  TOKEN_FOR, TOKEN_FUN, TOKEN_IF, TOKEN_NIL, TOKEN_OR,
  TOKEN_PRINT, TOKEN_RETURN, TOKEN_SUPER, TOKEN_THIS,
  TOKEN_TRUE, TOKEN_VAR, TOKEN_WHILE,

  TOKEN_ERROR, TOKEN_EOF
  );
  TToken = record
    type_: TokenType;
    start: PChar;
    length: Integer;
    line: Integer;
  end;

  { TLoxScanner }

  TLoxScanner = class
  private
    FSource: string;
  public
    start: PChar;
    current: PChar;
    line: integer;

    constructor Create(const source: string);
    destructor Destroy; override;

    function scanToken(): TToken;
  end;

implementation

{ TLoxScanner }

constructor TLoxScanner.Create(const source: string);
begin
  if source = '' then
    FSource := NL
  else
    FSource := source;
  start := @FSource[1];
  current := start;
  line := 1;
end;

destructor TLoxScanner.Destroy;
begin
  inherited Destroy;
end;

function TLoxScanner.scanToken(): TToken;
var
  c: Char;

  function IsAtEnd: boolean;
  begin
    Result := (current^ = #0);
  end;

  function makeToken(const type_: TokenType): TToken;
  begin
    Result.type_ := type_;
    Result.start := start;
    Result.length := integer(current - start);
    Result.line := line;
  end;

  function errorToken(const msg: string): TToken;
  begin
    Result.type_ := TOKEN_ERROR;
    Result.start := @msg[1];
    Result.length := length(msg);
    Result.line := line;
  end;

  procedure advance;
  begin
    c := current^;
    inc(current);
  end;

  function match(const expected: char): Boolean;
  begin
    if IsAtEnd then
      Exit(false);
    if (current^ <> expected) then
      Exit(false);
    inc(current);
    Result := true;
  end;

  function matchAB(const expected: char; const yes, no: TokenType): TokenType;
  begin
    if match(expected) then
      Result := yes
    else
      Result := no;
  end;

  function peek: Char;
  begin
    Result := current^;
  end;

  function peekNext: Char;
  begin
    if IsAtEnd then Exit(#0);
    Result := current[1];
  end;

  procedure skipWhitespace;
  begin
    while true do
      case peek() of
        ' ',
        #10, // line feed
        #9: // tab
          advance;
        NL: begin
          inc(line);
          advance;
        end;
        '/': begin
          if peekNext() = '/' then
            while (peek() <> NL) and (not IsAtEnd()) do
              advance
          else
            Exit;
        end
      else
        Exit;
      end;
  end;

  function strToken(): TToken;
  begin
    while (peek() <> '"') and (not IsAtEnd()) do
    begin
      if peek() = NL then
        inc(line);
      advance;
    end;

    if IsAtEnd then
      Exit(errorToken('Unterminated string.'));

    advance; // closing quote
    Result := makeToken(TOKEN_STRING);
  end;

  function isDigit(const ch: Char): Boolean;
  begin
    Result := (ch >= '0') and (ch <= '9');
  end;

  function numberToken(): TToken;
  begin
    while isDigit(peek()) do
      advance;

    // look for fractional part
    if (peek() = '.') and (isDigit(peekNext())) then
    begin
      advance;
      while isDigit(peek()) do
        advance;
    end;
    Result := makeToken(TOKEN_NUMBER);
  end;

  function isAlpha(const ch: Char): Boolean;
  begin
    Result := ((ch >= 'a') and (ch <= 'z')) or
              ((ch >= 'A') and (ch <= 'Z')) or
              (ch = '_');
  end;

  procedure checkKeyword(const first, count: Integer; const rest: PChar;
    const kwType: TokenType; var T: TToken);
  begin
    if (T.length = (first + count)) and memcmp((T.start + first), rest, count) then
      T.type_ := kwType;
  end;

  procedure identifierTypeCheck(var T: TToken);
  begin
    case T.start[0] of
      'a': checkKeyword(1, 2, 'nd', TOKEN_AND, T);
      'c': checkKeyword(1, 4, 'lass', TOKEN_CLASS, T);
      'e': checkKeyword(1, 3, 'lse', TOKEN_ELSE, T);
      'f': begin
        if T.length > 1 then
          case T.start[1] of
            'a': checkKeyword(2, 3, 'lse', TOKEN_FALSE, T);
            'o': checkKeyword(2, 1, 'r', TOKEN_FOR, T);
            'u': checkKeyword(2, 1, 'n', TOKEN_FUN, T);
          end;
      end;
      'i': checkKeyword(1, 1, 'f', TOKEN_IF, T);
      'n': checkKeyword(1, 2, 'il', TOKEN_NIL, T);
      'o': checkKeyword(1, 1, 'r', TOKEN_OR, T);
      'p': checkKeyword(1, 4, 'rint', TOKEN_PRINT, T);
      'r': checkKeyword(1, 5, 'eturn', TOKEN_RETURN, T);
      's': checkKeyword(1, 4, 'uper', TOKEN_SUPER, T);
      't': begin
        if T.length > 1 then
          case T.start[1] of
            'h': checkKeyword(2, 2, 'is', TOKEN_THIS, T);
            'r': checkKeyword(2, 2, 'ue', TOKEN_TRUE, T);
          end;
      end;
      'v': checkKeyword(1, 2, 'ar', TOKEN_VAR, T);
      'w': checkKeyword(1, 4, 'hile', TOKEN_WHILE, T);
    end;
  end;

  function identifierToken(): TToken;
  begin
    while isAlpha(peek()) or isDigit(peek()) do
      advance;
    Result := makeToken(TOKEN_IDENTIFIER);
    identifierTypeCheck(Result);
  end;

begin
  skipWhitespace;
  start := current;

  if IsAtEnd then
    Exit(makeToken(TOKEN_EOF));

  advance;

  if isAlpha(c) then
    Exit(identifierToken());
  if isDigit(c) then
    Exit(numberToken());

  case c of
    '(': Exit(makeToken(TOKEN_LEFT_PAREN));
    ')': Exit(makeToken(TOKEN_RIGHT_PAREN));
    '{': Exit(makeToken(TOKEN_LEFT_BRACE));
    '}': Exit(makeToken(TOKEN_RIGHT_BRACE));
    ';': Exit(makeToken(TOKEN_SEMICOLON));
    ',': Exit(makeToken(TOKEN_COMMA));
    '.': Exit(makeToken(TOKEN_DOT));
    '-': Exit(makeToken(TOKEN_MINUS));
    '+': Exit(makeToken(TOKEN_PLUS));
    '/': Exit(makeToken(TOKEN_SLASH));
    '*': Exit(makeToken(TOKEN_STAR));

    '!': Exit(makeToken(matchAB('=', TOKEN_BANG_EQUAL, TOKEN_BANG)));
    '=': Exit(makeToken(matchAB('=', TOKEN_EQUAL_EQUAL, TOKEN_EQUAL)));
    '<': Exit(makeToken(matchAB('=', TOKEN_LESS_EQUAL, TOKEN_LESS)));
    '>': Exit(makeToken(matchAB('=', TOKEN_GREATER_EQUAL, TOKEN_GREATER)));

    '"': Exit(strToken());
  end;

  Result := errorToken('Unexpected character.');
end;

end.

