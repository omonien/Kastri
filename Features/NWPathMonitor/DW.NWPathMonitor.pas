unit DW.NWPathMonitor;

{*******************************************************}
{                                                       }
{                      Kastri                           }
{                                                       }
{         Delphi Worlds Cross-Platform Library          }
{                                                       }
{  Copyright 2020-2026 Dave Nottage under MIT license   }
{  which is located in the root folder of this library  }
{                                                       }
{*******************************************************}

// Wrapper for nw_path_monitor (Network framework) on iOS.
// On other platforms the monitor reports IsSupported = False and Start does nothing.

interface

{$SCOPEDENUMS ON}

const
  // Raw values of nw_path_status_t
  cNWPathStatusInvalid = 0;
  cNWPathStatusSatisfied = 1;
  cNWPathStatusUnsatisfied = 2;
  cNWPathStatusSatisfiable = 3;
  // Raw values of nw_interface_type_t
  cNWInterfaceTypeOther = 0;
  cNWInterfaceTypeWiFi = 1;
  cNWInterfaceTypeCellular = 2;
  cNWInterfaceTypeWired = 3;
  cNWInterfaceTypeLoopback = 4;

type
  TNWPathStatus = (Invalid, Satisfied, Unsatisfied, Satisfiable);

  TNWInterfaceType = (Other, WiFi, Cellular, Wired, Loopback);

  TNWInterfaceTypes = set of TNWInterfaceType;

  TNWPath = record
    HasDNS: Boolean;
    HasIPv4: Boolean;
    HasIPv6: Boolean;
    InterfaceTypes: TNWInterfaceTypes;
    IsConstrained: Boolean;
    IsExpensive: Boolean;
    Status: TNWPathStatus;
    class function Empty: TNWPath; static;
    /// <summary>
    ///   True when the path status is Satisfied
    /// </summary>
    function IsConnected: Boolean;
    function IsEqual(const APath: TNWPath): Boolean;
    /// <summary>
    ///   Most relevant interface type of the path, in the order WiFi, Wired, Cellular, Other, Loopback
    /// </summary>
    function PrimaryInterfaceType: TNWInterfaceType;
    function ToString: string;
  end;

  TNWPathChangedEvent = procedure(Sender: TObject; const APath: TNWPath) of object;

  TNWPathMonitor = class;

  /// <summary>
  ///   Base class for platform implementations. Platform code calls PathChanged from any thread.
  /// </summary>
  TCustomPlatformNWPathMonitor = class(TObject)
  private
    FMonitor: TNWPathMonitor;
  protected
    procedure DoStart; virtual;
    procedure DoStop; virtual;
    function GetIsSupported: Boolean; virtual;
    procedure PathChanged(const APath: TNWPath);
  public
    constructor Create(const AMonitor: TNWPathMonitor); virtual;
    destructor Destroy; override;
    procedure Detach;
    property IsSupported: Boolean read GetIsSupported;
  end;

  TCustomPlatformNWPathMonitorClass = class of TCustomPlatformNWPathMonitor;

  TNWPathMonitor = class(TObject)
  private
    FAliveToken: IInterface;
    FIsMonitoring: Boolean;
    FLock: TObject;
    FPath: TNWPath;
    FPlatformMonitor: TCustomPlatformNWPathMonitor;
    FSynchronizeEvents: Boolean;
    FOnPathChanged: TNWPathChangedEvent;
    function GetIsSupported: Boolean;
    function GetPath: TNWPath;
  protected
    procedure DoPathChanged(const APath: TNWPath);
    procedure HandlePlatformPath(const APath: TNWPath);
  public
    /// <summary>
    ///   Creates the monitor with the platform implementation
    /// </summary>
    constructor Create; overload;
    /// <summary>
    ///   Creates the monitor with a custom implementation, e.g. for tests
    /// </summary>
    constructor Create(const APlatformClass: TCustomPlatformNWPathMonitorClass); overload;
    destructor Destroy; override;
    procedure Start;
    procedure Stop;
    property IsMonitoring: Boolean read FIsMonitoring;
    property IsSupported: Boolean read GetIsSupported;
    /// <summary>
    ///   Last path reported by the system. Safe to read from any thread
    /// </summary>
    property Path: TNWPath read GetPath;
    /// <summary>
    ///   When True (default), OnPathChanged is called on the main thread via TThread.Queue.
    ///   When False, OnPathChanged is called on the thread of the system callback
    /// </summary>
    property SynchronizeEvents: Boolean read FSynchronizeEvents write FSynchronizeEvents;
    property OnPathChanged: TNWPathChangedEvent read FOnPathChanged write FOnPathChanged;
  end;

