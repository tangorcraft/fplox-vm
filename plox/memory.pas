unit memory;

{$mode ObjFPC}{$H+}
{$i defines.inc}

interface

uses
  Classes, SysUtils, common;

function GROW_CAPACITY(const old: Integer): Integer;

type

  { TMemoryManager }

  TMemoryManager = class
  private
    procedure collectGarbage();
    function reallocate(P: Pointer; const old_size: SizeInt; const new_size: SizeInt): Pointer;
  protected
    collectGarbageProc: TProcedureMethod;
    bytesAllocated: SizeUInt;
    nextGC: SizeUInt;
  public
    constructor Create;

    function GROW_ARRAY(const arr: Pointer; const old_count: integer; const new_count: integer; const size: SizeInt): Pointer;
    function ALLOC_AND_ZERO_ARRAY(const new_count: integer; const size: SizeInt): Pointer;
    procedure FREE_ARRAY(const arr: Pointer; const count: Integer; const size: SizeInt);
    function ALLOCATE(const size: SizeInt): Pointer;
    procedure FREE_(const P: Pointer; const size: SizeInt);
  end;

  { TMemArray }

  TMemArray = class
  private
    MM: TMemoryManager;

    FMem: Pointer;
    FSize: Integer;
  protected
    procedure Init(const ItemSize: Integer);
    function Grow: Pointer;
  public
    count: Integer;
    capacity: Integer;

    constructor Create(const mgr: TMemoryManager);
    destructor Destroy; override;
  end;

implementation

const
  MaxWord = $FFFF;
  GC_HEAP_GROW = $7FFF0;

function GROW_CAPACITY(const old: Integer): Integer;
begin
  if old < 8 then
    Result := old + 8
  else if old > MaxWord then
    Result := old + MaxWord
  else
    Result := old * 2;
end;

{ TMemoryManager }

procedure TMemoryManager.collectGarbage();
{$ifdef DEBUG_LOG_GC}
var
  before: SizeUInt;
{$endif}
begin
  {$ifdef DEBUG_LOG_GC}
  before := bytesAllocated;
  {$endif}

  if Assigned(collectGarbageProc) then
    collectGarbageProc();

  if bytesAllocated < GC_HEAP_GROW then
    nextGC := bytesAllocated * 2
  else
    nextGC := bytesAllocated + GC_HEAP_GROW;

  {$ifdef DEBUG_LOG_GC}
  if debugLogGC then
    printf('   collected %u bytes (from %u to %u) next at %u'+NL,
               [before - bytesAllocated, before, bytesAllocated, nextGC], true);
  {$endif}
end;

function TMemoryManager.reallocate(P: Pointer; const old_size: SizeInt; const new_size: SizeInt): Pointer;
begin
  bytesAllocated := bytesAllocated + (new_size - old_size);
  if new_size > old_size then
  begin
    {$ifdef DEBUG_STRESS_GC}
    if debugStressGC then
      collectGarbage()
    else
    {$endif}
    if bytesAllocated > nextGC then
    begin
      collectGarbage();
    end;
  end;
  if new_size = 0 then
  begin
    Result := nil;
    if P <> nil then
      Freemem(P, old_size);
    Exit;
  end;

  Result := ReAllocMem(P, new_size);
end;

constructor TMemoryManager.Create;
begin
  bytesAllocated := 0;
  nextGC := 1024 * 1024;
end;

function TMemoryManager.GROW_ARRAY(const arr: Pointer; const old_count: integer; const new_count: integer;
  const size: SizeInt): Pointer;
begin
  Result := reallocate(arr, old_count * size, new_count * size);
end;

function TMemoryManager.ALLOC_AND_ZERO_ARRAY(const new_count: integer; const size: SizeInt): Pointer;
begin
  Result := reallocate(nil, 0, new_count * size);
  FillByte(Result^, new_count * size, 0);
end;

procedure TMemoryManager.FREE_ARRAY(const arr: Pointer; const count: Integer; const size: SizeInt);
begin
  reallocate(arr, count * size, 0);
end;

function TMemoryManager.ALLOCATE(const size: SizeInt): Pointer;
begin
  Result := reallocate(nil, 0, size);
end;

procedure TMemoryManager.FREE_(const P: Pointer; const size: SizeInt);
begin
  reallocate(P, size, 0);
end;

{ TMemArray }

procedure TMemArray.Init(const ItemSize: Integer);
begin
  FSize := ItemSize;
  count := 0;
  capacity := 0;
  FMem := nil;
end;

function TMemArray.Grow: Pointer;
var
  old_capacity: Integer;
begin
  old_capacity := capacity;
  capacity := GROW_CAPACITY(old_capacity);
  FMem := MM.GROW_ARRAY(FMem, old_capacity, capacity, FSize);
  Result := FMem;
end;

constructor TMemArray.Create(const mgr: TMemoryManager);
begin
  MM := mgr;
end;

destructor TMemArray.Destroy;
begin
  MM.FREE_ARRAY(FMem, capacity, FSize);
  inherited Destroy;
end;

end.

