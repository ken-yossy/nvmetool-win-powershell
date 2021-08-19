<#
get-subnqn.ps1: Sample script for getting NVM Subsystem NVMe Qualified Name (SUBNQN) and some fields
                from Identify Controller data of an NVMe drive using Windows' inbox device driver

Usage: ./get-subnqn.ps1 <PhysicalDriveNo>

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

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4096)]
    public Byte[] IdentifyControllerData;

//    Followings are the partial structure of Identify Conntroller Data in NVMe rev2.0a
// 
//                                            // byte offset from the head of this structure

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 4)]
//    public Byte[] __pad0;                   // byte 0

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 20)]
//    public Byte[] SerialNumber;             // byte 4

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 40)]
//    public Byte[] ModelNumber;              // byte 24

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 8)]
//    public Byte[] FirmwareRevision;         // byte 64

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 696)]
//    public Byte[] __pad1;                   // byte 72

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 256)]
//    public Byte[] SubNQN;                   // byte 768

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3072)]
//    public Byte[] __pad2;                   // byte 1024
}
"@

$AccessMask = "3221225472"; # = 0xC00000000 = GENERIC_READ (0x80000000) | GENERIC_WRITE (0x40000000)
$AccessMode = 3; # FILE_SHARE_READ | FILE_SHARE_WRITE
$AccessEx   = 3; # OPEN_EXISTING
$AccessAttr = 0x40; # FILE_ATTRIBUTE_DEVICE

$DeviceHandle = $KernelService::CreateFile("\\.\PhysicalDrive$PhyDrvNo", [System.Convert]::ToUInt32($AccessMask), $AccessMode, [System.IntPtr]::Zero, $AccessEx, $AccessAttr, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error()
if ($DeviceHandle -eq [System.IntPtr]::Zero) {
     Write-Output "`n[E] CreateFile failed: $LastError";
     Return;
}

# offsetof(STORAGE_PROPERTY_QUERY, AdditionalParameters)
#  + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
#  + sizeof(NVME_IDENTIFY_CONTROLLER_DATA)
$OutBufferSize = 8 + 40 + 4096; # = 4144
$OutBuffer     = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($OutBufferSize);

$Property      = New-Object NVMeStorageQueryProperty;
$PropertySize  = [System.Runtime.InteropServices.Marshal]::SizeOf($Property);

if ( $PropertySize -ne $OutBufferSize ) {
    Write-Output "`n[E] Size of structure is $PropertySize bytes, expect 4144 bytes, stop";
    Return;
}

$Property.PropertyId    = 49; # StorageAdapterProtocolSpecificProperty
$Property.QueryType     = 0;  # PropertyStandardQuery
$Property.ProtocolType  = 3;  # ProtocolTypeNvme
$Property.DataType      = 1;  # NVMeDataTypeIdentify

$Property.ProtocolDataRequestValue      = 1; # NVME_IDENTIFY_CNS_CONTROLLER
$Property.ProtocolDataRequestSubValue   = 0;

$Property.ProtocolDataOffset = 40;  # sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
$Property.ProtocolDataLength = 4096; # sizeof(NVME_IDENTIFY_CONTROLLER_DATA)

$ByteRet = 0;
$IoControlCode = 0x2d1400; # IOCTL_STORAGE_QUERY_PROPERTY

[System.Runtime.InteropServices.Marshal]::StructureToPtr($Property, $OutBuffer, [System.Boolean]::false);
$CallResult = $KernelService::DeviceIoControl($DeviceHandle, $IoControlCode, $OutBuffer, $OutBufferSize, $OutBuffer, $OutBufferSize, [ref]$ByteRet, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error();
if ( $CallResult -eq 0 ) {
    Write-Output "`n[E] DeviceIoControl() failed: $LastError";
    Return;
}

if ( $ByteRet -ne 4144 ) {
    Write-Output "`n[E] Data size returned ($ByteRet bytes) is wrong; expect $OutBufferSize bytes";
    Return;
}

$CurPtr = [System.IntPtr]::Add($OutBuffer, 48 + 4);
Write-Host -NoNewline "Serial Number (SN): ";
Write-Host("{0}" -F [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($CurPtr, 20));

$CurPtr = [System.IntPtr]::Add($OutBuffer, 48 + 24);
Write-Host -NoNewline "Model Number (MN): "
Write-Host("{0}" -F [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($CurPtr, 40));

$CurPtr = [System.IntPtr]::Add($OutBuffer, 48 + 64);
Write-Host -NoNewline "Firmware Revision (FR): ";
Write-Host("{0}" -F [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($CurPtr, 8));

$CurPtr = [System.IntPtr]::Add($OutBuffer, 48 + 768);
Write-Host -NoNewline "NVM Subsystem NVMe Qualified Name (SUBNQN): ";
Write-Host("{0}" -F [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($CurPtr, 256));

[System.Runtime.InteropServices.Marshal]::FreeHGlobal($OutBuffer);
[void]$KernelService::CloseHandle($DeviceHandle);
