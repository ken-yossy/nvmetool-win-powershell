<#
get-smart-log.ps1: Sample script for getting SMART Log data from an NVMe drive using Windows' inbox device driver

Usage: ./get-smart-log.ps1 <PhysicalDriveNo>

Copyright (c) 2021-2022 Kenichiro Yoshii
Copyright (c) 2021-2022 Hagiwara Solutions Co., Ltd.
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
    public UInt32 ProtocolDataRequestSubValue4;

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 512)]
    public Byte[] SMARTData;

//    Followings are the data structure of SMART Log page in NVMe rev1.4b
// 
//                                            // byte offset from the head of this structure
//    public Byte   CriticalWarning;          // byte 48
//    public UInt16 Temperature;              // byte 49
//    public Byte   AvailableSpare;           // byte 51
//    public Byte   AvailableSpareThreshold;  // byte 52
//    public Byte   PercentageUsed;           // byte 53
//    public Byte   EnduranceGroupSummary;    // byte 54

//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 25)]
//    public Byte[] Reserved1;                // byte 55

//    public UInt64 DataUnitReadL;            // byte 80
//    public UInt64 DataUnitReadH;            // byte 88

//    public UInt64 DataUnitWrittenL;         // byte 96
//    public UInt64 DataUnitWrittenH;         // byte 104

//    public UInt64 HostReadCommandsL;        // byte 112
//    public UInt64 HostReadCommandsH;        // byte 120

//    public UInt64 HostWriteCommandsL;       // byte 128
//    public UInt64 HostWriteCommandsH;       // byte 136

//    public UInt64 ControllerBusyTimeL;      // byte 144
//    public UInt64 ControllerBusyTimeH;      // byte 152

//    public UInt64 PowerCycleL;              // byte 160
//    public UInt64 PowerCycleH;              // byte 168

//    public UInt64 PowerOnHoursL;            // byte 176
//    public UInt64 PowerOnHoursH;            // byte 184

//    public UInt64 UnsafeShutdownsL;         // byte 192
//    public UInt64 UnsafeShutdownsH;         // byte 200

//    public UInt64 MediaErrorsL;             // byte 208
//    public UInt64 MediaErrorsH;             // byte 216

//    public UInt64 ErrorLogInfoEntryNumL;    // byte 224
//    public UInt64 ErrorLogInfoEntryNumH;    // byte 232

//    public UInt32 WCTempTime;               // byte 240
//    public UInt32 CCTempTime;               // byte 244
//    public UInt16 TempSensor1;              // byte 248
//    public UInt16 TempSensor2;              // byte 250
//    public UInt16 TempSensor3;              // byte 252
//    public UInt16 TempSensor4;              // byte 254
//    public UInt16 TempSensor5;              // byte 256
//    public UInt16 TempSensor6;              // byte 258
//    public UInt16 TempSensor7;              // byte 260
//    public UInt16 TempSensor8;              // byte 262
//    public UInt32 TMT1TransitionCount;      // byte 264
//    public UInt32 TMT2TransitionCount;      // byte 268
//    public UInt32 TMT1TotalTime;            // byte 272
//    public UInt32 TMT2TotalTime;            // byte 276
//
//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 280)]
//    public Byte[] Reserved2;                // byte 280
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
#  + sizeof(NVME_SMART_INFO_LOG) = 560
$OutBufferSize = 8 + 40 + 512; # = 560
$OutBuffer     = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($OutBufferSize);

$Property      = New-Object NVMeStorageQueryProperty;
$PropertySize  = [System.Runtime.InteropServices.Marshal]::SizeOf($Property);

if ( $PropertySize -ne $OutBufferSize ) {
    Write-Output "`n[E] Size of structure is $PropertySize bytes, expect 560 bytes, stop";
    Return;
}

$Property.PropertyId    = 50; # StorageDeviceProtocolSpecificProperty
$Property.QueryType     = 0;  # PropertyStandardQuery
$Property.ProtocolType  = 3;  # ProtocolTypeNvme
$Property.DataType      = 2;  # NVMeDataTypeLogPage

