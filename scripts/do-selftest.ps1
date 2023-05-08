<#
do-selftest.ps1: Sample script for invoke Drive Self-test of NVMe drive using Windows' inbox device driver

Usage: ./do-selftest.ps1 <PhysicalDriveNo> <CommandType>

Arguments:
    PhysicalDriveNo: physical drive no. to be accessed (required)
    CommandType: command of Drive Self-test; 1: start short test (default), 2: start extended test, 15: abort test

Copyright (c) 2023 Kenichiro Yoshii
Copyright (c) 2023 Hagiwara Solutions Co., Ltd.
#>
Param([parameter(mandatory)][Int]$PhyDrvNo, [Int]$cmdType = 1)

$KernelService = Add-Type -Name 'Kernel32' -Namespace 'Win32' -PassThru -MemberDefinition @"
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern IntPtr CreateFile(
        String lpFileName,
        UInt32 dwDesiredAccess,
        UInt32 dwShareMode,
        IntPtr lpSecurityAttributes,
        UInt32 dwCreationDisposition,
        UInt32 dwFlagsAndAttributes,
        IntPtr hTemplateFile);

    [DllImport("Kernel32.dll", SetLastError = true)]
    public static extern bool DeviceIoControl(
        IntPtr  hDevice,
        int     oControlCode,
        IntPtr  InBuffer,
        int     nInBufferSize,
        IntPtr  OutBuffer,
        int     nOutBufferSize,
        ref int pBytesReturned,
        IntPtr  Overlapped);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr hObject);
"@

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct StorageProtocolCommand {
    public UInt32 Version;
    public UInt32 Length;

    public UInt32 ProtocolType;
    public UInt32 Flags;

    public UInt32 ReturnStatus;
    public UInt32 ErrorCode;

    public UInt32 CommandLength;
    public UInt32 ErrorInfoLength;
    public UInt32 DataToDeviceTransferLength;
    public UInt32 DataFromDeviceTransferLength;

    public UInt32 TimeOutValue;

    public UInt32 ErrorInfoOffset;
    public UInt32 DataToDeviceBufferOffset;
    public UInt32 DataFromDeviceOffset;

    public UInt32 CommandSpecific;
    public UInt32 Reserved0;

    public UInt32 FixedProtocolReturnData;
    public UInt32 Reserved10;
    public UInt32 Reserved11;
    public UInt32 Reserved12;

    public UInt32 CDW0;
    public UInt32 CDW1;
    public UInt32 CDW2;
    public UInt32 CDW3;
    public UInt32 CDW4;
    public UInt32 CDW5;
    public UInt32 CDW6;
    public UInt32 CDW7;
    public UInt32 CDW8;
    public UInt32 CDW9;
    public UInt32 CDW10;
    public UInt32 CDW11;
    public UInt32 CDW12;
    public UInt32 CDW13;
    public UInt32 CDW14;
    public UInt32 CDW15;
}
"@

if ( $cmdType -eq 1 )
{
    Write-Output "`n[I] Short Device Self-test is requested";
}
elseif ( $cmdType -eq 2 )
{
    Write-Output "`n[I] Extended Device Self-test is requested";
}
elseif ( $cmdType -eq 15 )
{
    Write-Output "`n[I] Aborting Device Self-test is requested";
}
else
{
    Write-Output "`n[E] Unknown operation is specified ($cmdType)";
    Write-Output "[E] Operation should be one of '1' (Short Device Self-test), '2' (Extended Device Self-test), and '15' (Abort Device Self-test)";
    Return;
}

$AccessMask = "3221225472"; # = 0xC00000000 = GENERIC_READ (0x80000000) | GENERIC_WRITE (0x40000000)
$AccessMode = 3; # FILE_SHARE_READ | FILE_SHARE_WRITE
$AccessEx   = 3; # OPEN_EXISTING
$AccessAttr = 0x40; # FILE_ATTRIBUTE_DEVICE

$DeviceHandle = $KernelService::CreateFile("\\.\PhysicalDrive$PhyDrvNo", [System.Convert]::ToUInt32($AccessMask), $AccessMode, [System.IntPtr]::Zero, $AccessEx, $AccessAttr, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error()
if ($DeviceHandle -eq [System.IntPtr]::Zero)
{
     Write-Output "`n[E] CreateFile failed: $LastError";
     Return;
}

# offsetof(STORAGE_PROTOCOL_COMMAND, Command)
#  + STORAGE_PROTOCOL_COMMAND_LENGTH_NVME
$CmdBufferSize = 80 + 64; # = 144
$CmdBuffer     = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($CmdBufferSize);

$Command       = New-Object StorageProtocolCommand;
$CommandSize  = [System.Runtime.InteropServices.Marshal]::SizeOf($Command);

if ( $CommandSize -ne $CmdBufferSize )
{
    Write-Output "`n[E] Size of structure is $CommandSize bytes, expect 144 bytes, stop";
    Return;
}

$Command.Version      = 1;  # STORAGE_PROTOCOL_STRUCTURE_VERSION
$Command.Length       = 84; # sizeof(STORAGE_PROTOCOL_COMMAND)
$Command.ProtocolType = 3;  # ProtocolTypeNvme
$Command.Flags        = [System.Convert]::ToUInt32("2147483648");  # STORAGE_PROTOCOL_COMMAND_FLAG_ADAPTER_REQUEST (0x80000000)

$Command.CommandLength   = 64; # STORAGE_PROTOCOL_COMMAND_LENGTH_NVME
$Command.ErrorInfoLength = 0;
$Command.ErrorInfoOffset = 0;
$Command.DataFromDeviceOffset = 0;
$Command.DataFromDeviceTransferLength = 0;
$Command.TimeOutValue    = 10;
$Command.CommandSpecific = 1; # STORAGE_PROTOCOL_SPECIFIC_NVME_ADMIN_COMMAND

$Command.CDW0  = 0x14; # CDW0.OPC = NVME_ADMIN_COMMAND_DEVICE_SELF_TEST
$Command.CDW1  = [System.Convert]::ToUInt32("4294967295"); # CDW1 (NSID) = NVME_NAMESPACE_ALL (0xFFFFFFFF)
$Command.CDW10 = $cmdType;

$ByteRet = 0;
$IoControlCode = 3003328; # IOCTL_STORAGE_PROTOCOL_COMMAND

[System.Runtime.InteropServices.Marshal]::StructureToPtr($Command, $CmdBuffer, [System.Boolean]::false);
$CallResult = $KernelService::DeviceIoControl($DeviceHandle, $IoControlCode, $CmdBuffer, $CmdBufferSize, $CmdBuffer, $CmdBufferSize, [ref]$ByteRet, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error();
if ( $CallResult -eq 0 )
{
    Write-Output "`n[E] DeviceIoControl() failed: $LastError";
    Return;
}

[System.Runtime.InteropServices.Marshal]::FreeHGlobal($CmdBuffer);
[void]$KernelService::CloseHandle($DeviceHandle);

if ( $cmdType -eq 1 )
{
    Write-Output "`n[I] Short Device Self-test started. Test progress and result can be checked by get-selftest-log.ps1";
}
elseif ( $cmdType -eq 2 )
{
    Write-Output "`n[I] Extended Device Self-test started. Test progress and result can be checked by get-selftest-log.ps1";
}
else
{
    Write-Output "`n[I] Device Self-test is aborted. Test result can be checked by get-selftest-log.ps1";
}
