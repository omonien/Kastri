unit NWPathMonitorTests.Main;

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

interface

uses
  DUnitX.TestFramework,
  DW.NWPathMonitor;

type
  TFakePlatformNWPathMonitor = class(TCustomPlatformNWPathMonitor)
  public
    class var LastInstance: TFakePlatformNWPathMonitor;
    class var StartCount: Integer;
    class var StopCount: Integer;
  protected
    procedure DoStart; override;
    procedure DoStop; override;
    function GetIsSupported: Boolean; override;
  public
    constructor Create(const AMonitor: TNWPathMonitor); override;
    procedure Simulate(const APath: TNWPath);
  end;

  [TestFixture]
  TNWPathMonitorTests = class
  private
    FEventCount: Integer;
    FLastPath: TNWPath;
    procedure PathChangedHandler(Sender: TObject; const APath: TNWPath);
  public
    [Setup]
    procedure Setup;
    [Test]
    [TestCase('Invalid', '0,0')]
    [TestCase('Satisfied', '1,1')]
    [TestCase('Unsatisfied', '2,2')]
    [TestCase('Satisfiable', '3,3')]
    [TestCase('Unknown', '99,0')]
    procedure StatusFromValue(const AValue: Cardinal; const AExpected: Integer);
    [Test]
    [TestCase('Other', '0,0')]
    [TestCase('WiFi', '1,1')]
    [TestCase('Cellular', '2,2')]
    [TestCase('Wired', '3,3')]
    [TestCase('Loopback', '4,4')]
    [TestCase('Unknown', '42,0')]
    procedure InterfaceTypeFromValue(const AValue: Cardinal; const AExpected: Integer);
    [Test]
    procedure InterfaceTypeRoundTrip;
    [Test]
    procedure EmptyPathIsInvalid;
    [Test]
    procedure IsConnectedOnlyWhenSatisfied;
    [Test]
    procedure PrimaryInterfacePrefersWiFi;
    [Test]
    procedure PrimaryInterfaceWiredBeforeCellular;
    [Test]
    procedure PrimaryInterfaceLoopbackOnly;
    [Test]
    procedure PrimaryInterfaceEmptyIsOther;
    [Test]
    procedure IsEqualComparesAllFields;
    [Test]
    procedure ToStringListsTypes;
    [Test]
    procedure DefaultPlatformIsNotSupportedOnWindows;
    [Test]
    procedure StartStopCallPlatformOnce;
    [Test]
    procedure UnsynchronizedEventFiresDirectly;
    [Test]
    procedure PathPropertyKeepsLastPath;
    [Test]
    procedure NoEventAfterDestroy;
  end;

implementation

uses
  System.SysUtils, System.Classes;

{ TFakePlatformNWPathMonitor }

constructor TFakePlatformNWPathMonitor.Create(const AMonitor: TNWPathMonitor);
begin
  inherited;
  LastInstance := Self;
end;

procedure TFakePlatformNWPathMonitor.DoStart;
begin
  Inc(StartCount);
end;

procedure TFakePlatformNWPathMonitor.DoStop;
begin
  Inc(StopCount);
end;

function TFakePlatformNWPathMonitor.GetIsSupported: Boolean;
begin
  Result := True;
end;

procedure TFakePlatformNWPathMonitor.Simulate(const APath: TNWPath);
begin
  PathChanged(APath);
end;

function MakePath(const AStatus: TNWPathStatus; const ATypes: TNWInterfaceTypes): TNWPath;
begin
  Result := TNWPath.Empty;
  Result.Status := AStatus;
  Result.InterfaceTypes := ATypes;
end;

{ TNWPathMonitorTests }

procedure TNWPathMonitorTests.Setup;
begin
  FEventCount := 0;
  FLastPath := TNWPath.Empty;
  TFakePlatformNWPathMonitor.StartCount := 0;
  TFakePlatformNWPathMonitor.StopCount := 0;
  TFakePlatformNWPathMonitor.LastInstance := nil;
end;

procedure TNWPathMonitorTests.PathChangedHandler(Sender: TObject; const APath: TNWPath);
begin
  Inc(FEventCount);
  FLastPath := APath;
end;

procedure TNWPathMonitorTests.StatusFromValue(const AValue: Cardinal; const AExpected: Integer);
begin
  Assert.AreEqual(AExpected, Ord(NWPathStatusFromValue(AValue)));
end;

procedure TNWPathMonitorTests.InterfaceTypeFromValue(const AValue: Cardinal; const AExpected: Integer);
begin
  Assert.AreEqual(AExpected, Ord(NWInterfaceTypeFromValue(AValue)));
end;

procedure TNWPathMonitorTests.InterfaceTypeRoundTrip;
var
  LType: TNWInterfaceType;
begin
  for LType := Low(TNWInterfaceType) to High(TNWInterfaceType) do
    Assert.AreEqual(Ord(LType), Ord(NWInterfaceTypeFromValue(NWInterfaceTypeToValue(LType))));
end;

procedure TNWPathMonitorTests.EmptyPathIsInvalid;
var
  LPath: TNWPath;
begin
  LPath := TNWPath.Empty;
  Assert.AreEqual(Ord(TNWPathStatus.Invalid), Ord(LPath.Status));
  Assert.IsFalse(LPath.IsConnected);
  Assert.IsTrue(LPath.InterfaceTypes = []);
end;

procedure TNWPathMonitorTests.IsConnectedOnlyWhenSatisfied;
begin
  Assert.IsTrue(MakePath(TNWPathStatus.Satisfied, []).IsConnected);
  Assert.IsFalse(MakePath(TNWPathStatus.Satisfiable, []).IsConnected);
  Assert.IsFalse(MakePath(TNWPathStatus.Unsatisfied, []).IsConnected);
