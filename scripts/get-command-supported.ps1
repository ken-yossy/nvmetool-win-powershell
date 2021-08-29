<#
get-command-supported.ps1: Sample script for getting and listing supported command of specified NVMe drive.
 Information is retrieved from Command Supported and Effects log page with Windows' inbox device driver.

Note: lists commands defined in Admin Command Set, I/O Command Set, and NVM Command Set.
 Excludes vendor specific commands, ZNS and KVS Command Set.

Usage: ./get-command-supported.ps1 <PhysicalDriveNo>

Copyright (c) 2021 Kenichiro Yoshii
Copyright (c) 2021 Hagiwara Solutions Co., Ltd.
#>
Param([parameter(mandatory)][Int]$PhyDrvNo)

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
public struct NVMeStorageQueryProperty {
    public UInt32 PropertyId;
    public UInt32 QueryType;
    public UInt32 ProtocolType;
    public UInt32 DataType;
    public UInt32 ProtocolDataRequestValue;
    public UInt32 ProtocolDataRequestSubValue;
    public UInt32 ProtocolDataOffset;
    public UInt32 ProtocolDataLength;
    public UInt32 FixedProtocolReturnData;
    public UInt32 ProtocolDataRequestSubValue2;
    public UInt32 ProtocolDataRequestSubValue3;
    public UInt32 Reserved0;

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 1024)]
    public Byte[] CSEDataAdmin; // 4-byte x 256 commands

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 1024)]
    public Byte[] CSEDataIO; // 4-byte x 256 commands

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 2048)]
    public Byte[] Reserved1;
}
"@

$AdminCmdList = [ordered]@{
    0  = 'Delete I/O Submission Queue'
    1  = 'Create I/O Submission Queue'
    2  = 'Get Log Page'
    4  = 'Delete I/O Completion Queue'
    5  = 'Create I/O Completion Queue'
    6  = 'Identify'
    8  = 'Abort'
    9  = 'Set Features'
    10 = 'Get Features'
    12 = 'Asynchronous Event Request'
    13 = 'Namespace Management'
    16 = 'Firmware Commit'
    17 = 'Firmware Image Download'
    20 = 'Device Self-test'
    21 = 'Namespace Attachment'
    24 = 'Keep Alive'
    25 = 'Directive Send'
    26 = 'Directive Receive'
    28 = 'Virtualization Management'
    29 = 'NVMe-MI Send'
    30 = 'NVMe-MI Receive'
    32 = 'Capacity Management'
    36 = 'Lockdown'
    124 = 'Doorbell Buffer Config'
    127 = 'Fabrics Commands'
    128 = 'Format NVM'
    129 = 'Security Send'
    130 = 'Security Receive'
    132 = 'Sanitize'
    134 = 'Get LBA Status'
}

$IOandNVMCmdList = [ordered]@{
    0  = 'Flush'
    1  = 'Write'
    2  = 'Read'
    4  = 'Write Uncorrectable'
    5  = 'Compare'
    8  = 'Write Zeroes'
    9  = 'Dataset Management'
    12 = 'Verify'
    13 = 'Reservation Register'
    14 = 'Reservation Report'
    17 = 'Reservation Acquire'
    21 = 'Reservation Release'
    25 = 'Copy'
}

$AccessMask = "3221225472"; # = 0xC00000000 = GENERIC_READ (0x80000000) | GENERIC_WRITE (0x40000000)
$AccessMode = 3; # FILE_SHARE_READ | FILE_SHARE_WRITE
$AccessEx   = 3; # OPEN_EXISTING
$AccessAttr = 0x40; # FILE_ATTRIBUTE_DEVICE

$DeviceHandle = $KernelService::CreateFile("\\.\PhysicalDrive$PhyDrvNo", [System.Convert]::ToUInt32($AccessMask), $AccessMode, [System.IntPtr]::Zero, $AccessEx, $AccessAttr, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error()
if ($DeviceHandle -eq [System.IntPtr]::Zero) {
     Write-Output "[E] CreateFile failed: $LastError";
     Return;
}

# offsetof(STORAGE_PROPERTY_QUERY, AdditionalParameters)
#  + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
#  + sizeof(NVME_COMMAND_EFFECTS_LOG) = 4144
$OutBufferSize = 8 + 40 + 4096; # = 4144
$OutBuffer     = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($OutBufferSize);

$Property      = New-Object NVMeStorageQueryProperty;
$PropertySize  = [System.Runtime.InteropServices.Marshal]::SizeOf($Property);

if ( $PropertySize -ne $OutBufferSize ) {
    Write-Output "[E] Size of structure is $PropertySize bytes, expect 4144 bytes, stop";
    Return;
}

$Property.PropertyId    = 50; # StorageDeviceProtocolSpecificProperty
$Property.QueryType     = 0;  # PropertyStandardQuery
$Property.ProtocolType  = 3;  # ProtocolTypeNvme
$Property.DataType      = 2;  # NVMeDataTypeLogPage

$Property.ProtocolDataRequestValue      = 5; # NVME_LOG_PAGE_COMMAND_EFFECTS
$Property.ProtocolDataRequestSubValue   = [System.Convert]::ToUInt32("4294967295"); # NVME_NAMESPACE_ALL (0xFFFFFFFF)

$Property.ProtocolDataOffset = 40;  # sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
$Property.ProtocolDataLength = 4096; # sizeof(NVME_COMMAND_EFFECTS_LOG)

$ByteRet = 0;
$IoControlCode = 0x2d1400; # IOCTL_STORAGE_QUERY_PROPERTY

[System.Runtime.InteropServices.Marshal]::StructureToPtr($Property, $OutBuffer, [System.Boolean]::false);
$CallResult = $KernelService::DeviceIoControl($DeviceHandle, $IoControlCode, $OutBuffer, $OutBufferSize, $OutBuffer, $OutBufferSize, [ref]$ByteRet, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error();
if ( $CallResult -eq 0 ) {
    Write-Output "[E] DeviceIoControl() failed: $LastError";
    Return;
}

if ( $ByteRet -ne $OutBufferSize ) {
    Write-Output "[E] Data size returned ($ByteRet bytes) is wrong; expect $OutBufferSize bytes";
    Return;
}

# Admin Commands
Write-Output( "`nScan result of Admin Command Set (X: supported)");
$AdminCmdList.GetEnumerator() | ForEach-Object {
    $CSEData = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $_.key * 4 + 48);
    $CmdIsSupported = $CSEData -band 0x00000001; # bit 0 is "Command Supported (CSUPP)"
    if ( $CmdIsSupported -ne 0 ) {
        Write-Output( "[ X ] {0}" -F $_.value);
    } else {
        Write-Output( "[   ] {0}" -F $_.value);
    }
}

# I/O and NVM Commands
Write-Output( "`nScan result of I/O and NVM Command Set (X: supported)");
$IOandNVMCmdList.GetEnumerator() | ForEach-Object {
    $CSEData = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $_.key * 4 + 1024 + 48);
    $CmdIsSupported = $CSEData -band 0x00000001; # bit 0 is "Command Supported (CSUPP)"
    if ( $CmdIsSupported -ne 0 ) {
        Write-Output( "[ X ] {0}" -F $_.value);
    } else {
        Write-Output( "[   ] {0}" -F $_.value);
    }
}

[System.Runtime.InteropServices.Marshal]::FreeHGlobal($OutBuffer);
[void]$KernelService::CloseHandle($DeviceHandle);
