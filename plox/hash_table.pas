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
    FTombstoneCount: Integer;
    FCapacity: Integer;

    FGrowThreshold: Integer;
    FShrinkThreshold: Integer;
    FTombstoneThreshold: Integer;

    FProbeStep: Integer;
    FEntries: PTableEntry;

    MM: TObjectManager_SI;

    procedure ClearTombstones();
    procedure AdjustCapacity(const new_capacity: Integer);
    function findEntry(const key: PObjString): PTableEntry;
  public
    constructor Create(const objMgr: TObjectManager_SI);
    destructor Destroy; override;

    function tableGet(const key: PObjString; out V: TValue): Boolean;
    function tableFind(const key: PObjString): Boolean;
    function tableSet(const key: PObjString; const V: TValue;
      const mustExist: Boolean = false): Boolean;
    function tableDelete(const key: PObjString): Boolean;
    procedure tableAddAll(const from: THashTable);

    procedure markTable();
    {$ifdef DEBUG_HASH_TABLE}
    procedure printTable(const printEmpty: boolean);
    {$endif}
  end;

implementation

{$ifdef DEBUG_HASH_TABLE}
uses
  common;
{$endif}

const
  entrySize = SizeOf(TTableEntry);

  HT_MAX_LOAD = 0.7;
  HT_MIN_LOAD = 0.3;
  HT_MIN_CAPACITY = 10;

  HT_TOMBSTONE_LOAD = 0.2;
  HT_SHRINK_FACTOR = 1.4;

  HT_PROBE_GROW_BASE = 32;
  HT_PROBE_GROW_FACTOR = 2;

type
  TTableValues = record
    Entries: PTableEntry;
    Capacity: Integer;
    GrowThreshold: Integer;
    ShrinkThreshold: Integer;
    TombstoneThreshold: Integer;
    ProbeStep: Integer;
  end;

procedure NewTableValues(const MM: TMemoryManager; const new_capacity: Integer; out Values: TTableValues);
var
  probe_grow: Integer;
  {$ifdef NAN_BOXING}
  i: integer;
  {$endif}
begin
  Values.Capacity := new_capacity or 1; // let new capacity be odd
  Values.ProbeStep := 1; // linear probe at low capacity
  probe_grow := Values.Capacity div HT_PROBE_GROW_BASE;
  while probe_grow > 0 do
  begin
    probe_grow := probe_grow div HT_PROBE_GROW_FACTOR;
    Inc(Values.ProbeStep);
  end;
  if (Values.ProbeStep mod 2) = 1 then // probe step is odd, make odd capacity even
    inc(Values.Capacity);

  // zeroing memory will set value type to VAL_NIL, which is defined as = 0
  Values.Entries := MM.ALLOC_AND_ZERO_ARRAY(Values.Capacity, entrySize);
  {$ifdef NAN_BOXING}
  for i := 0 to Values.Capacity - 1 do
    Values.Entries[i].value := NIL_VAL;
  {$endif}

  Values.GrowThreshold := Trunc(Values.Capacity * HT_MAX_LOAD);
  Values.TombstoneThreshold := Trunc(Values.Capacity * HT_TOMBSTONE_LOAD);
  if Values.Capacity < HT_MIN_CAPACITY then
    Values.ShrinkThreshold := 0
  else
    Values.ShrinkThreshold := Trunc(Values.Capacity * HT_MIN_LOAD);
end;

procedure putEntry(const dest: TTableValues; const source: TTableEntry);
var
  idx: integer;
  destEntry: PTableEntry;
begin
  idx := source.key^.hash mod dest.Capacity;
  while true do
  begin
    destEntry := dest.Entries + idx;
    if (destEntry^.key = source.key) or (destEntry^.key = nil) then
    begin
      destEntry^ := source;
      Exit;
    end;
    idx := (idx + dest.ProbeStep) mod dest.Capacity;
  end;
end;

{ THashTable }

procedure THashTable.ClearTombstones();
var
  i, idx: Integer;
  iter, dest: PTableEntry;
begin
  if (FCount - FTombstoneCount) < FShrinkThreshold then
  begin
    AdjustCapacity(Trunc((FCount - FTombstoneCount) * HT_SHRINK_FACTOR));
    Exit; // size change = rehash = tombstone clear
  end;

  for i := 0 to FCapacity - 1 do
  begin
    iter := FEntries + i;
    if iter^.key = nil then // empty or tombstone
    begin
      if not (iter^.value IS_NIL_VAL) then // tombstone
      begin
        iter^.value := NIL_VAL; // make it empty
        Dec(FCount);
        Dec(FTombstoneCount);
      end;
    end
    else begin
      idx := Integer(iter^.key^.hash) mod FCapacity;
      while idx <> i do // entry not at desired place
      begin
        dest := FEntries + idx;
        if dest^.key = nil then // desired position is empty
        begin
          if not (dest^.value IS_NIL_VAL) then // tombstone
          begin
            Dec(FCount);
            Dec(FTombstoneCount);
          end;
          dest^ := iter^;
          iter^.key := nil;
          iter^.value := NIL_VAL;
          Break;
        end;
        inc(idx, FProbeStep);
      end;
    end;
  end;
  {$ifdef DEBUG_HASH_TABLE}
  if FTombstoneCount <> 0 then
    printf('HT Error: TombstoneCount not zero after clear: %d <> 0',[FTombstoneCount], true);
  {$endif}
