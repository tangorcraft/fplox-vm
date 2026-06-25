unit uapp_main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  lox_main;

type

  { TFMain }

  TFMain = class(TForm)
    BRunLox: TButton;
    BClearConsole: TButton;
    MemoLox: TMemo;
    MemoConsole: TMemo;
    PanelMiddle: TPanel;
    Splitter1: TSplitter;
    procedure BClearConsoleClick(Sender: TObject);
    procedure BRunLoxClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    procedure lox_string(const S: string);
  public

  end;

var
  FMain: TFMain;

implementation

uses common;

{$R *.lfm}

{ TFMain }

procedure TFMain.FormCreate(Sender: TObject);
begin
  lox_output := @lox_string;
end;

procedure TFMain.BRunLoxClick(Sender: TObject);
var
  lox: TLoxEngine;
  ret: integer;
begin
  lox := TLoxEngine.Create();
  MemoConsole.Lines.Add('Lox Interpreter started');
  try
    ret := lox.Execute(MemoLox.Text);
  finally
    lox.Free;
  end;
  MemoConsole.Lines.Add('Lox Interpreter finished execution with code %d',[ret]);
end;

procedure TFMain.BClearConsoleClick(Sender: TObject);
begin
  MemoConsole.Lines.Clear;
  MemoConsole.Lines.Add('Output console');
end;

procedure TFMain.FormDestroy(Sender: TObject);
begin
  lox_output := nil;
end;

procedure TFMain.lox_string(const S: string);
begin
  MemoConsole.Lines.Add(S);
end;

end.

