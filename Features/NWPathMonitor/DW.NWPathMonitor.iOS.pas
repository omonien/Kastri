unit DW.NWPathMonitor.iOS;

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
  // DW
  DW.NWPathMonitor;

type
  TPlatformNWPathMonitor = class(TCustomPlatformNWPathMonitor)
  private
    FState: IInterface;
  protected
    procedure DoStart; override;
    procedure DoStop; override;
    function GetIsSupported: Boolean; override;
  public
    destructor Destroy; override;
  end;

implementation

uses
  // RTL
  System.SysUtils,
  // Posix
  Posix.Dlfcn,
  // DW
  DW.iOSapi.Network;

// nw_path_monitor_set_update_handler and nw_path_monitor_set_cancel_handler expect Objective-C blocks. The procedural types in
// DW.iOSapi.Network are declared "of object", which the compiler only marshals for Objective-C methods, not for C functions.
// This unit therefore passes hand made block literals, flagged as global blocks so that Block_copy and Block_release are no-ops.

const
  libSystem = '/usr/lib/libSystem.dylib';
  cBlockIsGlobal = 1 shl 28;
  cRTLDDefault = NativeUInt(-2);

type
  TNWBlockDescriptor = record
    Reserved: NativeUInt;
    Size: NativeUInt;
  end;
  PNWBlockDescriptor = ^TNWBlockDescriptor;

  TNWBlockLiteral = record
    Isa: Pointer;
    Flags: Int32;
    Reserved: Int32;
    Invoke: Pointer;
    Descriptor: PNWBlockDescriptor;
    Context: Pointer;
  end;
  PNWBlockLiteral = ^TNWBlockLiteral;

  TNWPathMonitorState = class(TInterfacedObject)
  private
    FCancelBlock: PNWBlockLiteral;
    FLock: TObject;
    FMonitor: Pointer;
    FOwner: TPlatformNWPathMonitor;
    FUpdateBlock: PNWBlockLiteral;
  public
    constructor Create(const AOwner: TPlatformNWPathMonitor);
    destructor Destroy; override;
    procedure Cancelled;
    procedure Detach;
    procedure Update(const APath: Pointer);
  end;

  TOpenPlatformNWPathMonitor = class(TPlatformNWPathMonitor);

var
  GBlockDescriptor: TNWBlockDescriptor = (Reserved: 0; Size: SizeOf(TNWBlockLiteral));
  GConcreteGlobalBlock: Pointer;

function dispatch_queue_create(_label: MarshaledAString; attr: Pointer): Pointer; cdecl;
  external libSystem name _PU + 'dispatch_queue_create';
procedure dispatch_release(obj: Pointer); cdecl;
  external libSystem name _PU + 'dispatch_release';
procedure nw_path_monitor_set_update_handler_block(monitor: Pointer; update_handler: Pointer); cdecl;
  external libNetwork name _PU + 'nw_path_monitor_set_update_handler';
procedure nw_path_monitor_set_cancel_handler_block(monitor: Pointer; cancel_handler: Pointer); cdecl;
  external libNetwork name _PU + 'nw_path_monitor_set_cancel_handler';
procedure nw_path_monitor_set_queue_ptr(monitor: Pointer; queue: Pointer); cdecl;
  external libNetwork name _PU + 'nw_path_monitor_set_queue';

function ConcreteGlobalBlock: Pointer;
begin
  if GConcreteGlobalBlock = nil then
    GConcreteGlobalBlock := dlsym(cRTLDDefault, '_NSConcreteGlobalBlock');
  Result := GConcreteGlobalBlock;
end;

function CreateBlockLiteral(const AInvoke, AContext: Pointer): PNWBlockLiteral;
begin
  New(Result);
  Result.Isa := ConcreteGlobalBlock;
  Result.Flags := cBlockIsGlobal;
  Result.Reserved := 0;
  Result.Invoke := AInvoke;
  Result.Descriptor := @GBlockDescriptor;
  Result.Context := AContext;
end;

function PathFromNative(const APath: Pointer): TNWPath;
var
  LType: TNWInterfaceType;