end;

procedure THashTable.AdjustCapacity(const new_capacity: Integer);
var
  i: Integer;
  new_table: TTableValues;
  source: PTableEntry;
begin
  if new_capacity <= 0 then
  begin
    {$ifdef DEBUG_HASH_TABLE}
    printf('HT Error: AdjustCapacity called with invalid size: %d <= 0',[new_capacity], true);
    {$endif}
    Exit;
  end;

  NewTableValues(MM, new_capacity, new_table);

  FTombstoneCount := 0;
  FCount := 0;
  for i := 0 to FCapacity - 1 do
  begin
    source := FEntries + i;
    if source^.key = nil then Continue;
    putEntry(new_table, source^);
    inc(FCount);
  end;
  MM.FREE_ARRAY(FEntries, FCapacity, entrySize);
  FEntries := new_table.Entries;
  FCapacity := new_table.Capacity;
  FProbeStep := new_table.ProbeStep;
  FGrowThreshold := new_table.GrowThreshold;
  FShrinkThreshold := new_table.ShrinkThreshold;
  FTombstoneThreshold := new_table.TombstoneThreshold;
end;

function THashTable.findEntry(const key: PObjString): PTableEntry;
var
  idx: integer;
  tombstone: PTableEntry;
begin
  idx := key^.hash mod FCapacity;
  tombstone := nil;
  while true do
  begin
    Result := FEntries + idx;
    if Result^.key = key then
      Exit
    else if Result^.key = nil then
    begin
      if (Result^.value IS_NIL_VAL) then
      begin
        // empty entry return tombstone if it's not nil
        if tombstone <> nil then
          Exit(tombstone);
        Exit;
      end
      else begin
        // found tombstone
        if tombstone = nil then
          tombstone := Result;
      end;
    end;
    idx := (idx + FProbeStep) mod FCapacity;
  end;
end;

constructor THashTable.Create(const objMgr: TObjectManager_SI);
begin
  MM := objMgr;
  FCount := 0;
  FCapacity := 0;
  FGrowThreshold := 0;
  FShrinkThreshold := 0;
  FTombstoneCount := 0;
  FTombstoneThreshold := 0;
  FProbeStep := 1;
  FEntries := nil;
end;

destructor THashTable.Destroy;
begin
  MM.FREE_ARRAY(FEntries, FCapacity, entrySize);
  inherited Destroy;
end;

function THashTable.tableGet(const key: PObjString; out V: TValue): Boolean;
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

function THashTable.tableFind(const key: PObjString): Boolean;
begin
  if FCount = 0 then
    Exit(false);

  if findEntry(key)^.key = nil then
    Exit(false);

  Result := True;
end;

function THashTable.tableSet(const key: PObjString; const V: TValue;
  const mustExist: Boolean): Boolean;
var
  entry: PTableEntry;
begin
  if (FCount + 1) > FGrowThreshold then
    AdjustCapacity(GROW_CAPACITY(FCapacity));

  entry := findEntry(key);
  Result := entry^.key = nil; // isNewKey
  if Result then
  begin
    // if mustExist and key is new we return True, but no actual assigment happens
    // maybe I should change the meaning of this function return value
    if mustExist then
      Exit;
    if (entry^.value IS_NIL_VAL) then
      inc(FCount) // new entry is not a tombstone
    else
      dec(FTombstoneCount);
    entry^.key := key;
  end;
  entry^.value := V;
end;

function THashTable.tableDelete(const key: PObjString): Boolean;
var
  entry: PTableEntry;
begin
  if FCount = 0 then
    Exit(false);

  entry := findEntry(key);
  if entry^.key = nil then
    Exit(false);

  // tombstone, an entry with key = nil, but value type not = VAL_NIL
  entry^.key := nil;
  {$ifdef NAN_BOXING}
  entry^.value := QNAN;
  {$else}
  entry^.value.type_ := VAL_Invalid;
  {$endif}
  inc(FTombstoneCount);
  Result := True;
  if FTombstoneCount > FTombstoneThreshold then
    ClearTombstones();
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

procedure THashTable.markTable();
var
  i: Integer;
  entry: PTableEntry;
begin
  for i := 0 to FCapacity - 1 do
  begin
    entry := FEntries + i;
    MM.markObject(PLoxObj(entry^.key));
    MM.markValue(entry^.value);
  end;
end;

{$ifdef DEBUG_HASH_TABLE}
procedure THashTable.printTable(const printEmpty: boolean);
var
  i: Integer;
  entry: PTableEntry;
begin
  printf( 'capacity: %d'+NL
         +'count: %d'+NL
         +'tomb count: %d'+NL, [FCapacity, FCount, FTombstoneCount], true);
  for i := 0 to FCapacity - 1 do
  begin
    entry := FEntries + i;
    if entry^.key <> nil then
    begin
      printf('key[%3d] ', [i], true);
      printValue(OBJ_VAL(entry^.key), true);
      print(' = ', true);
      printValue(entry^.value, true);
      print(NL, true);
    end
    else if printEmpty then
      printf('key[%3d] is empty'+NL, [i], true);
  end;
end;
{$endif}

end.