function NWPathStatusFromValue(const AValue: Cardinal): TNWPathStatus;
function NWInterfaceTypeFromValue(const AValue: Cardinal): TNWInterfaceType;
function NWInterfaceTypeToValue(const AType: TNWInterfaceType): Cardinal;

implementation

uses
  // RTL
  System.SysUtils, System.Classes
  {$IF Defined(IOS)}
  , DW.NWPathMonitor.iOS
  {$ENDIF};

type
  // Captured by queued events, so they can detect that the monitor was destroyed in the meantime
  TNWAliveToken = class(TInterfacedObject)
  private
    FIsAlive: Boolean;
  public
    constructor Create;
    property IsAlive: Boolean read FIsAlive write FIsAlive;
  end;

{ TNWAliveToken }

constructor TNWAliveToken.Create;
begin
  inherited Create;
  FIsAlive := True;
end;

function NWPathStatusFromValue(const AValue: Cardinal): TNWPathStatus;
begin
  case AValue of
    cNWPathStatusSatisfied:
      Result := TNWPathStatus.Satisfied;
    cNWPathStatusUnsatisfied:
      Result := TNWPathStatus.Unsatisfied;
    cNWPathStatusSatisfiable:
      Result := TNWPathStatus.Satisfiable;
  else
    Result := TNWPathStatus.Invalid;
  end;
end;

function NWInterfaceTypeFromValue(const AValue: Cardinal): TNWInterfaceType;
begin
  case AValue of
    cNWInterfaceTypeWiFi:
      Result := TNWInterfaceType.WiFi;
    cNWInterfaceTypeCellular:
      Result := TNWInterfaceType.Cellular;
    cNWInterfaceTypeWired:
      Result := TNWInterfaceType.Wired;
    cNWInterfaceTypeLoopback:
      Result := TNWInterfaceType.Loopback;
  else
    Result := TNWInterfaceType.Other;
  end;
end;

function NWInterfaceTypeToValue(const AType: TNWInterfaceType): Cardinal;
begin
  case AType of
    TNWInterfaceType.WiFi:
      Result := cNWInterfaceTypeWiFi;
    TNWInterfaceType.Cellular:
      Result := cNWInterfaceTypeCellular;
    TNWInterfaceType.Wired:
      Result := cNWInterfaceTypeWired;
    TNWInterfaceType.Loopback:
      Result := cNWInterfaceTypeLoopback;
  else
    Result := cNWInterfaceTypeOther;
  end;
end;

{ TNWPath }

class function TNWPath.Empty: TNWPath;
begin
  Result := Default(TNWPath);
  Result.Status := TNWPathStatus.Invalid;
end;

function TNWPath.IsConnected: Boolean;
begin
  Result := Status = TNWPathStatus.Satisfied;
end;

function TNWPath.IsEqual(const APath: TNWPath): Boolean;
begin
  Result := (Status = APath.Status) and (InterfaceTypes = APath.InterfaceTypes) and (IsExpensive = APath.IsExpensive) and
    (IsConstrained = APath.IsConstrained) and (HasIPv4 = APath.HasIPv4) and (HasIPv6 = APath.HasIPv6) and (HasDNS = APath.HasDNS);
end;

function TNWPath.PrimaryInterfaceType: TNWInterfaceType;
begin
  if TNWInterfaceType.WiFi in InterfaceTypes then
    Result := TNWInterfaceType.WiFi
  else if TNWInterfaceType.Wired in InterfaceTypes then
    Result := TNWInterfaceType.Wired
  else if TNWInterfaceType.Cellular in InterfaceTypes then
    Result := TNWInterfaceType.Cellular
  else if TNWInterfaceType.Loopback in InterfaceTypes then
  begin
    if TNWInterfaceType.Other in InterfaceTypes then
      Result := TNWInterfaceType.Other
    else
      Result := TNWInterfaceType.Loopback;
  end
  else
    Result := TNWInterfaceType.Other;
end;

