unit hash_set;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, object_, value, memory, common;

type
  PKeyEntry = ^TKeyEntry;
  TKeyEntry = record
    key: PObjString;
    hash: UInt32;
    next: PKeyEntry;
  end;

  { TKeyTable }

  TKeyTable = class
  private
    FList: PKeyEntry;
    FCount: Cardinal;
    FCapacity: Cardinal;

    FObjs: TObjectManager;

    function tableFindKey(const chars: PChar; const len: Integer; const hash: uint32;
      out entry: PKeyEntry): Boolean;
    function makeNext(const entry: PKeyEntry): PKeyEntry;
    function tableGetEntry(const chars: PChar; const len: Integer): PKeyEntry;
    procedure freeLinkedList(var top: PKeyEntry);
  public
    constructor Create(const mgr: TObjectManager);
    destructor Destroy; override;

    function takeString(const chars: PChar; const len: Integer): PObjString;
    function copyString(const start: PChar; const len: Integer): PObjString;
  end;

implementation

const
  entrySize = SizeOf(TKeyEntry);

{ TKeyTable }

function TKeyTable.tableFindKey(const chars: PChar; const len: Integer; const hash: uint32;
  out entry: PKeyEntry): Boolean;
var
  idx: Integer;
begin
  idx := hash mod FCapacity;
  entry := FList + idx;
  while entry^.key <> nil do
  begin
    Result :=
      (entry^.hash = hash) and
      (entry^.key^.length_ = len) and
      memcmp(entry^.key^.chars, chars, len);
    if Result then Exit;
    if entry^.next = nil then
      Break
    else
      entry := entry^.next;
  end;
  Result := False;
end;

function TKeyTable.makeNext(const entry: PKeyEntry): PKeyEntry;
begin
  Result := ALLOCATE(entrySize);
  Result^.next := nil;
  Result^.key := nil;
  entry^.next := Result;
end;

function TKeyTable.tableGetEntry(const chars: PChar; const len: Integer): PKeyEntry;
var
  hash: UInt32;
begin
  hash := hashStringNZ(chars, len);
  if not tableFindKey(chars, len, hash, Result) then
  begin
    if Result^.key <> nil then
      Result := makeNext(Result);
    Result^.hash := hash;
  end;
end;

procedure TKeyTable.freeLinkedList(var top: PKeyEntry);
var
  next: PKeyEntry;
begin
  while top <> nil do
  begin
    next := top^.next;
    FREE_(top, entrySize);
    top := next;
  end;
end;

constructor TKeyTable.Create(const mgr: TObjectManager);
begin
  FCount := 0;
  FCapacity := 16;
  FObjs := mgr;
  FList := GROW_ARRAY(nil, 0, FCapacity, entrySize);
end;

destructor TKeyTable.Destroy;
var
  i: Cardinal;
begin
  for i := 0 to FCapacity - 1 do
    freeLinkedList(FList[i].next);
  FREE_ARRAY(FList, FCapacity, entrySize);
  inherited Destroy;
end;

function TKeyTable.takeString(const chars: PChar; const len: Integer): PObjString;
var
  entry: PKeyEntry;
begin
  entry := tableGetEntry(chars, len);
  if entry^.key <> nil then
  begin
    FREE_ARRAY(chars, len, SizeOf(Char));
    Exit(entry^.key)
  end
  else begin
    Result := FObjs.takeString(chars, len);
    entry^.key := Result;
  end;
end;

function TKeyTable.copyString(const start: PChar; const len: Integer): PObjString;
var
  entry: PKeyEntry;
begin
  entry := tableGetEntry(start, len);
  if entry^.key <> nil then
    Exit(entry^.key)
  else begin
    Result := FObjs.copyString(start, len);
    entry^.key := Result;
  end;
end;

end.