$Property.ProtocolDataRequestValue      = 2; # NVME_LOG_PAGE_HEALTH_INFO
$Property.ProtocolDataRequestSubValue   = 0; # LPOL
$Property.ProtocolDataRequestSubValue2  = 0; # LPOU
$Property.ProtocolDataRequestSubValue3  = 0; # Log Specific Identifier in CDW11
$Property.ProtocolDataRequestSubValue4  = 0; # Retain Asynchronous Event (RAE) and Log Specific Field (LSP) in CDW10

$Property.ProtocolDataOffset = 40;  # sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
$Property.ProtocolDataLength = 512; # sizeof(NVME_SMART_INFO_LOG)

$ByteRet = 0;
$IoControlCode = 0x2d1400; # IOCTL_STORAGE_QUERY_PROPERTY

[System.Runtime.InteropServices.Marshal]::StructureToPtr($Property, $OutBuffer, [System.Boolean]::false);
$CallResult = $KernelService::DeviceIoControl($DeviceHandle, $IoControlCode, $OutBuffer, $OutBufferSize, $OutBuffer, $OutBufferSize, [ref]$ByteRet, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error();
if ( $CallResult -eq 0 ) {
    Write-Output "`n[E] DeviceIoControl() failed: $LastError";
    Return;
}

if ( $ByteRet -ne 560 ) {
    Write-Output "`n[E] Data size returned ($ByteRet bytes) is wrong; expect $OutBufferSize bytes";
    Return;
}

Write-Output( "Critical Warning: 0x{0}" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 48).ToString("X2") );
Write-Output( "Composite Temperature: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 49) );
Write-Output( "Available Spare: {0} (%)" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 51) );
Write-Output( "Available Spare Threshold: {0} (%)" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 52) );
Write-Output( "Percentage Used: {0} (%)" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 53) );
Write-Output( "Endurance Group Summary: 0x{0}" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 54).ToString("X2") );
Write-Output( "Data Unit Read: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 88).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 80).ToString("X8") );
Write-Output( "Data Unit Written: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 104).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 96).ToString("X8") );
Write-Output( "Host Read Commands: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 120).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 112).ToString("X8") );
Write-Output( "Host Write Commands: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 136).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 128).ToString("X8") );
Write-Output( "Controller Busy Time: 0x{0}{1} (minutes)" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 152).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 144).ToString("X8") );
Write-Output( "Power Cycles: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 168).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 160).ToString("X8") );
Write-Output( "Power On Hours: 0x{0}{1} (hours)" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 184).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 176).ToString("X8") );
Write-Output( "Unsafe Shutdowns: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 200).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 192).ToString("X8") );
Write-Output( "Media and Data Integrity Errors: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 216).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 208).ToString("X8") );
Write-Output( "Number of Error Information Entries: 0x{0}{1}" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 232).ToString("X8"), [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, 224).ToString("X8") );
Write-Output( "Warning Composite Temperature Time: {0} (minutes)" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, 240) );
Write-Output( "Critical Composite Temperature Time: {0} (minutes)" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, 244) );
Write-Output( "Temperature Sensor 1: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 248) );
Write-Output( "Temperature Sensor 2: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 250) );
Write-Output( "Temperature Sensor 3: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 252) );
Write-Output( "Temperature Sensor 4: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 254) );
Write-Output( "Temperature Sensor 5: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 256) );
Write-Output( "Temperature Sensor 6: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 258) );
Write-Output( "Temperature Sensor 7: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 260) );
Write-Output( "Temperature Sensor 8: {0} (K)" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 262) );
Write-Output( "Thermal Management Temperature 1 Transition Count: {0} (times)" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, 264) );
Write-Output( "Thermal Management Temperature 2 Transition Count: {0} (times)" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, 268) );
Write-Output( "Total Time For Thermal Management Temperature 1: {0} (seconds)" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, 272) );
Write-Output( "Total Time For Thermal Management Temperature 2: {0} (seconds)" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, 276) );

[System.Runtime.InteropServices.Marshal]::FreeHGlobal($OutBuffer);
[void]$KernelService::CloseHandle($DeviceHandle);
