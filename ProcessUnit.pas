unit ProcessUnit;

interface

uses
  Windows, Classes, Generics.Collections, Generics.Defaults, SysUtils,
  JwaNative, JwaNtStatus, JwaWinType;

type
  TWindowList = class;

  TProcess = class
  private
    FProcessInfo: TSystemProcesses;
    FProcessHandle: THandle;
    FWindowHandle: THandle;
    FName: String;
    FPid: DWORD;
    function GetWindowHandle: THandle;
    function GetProcessHandle: THandle;
  public
    constructor Create(const ProcessInfo: TSystemProcesses);
    destructor Destroy; override;
    property Name: String read FName;
    property Pid: DWORD read FPid;
    property ProcessHandle: THandle read GetProcessHandle;
    function Wait(const Timeout: DWORD): Boolean;
    property WindowHandle: THandle read GetWindowHandle;
  end;

  TProcessList = class(TObjectList<TProcess>)
  public
    function Exists(const Pid: DWORD): Boolean;
    function Find(const Pid: DWORD): TProcess; overload;
    function Find(const Name: string): TProcessList; overload;
    function FindFirst(const Name: string): TProcess;
    constructor Create(const AOwnsObjects: Boolean = True);
    procedure Sort; reintroduce;
  end;

  TWindow = class
  private
    FhWnd: THandle;
    function GetPid: DWORD;
    function GetCaption: String;
    function GetClassName: String;
    function GetVisible: Boolean;
    procedure SetVisible(const Value: Boolean);
  public
    constructor Create(const hWnd: THandle);
    property Caption: String read GetCaption;
    property _Class: String read GetClassName;
    property Handle: THandle read FhWnd;
    property Pid: DWORD read GetPid;
    procedure Show;
    procedure Hide;
    property Visible: Boolean read GetVisible write SetVisible;
  end;

  TWindowList = class(TObjectList<TWindow>)
  private
    type
      TWindowListAndProcess = record
        WindowList: TWindowList;
        Process: TProcess;
      end;
      PWindowListAndProcess = ^TWindowListAndProcess;
    var
      FProcessName: String;

    class function EnumWindowsProc(hWnd: THandle;
      EnumData: PWindowListAndProcess): BOOL; stdcall; static;
  public
    constructor Create(const hWnd: THandle = 0); overload;
    constructor Create(const ProcessName: String); overload;
    function FindByClass(const Value: String): TWindow;
    function FindByCaption(const Value: String): TWindow;
  end;

implementation

constructor TProcess.Create(const ProcessInfo: TSystemProcesses);
begin
  inherited Create;

  FProcessInfo := ProcessInfo;
  FProcessHandle := 0;
  FWindowHandle := 0;
  FName := ProcessInfo.ProcessName.Buffer;
  FPid := ProcessInfo.ProcessId;
end;

destructor TProcess.Destroy;
begin
  inherited Destroy;
end;

function EnumProcessWindowsProc(hWnd: THandle; lParam: LPARAM): BOOL; stdcall;
var
  dwPid: DWORD;
  Process: TProcess absolute lParam;
  dwThreadId: DWORD;
begin
  dwThreadId := GetWindowThreadProcessId(hWnd, dwPid);
  if dwPid = Process.Pid then
  begin
    Process.FWindowHandle := hWnd;
    Exit(False);
  end;

  Result := True;
end;

function TProcess.GetProcessHandle: THandle;
begin
  if FProcessHandle = 0 then
    FProcessHandle := OpenProcess(MAXIMUM_ALLOWED, False, FPid);

  Result := FProcessHandle;
end;

function TProcess.GetWindowHandle: THandle;
begin
  if FWindowHandle = 0 then
    EnumWindows(@EnumProcessWindowsProc, LPARAM(Self));

  Result := FWindowHandle;
end;

function TProcess.Wait(const Timeout: DWORD): Boolean;
var
  dwResult: DWORD;
begin
  dwResult := WaitForSingleObject(ProcessHandle, TimeOut);
  Result := dwResult = WAIT_OBJECT_0;
end;

{ TProcessList }

constructor TProcessList.Create(const AOwnsObjects: Boolean = True);
var
  Current: PSystemProcesses;
  SystemProcesses : PSystemProcesses;
  dwSize: DWORD;
  nts: NTSTATUS;
begin
  inherited Create(AOwnsObjects);

  dwSize := 200000;
  SystemProcesses := AllocMem(dwSize);

  nts := NtQuerySystemInformation(SystemProcessesAndThreadsInformation,
      SystemProcesses, dwSize, @dwSize);

  while nts = STATUS_INFO_LENGTH_MISMATCH do
  begin
    ReAllocMem(SystemProcesses, dwSize);
    nts := NtQuerySystemInformation(SystemProcessesAndThreadsInformation,
      SystemProcesses, dwSize, @dwSize);
  end;

  if nts = STATUS_SUCCESS then
  begin
    Current := SystemProcesses;
    while True do
    begin
      Self.Add(TProcess.Create(Current^));
      if Current^.NextEntryDelta = 0 then
        Break;

      Current := PSYSTEM_PROCESSES(DWORD_PTR(Current) + Current^.NextEntryDelta);
    end;
  end;

  FreeMem(SystemProcesses);
