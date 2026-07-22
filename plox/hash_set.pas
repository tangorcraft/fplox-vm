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
    mem: TMemoryManager;
    FList: PKeyEntry;
    FCapacity: Cardinal;
    FLinkCount: Cardinal; // number of separate linked list entries
    FGrowThreshold: Cardinal;

    FOldList: PKeyEntry;
    FOldCapacity: Cardinal;

    function tableFindKey(const chars: PChar; const len: Integer; const hash: uint32;
      out entry: PKeyEntry): Boolean;
    procedure grow();
    function newNext(var next: PKeyEntry): PKeyEntry;
    function tableGetEntry(const chars: PChar; const len: Integer): PKeyEntry;
    procedure freeLinkedList(var top: PKeyEntry);
  public
    constructor Create(const mgr: TMemoryManager);
    destructor Destroy; override;

    procedure tableRemoveWhite(const List: PKeyEntry; const Capacity: Cardinal);
  end;

  { TObjectManager_SI: String Interning}

  TObjectManager_SI = class(TObjectManager)
  private
    FHashSet: TKeyTable;
  public
    constructor Create;
    destructor Destroy; override;

    procedure sweepStringInternTable;

    // hiding methods of the parent class
    function takeString(const chars: PChar; const len: Integer): PObjString;
    function copyString(const start: PChar; const len: Integer): PObjString;
  end;

implementation

const
  entrySize = SizeOf(TKeyEntry);
  HASHSET_MAX_LOAD = 1.4; // LinkCount to Capacity ratio

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
  i: Integer;
  bin: PKeyEntry;
  iter_entry: PKeyEntry;

  function insertFromBin(var next: PKeyEntry): PKeyEntry;
  begin
    Result := bin;
    bin := bin^.next;
    Result^.next := next;
    next := Result;
  end;

  procedure copyListEntry(const copy_entry: TKeyEntry);
  var
    idx: Integer;
    target_entry: PKeyEntry;
  begin
    idx := copy_entry.hash mod FCapacity;
    target_entry := FList + idx;
    if target_entry^.key <> nil then
    begin // collision, take linked entry from bin
      target_entry := insertFromBin(target_entry^.next);
    end;
    target_entry^.key := copy_entry.key;
    target_entry^.hash := copy_entry.hash;
  end;

  function moveLinkedEntry(const entry: PKeyEntry): PKeyEntry;
  var
    idx: Integer;
    target_entry: PKeyEntry;
  begin
    Result := entry^.next;
    idx := entry^.hash mod FCapacity;
    target_entry := FList + idx;
    if target_entry^.key <> nil then
    begin // collision, simply insert entry into the new linked list
      entry^.next := target_entry^.next;
      target_entry^.next := entry;
      Exit;
    end;
    // copy entry into new list
    target_entry^.key := entry^.key;
    target_entry^.hash := entry^.hash;
    // move entry to the bin
    entry^.next := bin;
    bin := entry;
  end;

begin
  FOldList := FList;
  FOldCapacity := FCapacity;
  FCapacity := GROW_CAPACITY(FOldCapacity + FLinkCount);
  FList := nil;
  FList := mem.ALLOC_AND_ZERO_ARRAY(FCapacity, entrySize);

  bin := nil;
  // when separately allocated key entry is copied
  // it will be moved to bin, a linked list, instead of being freed
  // if new collisions occur, entries from bin will be used instead of allocating new entry
  // with GC added, avoiding new allocations also avoids potential GC runs
  // need to be very careful with this routine since GC run can remove items with tableRemoveWhite()
  for i := 0 to FOldCapacity - 1 do
  begin
    iter_entry := FOldList + i;
    // moving a list don't allocate any new entry, GC safe
    with iter_entry^ do
      while next <> nil do
        next := moveLinkedEntry(next);
    // make sure bin is not empty to prevent allocation (and possible GC run) during copyListEntry
    if bin = nil then
      newNext(bin);
    copyListEntry(iter_entry^);
  end;
  mem.FREE_ARRAY(FOldList, FOldCapacity, entrySize);
  FOldList := nil;
  FOldCapacity := 0;
  FGrowThreshold := Trunc(FCapacity * HASHSET_MAX_LOAD);
  freeLinkedList(bin);
end;

function TKeyTable.newNext(var next: PKeyEntry): PKeyEntry;
begin
  inc(FLinkCount);
  Result := mem.ALLOCATE(entrySize);
  Result^.next := next;
  Result^.key := nil;
  next := Result;
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
      Result := newNext(Result^.next);
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
    mem.FREE_(top, entrySize);
    top := next;
    dec(FLinkCount);
  end;
end;

constructor TKeyTable.Create(const mgr: TMemoryManager);
begin
  mem := mgr;
  FLinkCount := 0;
  FCapacity := 0;
  FList := nil;
  FOldCapacity := 0;
  FOldList := nil;
  grow();
end;

destructor TKeyTable.Destroy;
var
  i: Cardinal;
begin
  // hash set does not own any objects, so we only need to free memory for the key entries
  for i := 0 to FCapacity - 1 do
    freeLinkedList(FList[i].next);
  mem.FREE_ARRAY(FList, FCapacity, entrySize);
  inherited Destroy;
end;

procedure TKeyTable.tableRemoveWhite(const List: PKeyEntry; const Capacity: Cardinal);
var
  i: integer;
  prev, entry, white, bin: PKeyEntry;

begin
  if List = nil then
    Exit;
  bin := nil; // linked list of entries to be freed
  for i := 0 to Capacity - 1 do
  begin
    prev := nil;
    entry := List + i;
    while entry <> nil do
    begin
      if (entry^.key <> nil) and (not entry^.key^.obj.isMarked) then
      begin // found white
        if prev = nil then // entry on the main array
        begin
          if entry^.next = nil then
          begin
            entry^.key := nil; // no next, just nil the key
            Break; // exit while loop
          end
          else
          begin
            // there is next entry in linked list
            // copy it into main array
            white := entry^.next;
            entry^ := white^;
            // and move it to to-be-freed list
            white^.next := bin;
            bin := white;
            // I could've reused prev vairable here, but this looks more readable
          end;
        end
        else
        begin // entry is in linked list
          // extract entry from linked list
          prev^.next := entry^.next;
          // and put it into to-be-freed list
          entry^.next := bin;
          bin := entry;
          // point entry back to linked list
          entry := prev^.next;
        end;
      end
      else
      begin // entry is empty or marked, go to next
        prev := entry;
        entry := entry^.next;
      end;
    end;
  end;
  freeLinkedList(bin);
end;

{ TObjectManager_SI }

constructor TObjectManager_SI.Create;
begin
  inherited Create;
  FHashSet := TKeyTable.Create(Self);
  sweepStringInternProc := @sweepStringInternTable;
end;

destructor TObjectManager_SI.Destroy;
begin
  sweepStringInternProc := nil;
  FHashSet.Free;
  inherited Destroy;
end;

procedure TObjectManager_SI.sweepStringInternTable;
begin
  FHashSet.tableRemoveWhite(FHashSet.FList, FHashSet.FCapacity);
  FHashSet.tableRemoveWhite(FHashSet.FOldList, FHashSet.FOldCapacity);
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
    Result := inherited takeString(chars, len, entry^.hash);
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
    Result := inherited copyString(start, len, entry^.hash);
    entry^.key := Result;
  end;
end;

end.

