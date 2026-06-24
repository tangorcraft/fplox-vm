unit memory;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

function GROW_CAPACITY(const old: Integer): Integer;
function GROW_ARRAY(const arr: Pointer; const old_count: integer; const new_count: integer; const size: integer): Pointer;
procedure FREE_ARRAY(const arr: Pointer; const count: Integer; const size: Integer);

type

  { TMemArray }

  TMemArray = class
  private
    FMem: Pointer;
    FSize: Integer;
  protected
    procedure Init(const ItemSize: Integer);
    function Grow: Pointer;
  public
    count: Integer;
    capacity: Integer;

    destructor Destroy; override;
  end;

implementation

const
  MaxWord = $FFFF;

function reallocate(P: Pointer; const old_size: Integer; const new_size: Integer): Pointer;
begin
  if new_size = 0 then
  begin
    Result := nil;
    if P <> nil then
      Freemem(P, old_size);
    Exit;
  end;

  Result := ReAllocMem(P, new_size);
end;

function GROW_CAPACITY(const old: Integer): Integer;
begin
  if old < 8 then
    Result := old + 8
  else if old > MaxWord then
    Result := old + MaxWord
  else
    Result := old * 2;
end;

function GROW_ARRAY(const arr: Pointer; const old_count: integer;
  const new_count: integer; const size: integer): Pointer;
begin
  Result := reallocate(arr, old_count * size, new_count * size);
end;

procedure FREE_ARRAY(const arr: Pointer; const count: Integer;
  const size: Integer);
begin
  reallocate(arr, count * size, 0);
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
  FMem := GROW_ARRAY(FMem, old_capacity, capacity, FSize);
  Result := FMem;
end;

destructor TMemArray.Destroy;
begin
  FREE_ARRAY(FMem, capacity, FSize);
  inherited Destroy;
end;

end.

