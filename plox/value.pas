unit value;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, memory, common;

type
  TValue = Double;
  PValue = ^TValue;

  { TValueArray }

  TValueArray = class(TMemArray)
  public
    values: PValue;

    constructor Create();

    procedure write(V: TValue);
  end;

procedure printValue(const V: TValue);

implementation

procedure printValue(const V: TValue);
begin
  printf('%g',[V]);
end;

{ TValueArray }

constructor TValueArray.Create();
begin
  Init(SizeOf(TValue));
  values := Grow;
end;

procedure TValueArray.write(V: TValue);
begin
  if capacity < (count + 1) then
    values := Grow;
  values[count] := V;
  inc(count);
end;

end.