end;

function TProcessList.Exists(const Pid: DWORD): Boolean;
var
  i: Integer;
begin
  Result := False;

  for i := 0 to Self.Count - 1 do
  begin
    Result := Self.Items[i].Pid = Pid;
    if Result then
      Break;
  end;
end;

function TProcessList.FindFirst(const Name: string): TProcess;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
  begin
    if CompareText(Name, Items[i].Name) = 0 then
    begin
      Result := Items[i];
      Exit;
    end;
  end;

  Result := nil;
end;

function TProcessList.Find(const Name: string): TProcessList;
var
  i: Integer;
begin
  Result := TProcessList.Create;
  for i := 0 to Count - 1 do
  begin
    if CompareText(Name, Items[i].Name) = 0 then
    begin
      Result.Add(TProcess.Create(Items[i].FProcessInfo));
    end;
  end;
end;

function TProcessList.Find(const Pid: DWORD): TProcess;
var
  i: Integer;
begin
  Result := nil;

  for i := 0 to Self.Count - 1 do
  begin
    if Self.Items[i].Pid = Pid then
    begin
      Result := Self.Items[i];
      Break;
    end;
  end;
end;

procedure TProcessList.Sort;
begin
  inherited Sort(TComparer<TProcess>.Construct(
    function(const L, R: TProcess): Integer
    begin
      //less than 0 if S1 is less than S2, 0 if S1 equals S2, or greater than 0 if S1 is greater than S2.
      Result := L.Pid - R.Pid;
    end));
end;


{ TWindowList }
function EnumWindowsWindowsProc(hWnd: THandle; lParam: LPARAM): BOOL; stdcall;
var
  Windows: TWindowList absolute lParam;
begin
  Windows.Add(TWindow.Create(hWnd));
  Result := True;
end;

constructor TWindowList.Create(const hWnd: THandle);
var
  bRes: Boolean;
begin
  inherited Create;
  bRes := EnumChildWindows(hWnd, @EnumWindowsWindowsProc, LPARAM(Self));
  if not bRes then
    OutputDebugString('bla');
end;

constructor TWindowList.Create(const ProcessName: String);
var
  EnumData: TWindowListAndProcess;
  ProcessList: TProcessList;
  Process: TProcess;
begin
  FProcessName := ProcessName;
  ProcessList := TProcessList.Create;
  try
    Process := ProcessList.FindFirst(ProcessName);
    if not Assigned(Process) then
      Exit;

    EnumData.WindowList := Self;
    EnumData.Process := Process;
    EnumWindows(@TWindowList.EnumWindowsProc, LPARAM(@EnumData));

  finally
    ProcessList.Free;
  end;
end;

class function TWindowList.EnumWindowsProc(hWnd: THandle;
  EnumData: PWindowListAndProcess): BOOL; stdcall;
var
  dwPid: DWORD;
begin
  GetWindowThreadProcessId(hWnd, dwPid);
  if dwPid = EnumData^.Process.Pid then
    EnumData^.WindowList.Add(TWindow.Create(hWnd));

  Result := True;
end;

function TWindowList.FindByCaption(const Value: String): TWindow;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
  begin
    if CompareText(Value, Items[i].Caption) = 0 then
    begin
      Result := Items[i];
      Exit;
    end;
  end;

  Result := nil;
end;

function TWindowList.FindByClass(const Value: String): TWindow;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do
  begin
    if CompareText(Value, Items[i]._Class) = 0 then
    begin
      Result := Items[i];
      Exit;
    end;
  end;

  Result := nil;
end;

{ TWindow }

constructor TWindow.Create(const hWnd: THandle);
begin
  FhWnd := hWnd;
end;

function TWindow.GetCaption: String;
begin
  SetLength(Result, MAX_PATH);
  SetLength(Result, GetWindowText(FhWnd, PChar(Result), Length(Result)));
end;

function TWindow.GetClassName: String;
begin
  SetLength(Result, MAX_PATH);
  SetLength(Result, Windows.GetClassName(FhWnd, PChar(Result), Length(Result)));
end;

function TWindow.GetPid: DWORD;
begin
  GetWindowThreadProcessId(FhWnd, Result);
end;

function TWindow.GetVisible: Boolean;
begin
  Result := IsWindowVisible(FhWnd);

end;

procedure TWindow.Hide;
begin
  ShowWindow(FhWnd, SW_HIDE);
end;

procedure TWindow.SetVisible(const Value: Boolean);
begin
  if Value then
    Show
  else
    Hide;
end;

procedure TWindow.Show;
begin
  ShowWindow(FhWnd, SW_SHOW);
end;

end.
