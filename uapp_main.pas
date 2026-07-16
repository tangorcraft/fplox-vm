unit uapp_main;

{$mode objfpc}{$H+}
{$i plox/defines.inc}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Menus,
  lox_main;

type

  { TFMain }

  TFMain = class(TForm)
    BRunLox: TButton;
    BClearConsole: TButton;
    BRunPause: TButton;
    BRunStop: TButton;
    cbDebugPrintCode: TCheckBox;
    cbDebugTraceExecution: TCheckBox;
    GroupBoxDebug: TGroupBox;
    MainMenu: TMainMenu;
    MemoLox: TMemo;
    MemoConsole: TMemo;
    miTest: TMenuItem;
    PanelMiddle: TPanel;
    Splitter1: TSplitter;
    procedure BClearConsoleClick(Sender: TObject);
    procedure BRunLoxClick(Sender: TObject);
    procedure BRunPauseClick(Sender: TObject);
    procedure BRunStopClick(Sender: TObject);
    procedure cbDebugPrintCodeChange(Sender: TObject);
    procedure cbDebugTraceExecutionChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FTests: TStringList;
    FLox: TLoxEngine;
    procedure menuTestClick(Sender: TObject);

    procedure lox_string(const S: string);

    procedure findTest(const path: string; const root: TMenuItem);
    procedure runUIState(const running: Boolean);
  public

  end;

var
  FMain: TFMain;

implementation

uses common;

{$R *.lfm}

{ TFMain }

procedure TFMain.FormCreate(Sender: TObject);
var
  test_path: string;
begin
  lox_output := @lox_string;
  lox_error := @lox_string;
  FLox := nil;

  {$ifndef DEBUG}
  GroupBoxDebug.Enabled := False;
  GroupBoxDebug.Visible := False;
  {$else}
    {$ifndef DEBUG_PRINT_CODE}
    cbDebugPrintCode.Checked := false;
    cbDebugPrintCode.Enabled := false;
    {$endif}
    {$ifndef DEBUG_TRACE_EXECUTION}
    cbDebugTraceExecution.Checked := false;
    cbDebugTraceExecution.Enabled := false;
    {$endif}
    debugPrintCode := cbDebugPrintCode.Checked;
    debugTraceExecution := cbDebugTraceExecution.Checked;
  {$endif}

  FTests := TStringList.Create;
  test_path := ExtractFilePath(Application.ExeName) + 'test';
  if DirectoryExists(test_path) then
  begin
    // recursive find all *.lox files in test directory and create menu items in Test main menu
    // clicking submenu item will load corresponding test file
    findTest(test_path + '\', miTest);
  end;
end;

procedure TFMain.BRunLoxClick(Sender: TObject);
var
  ret: integer;
begin
  MemoConsole.Lines.Add('Lox Interpreter started');
  runUIState(true);
  Application.ProcessMessages;
  FLox := TLoxEngine.Create();
  try
    ret := FLox.Execute(MemoLox.Text);
  finally
    FLox.Free;
    FLox := nil;
    runUIState(false);
  end;
  MemoConsole.Lines.Add('Lox Interpreter finished execution with code %d',[ret]);
end;

procedure TFMain.BRunPauseClick(Sender: TObject);
begin
  if Assigned(FLox) then
  begin
    if FLox.LoxVM.is_paused then
      FLox.LoxVM.pause(nil)
    else
      FLox.LoxVM.pause(@Application.ProcessMessages);
  end;
end;

procedure TFMain.BRunStopClick(Sender: TObject);
begin
  if Assigned(FLox) then
    FLox.LoxVM.stop;
end;

procedure TFMain.cbDebugPrintCodeChange(Sender: TObject);
begin
  {$ifdef DEBUG}
  debugPrintCode := cbDebugPrintCode.Checked;
  {$endif}
end;

procedure TFMain.cbDebugTraceExecutionChange(Sender: TObject);
begin
  {$ifdef DEBUG}
  debugTraceExecution := cbDebugTraceExecution.Checked;
  {$endif}
end;

procedure TFMain.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if Assigned(FLox) and FLox.LoxVM.is_paused then
    FLox.LoxVM.stop;
end;

procedure TFMain.BClearConsoleClick(Sender: TObject);
begin
  MemoConsole.Lines.Clear;
  MemoConsole.Lines.Add('Output console');
end;

procedure TFMain.FormDestroy(Sender: TObject);
begin
  FTests.Free;

  lox_output := nil;
  lox_error := nil;
end;

procedure TFMain.menuTestClick(Sender: TObject);
var
  fn: string;
begin
  fn := FTests[(Sender as TMenuItem).Tag];
  if FileExists(fn) then
    MemoLox.Lines.LoadFromFile(fn);
end;

procedure TFMain.lox_string(const S: string);
begin
  MemoConsole.Lines.Add(S);
  Application.ProcessMessages;
end;

procedure TFMain.findTest(const path: string; const root: TMenuItem);
var
  sr: TSearchRec;
  idx: Integer;
  mi: TMenuItem;
begin
  if FindFirst(Path+'*', faDirectory, sr) = 0 then
  repeat
    if ((sr.Attr and faDirectory) <> 0)
    and (sr.Name <> '.')
    and (sr.Name <> '..') then
    begin
      mi := TMenuItem.Create(Self);
      mi.Caption := sr.Name;
      root.Add(mi);
      findTest(Path + sr.Name + '\', mi);
    end;
  until FindNext(sr) <> 0;
  FindClose(sr);

  if FindFirst(Path+'*.lox', faAnyFile, sr) = 0 then
  repeat
    if ((sr.Attr and faDirectory) = 0) then
    begin
      idx := FTests.Add(Path + sr.Name);
      mi := TMenuItem.Create(Self);
      mi.Caption := sr.Name;
      mi.Tag := idx;
      mi.OnClick := @menuTestClick;
      root.Add(mi);
    end;
  until FindNext(sr) <> 0;
  FindClose(sr);
end;

procedure TFMain.runUIState(const running: Boolean);
begin
  MemoLox.Enabled := not running;
  BClearConsole.Enabled := not running;
  BRunLox.Enabled := not running;
  BRunPause.Enabled := running;
  BRunStop.Enabled := running;
end;

end.

