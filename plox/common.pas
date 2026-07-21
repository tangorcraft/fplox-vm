unit common;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, Math;

type
  TProcedureMethod = procedure of object;
  TStringMethod = procedure (const S: string) of object;

var
  lox_output: TStringMethod;
  lox_error: TStringMethod;
  {$ifdef DEBUG}
  debugPrintCode: Boolean = True;
  debugTraceExecution: Boolean = True;
  debugStressGC: Boolean = True;
  debugLogGC: Boolean = True;
  {$endif}

const
  NL = #13; // new line
  NaN = Math.NaN;
  UINT8_MAX = high(UInt8);
  UINT8_COUNT = UINT8_MAX + 1;

procedure print(S: string; const err: Boolean = false);
procedure printf(const Fmt: string; vars: array of const; const err: Boolean = false);

function memcmp(const p1, p2: Pointer; const count: SizeInt): boolean;
procedure memcpy(const dest, source: Pointer; const count: SizeInt);
function strtod(const S: string): Double;

function hashStringNZ(const S: PChar; const len: Integer): UInt32;

implementation

{$ifdef USE_SIPHASH}
uses
  siphash_1_3;
{$endif}

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
  MAX_LINE = 160;

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

{$ifdef USE_SIPHASH}
var
  sip_key: packed array[0..15] of Byte;
{$else}
const
  FNV_Basis32 = $811c9dc5;
  FNV_Prime32 = $01000193;
  FNV_Basis64 = $cbf29ce484222325;
  FNV_Prime64 = $100000001b3;

function hash_FNV_1a(S: PChar; len: Integer): UInt32;
begin
  Result := FNV_Basis32;
  while len > 0 do
  begin
    Result := (Ord(S^) xor Result) * FNV_Prime32;
    dec(len);
    inc(S);
  end;
end;

function hash_FNV_1a_64(S: PChar; len: Integer): UInt64;
begin
  Result := FNV_Basis64;
  while len > 0 do
  begin
    Result := (Ord(S^) xor Result) * FNV_Prime64;
    dec(len);
    inc(S);
  end;
end;
{$endif}

function hashStringNZ(const S: PChar; const len: Integer): UInt32;
begin
  {$ifdef USE_SIPHASH}
  // 4 bytes halfSipHash out to uint32 Result
  halfsiphash_1_3(S, len, @sip_key[0], PByte(@Result), half_out_len_4b);
  {$else}
  Result := hash_FNV_1a(S, len);
  {$endif}
  if Result = 0 then // no zero result
    Result := MaxLongint;
end;

initialization
  std.proc := @internal_print;
  stderr.proc := @internal_print_err;
  {$ifdef USE_SIPHASH}
  Randomize;
  PInt64(@sip_key[0])^ := Random(high(Int64));
  PInt64(@sip_key[8])^ := Random(high(Int64));
  {$endif}
end.

