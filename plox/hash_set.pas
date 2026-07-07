unit hash_set;

{$mode ObjFPC}{$H+}
{$i defines.inc}

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
    FLinkCount: Cardinal; // number of separate linked list entries
    FGrowThreshold: Cardinal;
    FCapacity: Cardinal;

    function tableFindKey(const chars: PChar; const len: Integer; const hash: uint32;
      out entry: PKeyEntry): Boolean;
    procedure grow();
    function newNext(const entry: PKeyEntry): PKeyEntry;
    function tableGetEntry(const chars: PChar; const len: Integer): PKeyEntry;
    procedure freeLinkedList(var top: PKeyEntry);
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { TObjectManager_SI: String Interning}

  TObjectManager_SI = class(TObjectManager)
  private
    FHashSet: TKeyTable;
  public
    constructor Create;
    destructor Destroy; override;

    // hiding methods of the parent class
    function takeString(const chars: PChar; const len: Integer): PObjString;
    function copyString(const start: PChar; const len: Integer): PObjString;
  end;

implementation

const
  entrySize = SizeOf(TKeyEntry);
  HASHSET_MAX_LOAD = 0.4; // LinkCount to Capacity ratio

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

procedure TKeyTable.grow();
var
  old_size, i: Integer;
  old_list, bin: PKeyEntry;
  iter_entry: PKeyEntry;

  function newEntryTop(var top: PKeyEntry): PKeyEntry;
  begin
    if bin = nil then
      Result := ALLOCATE(entrySize)
    else begin
      Result := bin;
      bin := bin^.next;
    end;
    Result^.next := top;
    top := Result;
  end;

  procedure copyEntry(const copy_entry: TKeyEntry);
  var
    idx: Integer;
    target_entry: PKeyEntry;
  begin
    idx := copy_entry.hash mod FCapacity;
    target_entry := FList + idx;
    if target_entry^.key <> nil then
    begin
      target_entry := newEntryTop(target_entry^.next);
      inc(FLinkCount);
    end;
    target_entry^.key := copy_entry.key;
    target_entry^.hash := copy_entry.hash;
  end;

  procedure copyLinkedList();
  var
    tmp_entry, copy_entry: PKeyEntry;
  begin
    copy_entry := iter_entry^.next;
    while copy_entry <> nil do
    begin
      copyEntry(copy_entry^);
      tmp_entry := copy_entry;
      copy_entry := tmp_entry^.next; // next iteration
      tmp_entry^.next := bin; // moving tmp to bin
      bin := tmp_entry;
    end;
  end;

begin
  old_list := FList;
  old_size := FCapacity;
  FCapacity := GROW_CAPACITY(FCapacity + FLinkCount);
  FLinkCount := 0;

  FList := GROW_ARRAY(nil, 0, FCapacity, entrySize);
  FillChar(FList^, FCapacity * entrySize, 0);
  FGrowThreshold := Trunc(FCapacity * HASHSET_MAX_LOAD);
  if old_list = nil then Exit;

  bin := nil;
  // when separately allocated key entry is copied
  // it will be moved to bin, a linked list, instead of being freed
  // if new collisions occur, entries from bin will be used instead of allocating new entry
  // it is possible that freeing them immediately and allocating new entry as/if needed will be faster
  for i := 0 to old_size - 1 do
  begin
    iter_entry := old_list + i;
    copyLinkedList();
    copyEntry(iter_entry^);
  end;
  FREE_ARRAY(old_list, old_size, entrySize);
  freeLinkedList(bin);
end;

function TKeyTable.newNext(const entry: PKeyEntry): PKeyEntry;
begin
  inc(FLinkCount);
  Result := ALLOCATE(entrySize);
  Result^.next := nil;
  Result^.key := nil;
  entry^.next := Result;
end;

function TKeyTable.tableGetEntry(const chars: PChar; const len: Integer): PKeyEntry;
var
  hash: UInt32;
begin
  if (FLinkCount >= FGrowThreshold) then
    grow();
  hash := hashStringNZ(chars, len);
  if not tableFindKey(chars, len, hash, Result) then
  begin
    if Result^.key <> nil then
      Result := newNext(Result);
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

constructor TKeyTable.Create;
begin
  FLinkCount := 0;
  FCapacity := 0;
  FList := nil;
  grow();
end;

destructor TKeyTable.Destroy;
var
  i: Cardinal;
begin
  // hash set does not own any objects, so we only need to free memory for the key entries
  for i := 0 to FCapacity - 1 do
    freeLinkedList(FList[i].next);
  FREE_ARRAY(FList, FCapacity, entrySize);
  inherited Destroy;
end;

{ TObjectManager_SI }

constructor TObjectManager_SI.Create;
begin
  inherited Create;
  FHashSet := TKeyTable.Create;
end;

destructor TObjectManager_SI.Destroy;
begin
  FHashSet.Free;
  inherited Destroy;
end;

function TObjectManager_SI.takeString(const chars: PChar; const len: Integer): PObjString;
var
  entry: PKeyEntry;
begin
  entry := FHashSet.tableGetEntry(chars, len);
  if entry^.key <> nil then
  begin
    FREE_ARRAY(chars, len, SizeOf(Char));
    Exit(entry^.key)
  end
  else begin
    Result := inherited takeString(chars, len);
    entry^.key := Result;
  end;
end;

function TObjectManager_SI.copyString(const start: PChar; const len: Integer): PObjString;
var
  entry: PKeyEntry;
begin
  entry := FHashSet.tableGetEntry(start, len);
  if entry^.key <> nil then
    Exit(entry^.key)
  else begin
    Result := inherited copyString(start, len);
    entry^.key := Result;
  end;
end;

end.