function TNWPath.ToString: string;
const
  cStatusNames: array[TNWPathStatus] of string = ('Invalid', 'Satisfied', 'Unsatisfied', 'Satisfiable');
  cTypeNames: array[TNWInterfaceType] of string = ('Other', 'WiFi', 'Cellular', 'Wired', 'Loopback');
var
  LType: TNWInterfaceType;
  LTypes: string;
begin
  LTypes := '';
  for LType := Low(TNWInterfaceType) to High(TNWInterfaceType) do
  begin
    if LType in InterfaceTypes then
    begin
      if not LTypes.IsEmpty then
        LTypes := LTypes + ',';
      LTypes := LTypes + cTypeNames[LType];
    end;
  end;
  Result := Format('Status=%s Types=[%s] Expensive=%s Constrained=%s IPv4=%s IPv6=%s DNS=%s',
    [cStatusNames[Status], LTypes, BoolToStr(IsExpensive, True), BoolToStr(IsConstrained, True), BoolToStr(HasIPv4, True),
     BoolToStr(HasIPv6, True), BoolToStr(HasDNS, True)]);
end;

{ TCustomPlatformNWPathMonitor }

constructor TCustomPlatformNWPathMonitor.Create(const AMonitor: TNWPathMonitor);
begin
  inherited Create;
  FMonitor := AMonitor;
end;

destructor TCustomPlatformNWPathMonitor.Destroy;
begin
  Detach;
  inherited;
end;

procedure TCustomPlatformNWPathMonitor.Detach;
begin
  FMonitor := nil;
end;

procedure TCustomPlatformNWPathMonitor.DoStart;
begin
  // Platforms without support do nothing
end;

procedure TCustomPlatformNWPathMonitor.DoStop;
begin
  //
end;

function TCustomPlatformNWPathMonitor.GetIsSupported: Boolean;
begin
  Result := False;
end;

procedure TCustomPlatformNWPathMonitor.PathChanged(const APath: TNWPath);
begin
  if FMonitor <> nil then
    FMonitor.HandlePlatformPath(APath);
end;

{ TNWPathMonitor }

constructor TNWPathMonitor.Create;
begin
  {$IF Defined(IOS)}
  Create(TPlatformNWPathMonitor);
  {$ELSE}
  Create(TCustomPlatformNWPathMonitor);
  {$ENDIF}
end;

constructor TNWPathMonitor.Create(const APlatformClass: TCustomPlatformNWPathMonitorClass);
begin
  inherited Create;
  FAliveToken := TNWAliveToken.Create;
  FLock := TObject.Create;
  FPath := TNWPath.Empty;
  FSynchronizeEvents := True;
  FPlatformMonitor := APlatformClass.Create(Self);
end;

destructor TNWPathMonitor.Destroy;
begin
  Stop;
  TNWAliveToken(FAliveToken).IsAlive := False;
  FPlatformMonitor.Detach;
  FPlatformMonitor.Free;
  FLock.Free;
  inherited;
end;

procedure TNWPathMonitor.DoPathChanged(const APath: TNWPath);
begin
  if Assigned(FOnPathChanged) then
    FOnPathChanged(Self, APath);
end;

function TNWPathMonitor.GetIsSupported: Boolean;
begin
  Result := FPlatformMonitor.IsSupported;
end;

function TNWPathMonitor.GetPath: TNWPath;
begin
  TMonitor.Enter(FLock);
  try
    Result := FPath;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TNWPathMonitor.HandlePlatformPath(const APath: TNWPath);
var
  LPath: TNWPath;
  LToken: IInterface;
begin
  TMonitor.Enter(FLock);
  try
    FPath := APath;
  finally
    TMonitor.Exit(FLock);
  end;
  if FSynchronizeEvents then
  begin
    LPath := APath;
    LToken := FAliveToken;
    TThread.ForceQueue(nil,
      procedure
      begin
        // Skip events that arrive after the monitor was stopped or destroyed
        if TNWAliveToken(LToken).IsAlive and FIsMonitoring then
          DoPathChanged(LPath);
      end
    );
  end
  else
    DoPathChanged(APath);
end;

procedure TNWPathMonitor.Start;
begin
  if not FIsMonitoring then
  begin
    FIsMonitoring := True;
    FPlatformMonitor.DoStart;
  end;
end;

procedure TNWPathMonitor.Stop;
begin
  if FIsMonitoring then
  begin
    FIsMonitoring := False;
    FPlatformMonitor.DoStop;
  end;
end;

end.