begin
  Result := TNWPath.Empty;
  if APath = nil then
    Exit; // <======
  Result.Status := NWPathStatusFromValue(nw_path_get_status(APath));
  for LType := Low(TNWInterfaceType) to High(TNWInterfaceType) do
  begin
    if nw_path_uses_interface_type(APath, NWInterfaceTypeToValue(LType)) then
      Include(Result.InterfaceTypes, LType);
  end;
  Result.IsExpensive := nw_path_is_expensive(APath);
  Result.IsConstrained := nw_path_is_constrained(APath);
  Result.HasIPv4 := nw_path_has_ipv4(APath);
  Result.HasIPv6 := nw_path_has_ipv6(APath);
  Result.HasDNS := nw_path_has_dns(APath);
end;

procedure UpdateBlockInvoke(ABlock: PNWBlockLiteral; APath: Pointer); cdecl;
begin
  TNWPathMonitorState(ABlock.Context).Update(APath);
end;

procedure CancelBlockInvoke(ABlock: PNWBlockLiteral); cdecl;
begin
  TNWPathMonitorState(ABlock.Context).Cancelled;
end;

{ TNWPathMonitorState }

constructor TNWPathMonitorState.Create(const AOwner: TPlatformNWPathMonitor);
begin
  inherited Create;
  FLock := TObject.Create;
  FOwner := AOwner;
  // The block literals are intentionally never freed: the Network framework may still read them (e.g. in Block_release) after
  // the cancel handler has run. They are 40 bytes each, allocated once per Start
  FUpdateBlock := CreateBlockLiteral(@UpdateBlockInvoke, Self);
  FCancelBlock := CreateBlockLiteral(@CancelBlockInvoke, Self);
end;

destructor TNWPathMonitorState.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TNWPathMonitorState.Cancelled;
begin
  if FMonitor <> nil then
    nw_release(FMonitor);
  FMonitor := nil;
  // Releases the reference that was held for the native side in DoStart
  _Release;
end;

procedure TNWPathMonitorState.Detach;
begin
  TMonitor.Enter(FLock);
  try
    FOwner := nil;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TNWPathMonitorState.Update(const APath: Pointer);
var
  LPath: TNWPath;
begin
  // The path object is only valid during the callback, so it is read here
  LPath := PathFromNative(APath);
  TMonitor.Enter(FLock);
  try
    if FOwner <> nil then
      TOpenPlatformNWPathMonitor(FOwner).PathChanged(LPath);
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TPlatformNWPathMonitor }

destructor TPlatformNWPathMonitor.Destroy;
begin
  DoStop;
  inherited;
end;

procedure TPlatformNWPathMonitor.DoStart;
var
  LState: TNWPathMonitorState;
  LQueue: Pointer;
begin
  if (FState <> nil) or (ConcreteGlobalBlock = nil) then
    Exit; // <======
  LState := TNWPathMonitorState.Create(Self);
  FState := LState;
  LState.FMonitor := nw_path_monitor_create;
  if LState.FMonitor = nil then
  begin
    FState := nil;
    Exit; // <======
  end;
  // Held until the cancel handler has run
  LState._AddRef;
  LQueue := dispatch_queue_create('com.delphiworlds.nwpathmonitor', nil);
  nw_path_monitor_set_queue_ptr(LState.FMonitor, LQueue);
  // The monitor retains the queue
  dispatch_release(LQueue);
  nw_path_monitor_set_update_handler_block(LState.FMonitor, LState.FUpdateBlock);
  nw_path_monitor_set_cancel_handler_block(LState.FMonitor, LState.FCancelBlock);
  nw_path_monitor_start(LState.FMonitor);
end;

procedure TPlatformNWPathMonitor.DoStop;
var
  LState: TNWPathMonitorState;
begin
  if FState = nil then
    Exit; // <======
  LState := TNWPathMonitorState(FState);
  // After Detach no further updates reach this object, even when the queue still delivers one
  LState.Detach;
  nw_path_monitor_cancel(LState.FMonitor);
  FState := nil;
end;

function TPlatformNWPathMonitor.GetIsSupported: Boolean;
begin
  Result := ConcreteGlobalBlock <> nil;
end;

end.