end;

procedure TNWPathMonitorTests.PrimaryInterfacePrefersWiFi;
var
  LPath: TNWPath;
begin
  LPath := MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.Cellular, TNWInterfaceType.WiFi, TNWInterfaceType.Other]);
  Assert.AreEqual(Ord(TNWInterfaceType.WiFi), Ord(LPath.PrimaryInterfaceType));
end;

procedure TNWPathMonitorTests.PrimaryInterfaceWiredBeforeCellular;
var
  LPath: TNWPath;
begin
  LPath := MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.Cellular, TNWInterfaceType.Wired]);
  Assert.AreEqual(Ord(TNWInterfaceType.Wired), Ord(LPath.PrimaryInterfaceType));
end;

procedure TNWPathMonitorTests.PrimaryInterfaceLoopbackOnly;
var
  LPath: TNWPath;
begin
  LPath := MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.Loopback]);
  Assert.AreEqual(Ord(TNWInterfaceType.Loopback), Ord(LPath.PrimaryInterfaceType));
  LPath.InterfaceTypes := [TNWInterfaceType.Loopback, TNWInterfaceType.Other];
  Assert.AreEqual(Ord(TNWInterfaceType.Other), Ord(LPath.PrimaryInterfaceType));
end;

procedure TNWPathMonitorTests.PrimaryInterfaceEmptyIsOther;
begin
  Assert.AreEqual(Ord(TNWInterfaceType.Other), Ord(MakePath(TNWPathStatus.Unsatisfied, []).PrimaryInterfaceType));
end;

procedure TNWPathMonitorTests.IsEqualComparesAllFields;
var
  LA, LB: TNWPath;
begin
  LA := MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.WiFi]);
  LB := LA;
  Assert.IsTrue(LA.IsEqual(LB));
  LB.IsExpensive := True;
  Assert.IsFalse(LA.IsEqual(LB));
  LB := LA;
  LB.HasDNS := True;
  Assert.IsFalse(LA.IsEqual(LB));
  LB := LA;
  LB.InterfaceTypes := [TNWInterfaceType.Cellular];
  Assert.IsFalse(LA.IsEqual(LB));
end;

procedure TNWPathMonitorTests.ToStringListsTypes;
var
  LText: string;
begin
  LText := MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.WiFi, TNWInterfaceType.Cellular]).ToString;
  Assert.Contains(LText, 'Status=Satisfied');
  Assert.Contains(LText, 'Types=[WiFi,Cellular]');
end;

procedure TNWPathMonitorTests.DefaultPlatformIsNotSupportedOnWindows;
var
  LMonitor: TNWPathMonitor;
begin
  LMonitor := TNWPathMonitor.Create;
  try
    Assert.IsFalse(LMonitor.IsSupported);
    LMonitor.Start;
    Assert.IsTrue(LMonitor.IsMonitoring);
    LMonitor.Stop;
    Assert.IsFalse(LMonitor.IsMonitoring);
  finally
    LMonitor.Free;
  end;
end;

procedure TNWPathMonitorTests.StartStopCallPlatformOnce;
var
  LMonitor: TNWPathMonitor;
begin
  LMonitor := TNWPathMonitor.Create(TFakePlatformNWPathMonitor);
  try
    Assert.IsTrue(LMonitor.IsSupported);
    LMonitor.Start;
    LMonitor.Start;
    LMonitor.Stop;
    LMonitor.Stop;
    Assert.AreEqual(1, TFakePlatformNWPathMonitor.StartCount);
    Assert.AreEqual(1, TFakePlatformNWPathMonitor.StopCount);
  finally
    LMonitor.Free;
  end;
end;

procedure TNWPathMonitorTests.UnsynchronizedEventFiresDirectly;
var
  LMonitor: TNWPathMonitor;
begin
  LMonitor := TNWPathMonitor.Create(TFakePlatformNWPathMonitor);
  try
    LMonitor.SynchronizeEvents := False;
    LMonitor.OnPathChanged := PathChangedHandler;
    LMonitor.Start;
    TFakePlatformNWPathMonitor.LastInstance.Simulate(MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.WiFi]));
    Assert.AreEqual(1, FEventCount);
    Assert.IsTrue(FLastPath.IsConnected);
  finally
    LMonitor.Free;
  end;
end;

procedure TNWPathMonitorTests.PathPropertyKeepsLastPath;
var
  LMonitor: TNWPathMonitor;
begin
  LMonitor := TNWPathMonitor.Create(TFakePlatformNWPathMonitor);
  try
    LMonitor.SynchronizeEvents := False;
    LMonitor.Start;
    TFakePlatformNWPathMonitor.LastInstance.Simulate(MakePath(TNWPathStatus.Unsatisfied, []));
    TFakePlatformNWPathMonitor.LastInstance.Simulate(MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.Cellular]));
    Assert.IsTrue(LMonitor.Path.IsConnected);
    Assert.AreEqual(Ord(TNWInterfaceType.Cellular), Ord(LMonitor.Path.PrimaryInterfaceType));
  finally
    LMonitor.Free;
  end;
end;

procedure TNWPathMonitorTests.NoEventAfterDestroy;
var
  LMonitor: TNWPathMonitor;
begin
  LMonitor := TNWPathMonitor.Create(TFakePlatformNWPathMonitor);
  LMonitor.OnPathChanged := PathChangedHandler;
  LMonitor.Start;
  // Queued for the main thread, then the monitor goes away before the queue is processed
  TFakePlatformNWPathMonitor.LastInstance.Simulate(MakePath(TNWPathStatus.Satisfied, [TNWInterfaceType.WiFi]));
  LMonitor.Free;
  CheckSynchronize(0);
  Assert.AreEqual(0, FEventCount);
end;

end.
