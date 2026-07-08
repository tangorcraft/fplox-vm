unit hash_table;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, hash_set, object_, value, memory;

type
  TTableEntry = record
    key: PObjString;
    value: TValue;
  end;
  PTableEntry = ^TTableEntry;

  { THashTable }

  THashTable = class
  private
    FCount: Integer;
    FRealCount: Integer;
    FCapacity: Integer;
    FGrowThreshold: Integer;
    FShrinkThreshold: Integer;
    FProbeStep: Integer;
    FEntries: PTableEntry;

    FObjs: TObjectManager_SI;

    procedure PurgeTombs();
    procedure NewCapacity(const new_capacity: Integer);
    procedure AdjustCapacity();
    function findEntry(const key: PObjString): PTableEntry;
  public
    constructor Create(const aObjs: TObjectManager_SI);
    destructor Destroy; override;

    function tableGet(const key: PObjString; var V: TValue): Boolean;
    function tableSet(const key: PObjString; const V: TValue): Boolean;
    procedure tableAddAll(const from: THashTable);
  end;

implementation

{$ifdef DEBUG_HASH_TABLE}
uses
  common;
{$endif}

const
  entrySize = SizeOf(TTableEntry);
  HT_MAX_LOAD = 0.8;
  HT_MIN_LOAD = 0.3;
  HT_MIN_CAPACITY = 10;
  HT_SHRINK_FACTOR = 1.4;
  HT_PROBE_GROW_BASE = 32;
  HT_PROBE_GROW_FACTOR = 2;

{ THashTable }

procedure THashTable.PurgeTombs();
begin

end;

procedure THashTable.NewCapacity(const new_capacity: Integer);
var
  probe_grow: Integer;
begin
  FCapacity := new_capacity or 1; // let new capacity be odd
  FProbeStep := 1; // linear probe at low capacity
  probe_grow := FCapacity div HT_PROBE_GROW_BASE;
  while probe_grow > 0 do
  begin
    probe_grow := probe_grow div HT_PROBE_GROW_FACTOR;
    Inc(FProbeStep);
  end;
  if (FProbeStep and 1) = 1 then // probe step is odd, make odd capacity even
    inc(FCapacity);
  FEntries := ALLOC_AND_ZERO_ARRAY(FCapacity, entrySize);
  FGrowThreshold := Trunc(FCapacity * HT_MAX_LOAD);
  if FCapacity < HT_MIN_CAPACITY then
    FShrinkThreshold := 0
  else
    FShrinkThreshold := Trunc(FCapacity * HT_MIN_LOAD);
end;

procedure THashTable.AdjustCapacity();
var
  old_capacity, i: Integer;
  old_list, source, dest: PTableEntry;
begin
  // NewCapacity will create new TableEntry array, so we must save old values before calling it
  old_capacity := FCapacity;
  old_list := FEntries;
  if (FRealCount + 1) > FGrowThreshold then
    NewCapacity(GROW_CAPACITY(old_capacity))
  else if FRealCount < FShrinkThreshold then
    NewCapacity(Trunc(FRealCount * HT_SHRINK_FACTOR))
  else begin
    // number of real entries is within bounds, but this routine was called
    // this means that count of real entries + tombstones (FCount) exceeded grow threshold
    // so instead of resizing the hash table, it may be faster to only purge tombstones
    PurgeTombs();
    Exit;
  end;

  if old_list = nil then
    Exit;

  FCount := 0;
  for i := 0 to old_capacity - 1 do
  begin
    source := old_list + i;
    if source^.key = nil then Continue;
    dest := findEntry(source^.key);
    dest^ := source^;
    inc(FCount);
  end;
  {$ifdef DEBUG_HASH_TABLE}
  if FCount <> FRealCount then
  begin
    printf('ERROR: Count and real count mismatch after hash table resize: count=%d; real=%d; capacity=%d',
      [FCount, FRealCount, FCapacity], true);
    FRealCount := FCount;
  end;
  {$endif}
  FREE_ARRAY(old_list, old_capacity, entrySize);
end;

function THashTable.findEntry(const key: PObjString): PTableEntry;
var
  idx: integer;
  tombstone: PTableEntry;
begin
  idx := Integer(key^.hash) mod FCapacity;
  while true do
  begin
    Result := FEntries + idx;
    if (Result^.key = key) or (Result^.key = nil) then
      Exit;
    idx := (idx + FProbeStep) mod FCapacity;
  end;
end;

constructor THashTable.Create(const aObjs: TObjectManager_SI);
begin
  FObjs := aObjs;
  FCount := 0;
  FRealCount := 0;
  FCapacity := 0;
  FGrowThreshold := 0;
  FShrinkThreshold := 0;
  FProbeStep := 1;
  FEntries := nil;
end;

destructor THashTable.Destroy;
begin
  FREE_ARRAY(FEntries, FCapacity, entrySize);
  inherited Destroy;
end;

function THashTable.tableGet(const key: PObjString; var V: TValue): Boolean;
var
  entry: PTableEntry;
begin
  if FCount = 0 then
    Exit(false);

  entry := findEntry(key);
  if entry^.key = nil then
    Exit(false);

  V := entry^.value;
  Result := True;
end;

function THashTable.tableSet(const key: PObjString; const V: TValue): Boolean;
var
  entry: PTableEntry;
begin
  if FCount > FGrowThreshold then
    AdjustCapacity();

  entry := findEntry(key);
  Result := entry^.key = nil; // isNewKey
  if Result then
  begin
    inc(FCount);
    inc(FRealCount);
    entry^.key := key;
  end;
  entry^.value := V;
end;

procedure THashTable.tableAddAll(const from: THashTable);
var
  i: Integer;
  entry: PTableEntry;
begin
  for i := 0 to from.FCapacity - 1 do
  begin
    entry := from.FEntries + i;
    if entry^.key <> nil then
      tableSet(entry^.key, entry^.value);
  end;
end;

end.

