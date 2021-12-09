<#
get-selftest-log.ps1: Sample script for getting Device Self-test Log data from an NVMe drive using Windows' inbox device driver

Usage: ./get-selftest-log.ps1 <PhysicalDriveNo>

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

    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 564)]
    public Byte[] SelftestLogData;

//    Followings are the data structure of Device Self-test log page in NVMe rev2.0a
// 
//                                            // byte offset from the head of this structure
//    public Byte   CurrentOperation;         // byte 48
//    public Byte   CurrentCompletion;        // byte 49
//    public UInt16 Reserved;                 // byte 50
//
//    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 560)]
//    public Byte[] SelftestResult;           // byte 52; 28 Bytes x 20 entries = 560 Bytes 
}
"@

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

# offsetof(STORAGE_PROPERTY_QUERY, AdditionalParameters)
#  + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
#  + sizeof(NVME_DEVICE_SELF_TEST_LOG)
$OutBufferSize = 8 + 40 + 564; # = 612
$OutBuffer     = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($OutBufferSize);

$Property      = New-Object NVMeStorageQueryProperty;
$PropertySize  = [System.Runtime.InteropServices.Marshal]::SizeOf($Property);

if ( $PropertySize -ne $OutBufferSize )
{
    Write-Output "`n[E] Size of structure is $PropertySize bytes, expect 612 bytes, stop";
    Return;
}

$Property.PropertyId    = 50; # StorageDeviceProtocolSpecificProperty
$Property.QueryType     = 0;  # PropertyStandardQuery
$Property.ProtocolType  = 3;  # ProtocolTypeNvme
$Property.DataType      = 2;  # NVMeDataTypeLogPage

$Property.ProtocolDataRequestValue      = 6; # NVME_LOG_PAGE_DEVICE_SELF_TEST
$Property.ProtocolDataRequestSubValue   = 0;

$Property.ProtocolDataOffset = 40;  # sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
$Property.ProtocolDataLength = 564; # sizeof(NVME_DEVICE_SELF_TEST_LOG)

$ByteRet = 0;
$IoControlCode = 0x2d1400; # IOCTL_STORAGE_QUERY_PROPERTY

[System.Runtime.InteropServices.Marshal]::StructureToPtr($Property, $OutBuffer, [System.Boolean]::false);
$CallResult = $KernelService::DeviceIoControl($DeviceHandle, $IoControlCode, $OutBuffer, $OutBufferSize, $OutBuffer, $OutBufferSize, [ref]$ByteRet, [System.IntPtr]::Zero);

$LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error();
if ( $CallResult -eq 0 )
{
    Write-Output "`n[E] DeviceIoControl() failed: $LastError";
    Return;
}

if ( $ByteRet -ne $OutBufferSize )
{
    Write-Output "`n[E] Data size returned ($ByteRet bytes) is wrong; expect $OutBufferSize bytes";
    Return;
}

Write-Output( "Device Self-test Information:" );
Write-Output( "" );

$u8CurrentStatus = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 48);
switch ( $u8CurrentStatus )
{
    0x0 { Write-Output( "byte [    0] Current Device Self-test Operation: 0x00 (No device self-test operation in progress)" ); }
    0x1 { Write-Output( "byte [    0] Current Device Self-test Operation: 0x01 (Short device self-test operation in progress)" ); }
    0x2 { Write-Output( "byte [    0] Current Device Self-test Operation: 0x02 (Extended device self-test operation in progress)" ); }
    0xE { Write-Output( "byte [    0] Current Device Self-test Operation: 0x0E (Vendor specific)" ); }
    default { Write-Output( "byte [    0] Current Device Self-test Operation: 0x0{0} (Unknown)" -F $u8CurrentStatus ); }
}

$u8CurrentCompletion = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, 49);
if ( $u8CurrentCompletion -eq 0 )
{
    Write-Output( "byte [    1] Current Device Self-test Completion: 0 (No test is in progress)" );
}
else
{
    Write-Output( "byte [    1] Current Device Self-test Completion: {0} ({1}% completed)" -F $u8CurrentCompletion, $u8CurrentCompletion );
}

$BaseOffset = 52

for ( $counter = 0; $counter -lt 20; $counter++ )
{
    $TestStatus = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $BaseOffset + $counter * 28);
    $TestResult = $TestStatus -band 0xF;
    if ( $TestResult -eq 0xF )
    {
        continue; # not valid entry
    }

    Write-Output( "" );
    Write-Output("Self-test Result Data #{0}:" -F $counter );
    Write-Output("    byte [    0] Device Self-test Status");
    switch ( $TestResult )
    {
        0x0 { Write-Output("        bit [ 3: 0] 0x0 = Completed without error"); }
        0x1 { Write-Output("        bit [ 3: 0] 0x1 = Aborted by a Device Self-test command"); }
        0x2 { Write-Output("        bit [ 3: 0] 0x2 = Aborted by a Controller Level Reset"); }
        0x3 { Write-Output("        bit [ 3: 0] 0x3 = Aborted due to a removal of a namespace from the namespace inventory"); }
        0x4 { Write-Output("        bit [ 3: 0] 0x4 = Aborted due to the processing of a Format NVM command"); }
        0x5 { Write-Output("        bit [ 3: 0] 0x5 = Did not complete due to fatal error or unknown test error"); }
        0x6 { Write-Output("        bit [ 3: 0] 0x6 = Completed with a failed segment (failed segment is unknown)"); }
        0x7 { Write-Output("        bit [ 3: 0] 0x7 = Completed with one or more failed segments (first failed segment is indicated in the Segment Number field)"); }
        0x8 { Write-Output("        bit [ 3: 0] 0x8 = Aborted for unknown reason"); }
        0xF { Write-Output("        bit [ 3: 0] 0xF = Entry not used (does not contain a test result)"); }
        default { Write-Output("        bit [ 3: 0] 0x%{0} = Reserved" -F $TestResult.ToString("X2") ); }
    }

    $TestType = ( ( $TestStatus -shr 4 ) -band 0xF );
    switch ( $TestType )
    {
        0x1 { Write-Output("        bit [ 7: 4] 0x1 = Short device self-test operation"); }
        0x2 { Write-Output("        bit [ 7: 4] 0x2 = Extended device self-test operation"); }
        0xE { Write-Output("        bit [ 7: 4] 0xE = Vendor specific"); }
        default { Write-Output("        bit [ 7: 4] 0x{0} = Reserved" -F $TestType.ToString("X2") ); }
    }

    $FailedSegment = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $BaseOffset + $counter * 28 + 1);
    Write-Output("    byte [    1] 0x{0} = Segment Number" -F $FailedSegment.ToString("X2") );

    $DiagInfo = [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $BaseOffset + $counter * 28 + 2);
    Write-Output("    byte [    2] Valid Diagnostic Information");
    if ( $DiagInfo -band 0x1 )
    {
        Write-Output("        bit [    0] 1 = Namespace Identifier field is valid");
    }
    else
    {
        Write-Output("        bit [    0] 0 = Namespace Identifier field is invalid");
    }
    if ( $DiagInfo -band 0x2 )
    {
        Write-Output("        bit [    1] 1 = Failing LBA field is valid");
    }
    else
    {
        Write-Output("        bit [    1] 0 = Failing LBA field is invalid");
    }
    if ( $DiagInfo -band 0x4 )
    {
        Write-Output("        bit [    2] 1 = Status Code Type field is valid");
    }
    else
    {
        Write-Output("        bit [    2] 0 = Status Code Type field is invalid");
    }
    if ( $DiagInfo -band 0x8 )
    {
        Write-Output("        bit [    3] 1 = Status Code field is valid");
    }
    else
    {
        Write-Output("        bit [    3] 0 = Status Code field is invalid");
    }

    Write-Output("    byte [11: 4] 0x{0} = Power On Hours" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, $BaseOffset + $counter * 28 + 4).ToString("X16") );

    if ( $DiagInfo -band 0x1 )
    {
        Write-Output("    byte [15:12] 0x{0} = Namespace Identifier" -F [System.Runtime.InteropServices.Marshal]::ReadInt32($OutBuffer, $BaseOffset + $counter * 28 + 12).ToString("X4") );
    }
    if ( $DiagInfo -band 0x2 )
    {
        Write-Output("    byte [23:16] 0x{0} = Failing LBA" -F [System.Runtime.InteropServices.Marshal]::ReadInt64($OutBuffer, $BaseOffset + $counter * 28 + 16).ToString("X8") );
    }
    if ( $DiagInfo -band 0x4 )
    {
        Write-Output("    byte [   24] 0x{0} = Status Code Type" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $BaseOffset + $counter * 28 + 24).ToString("X2") );
    }
    if ( $DiagInfo -band 0x8 )
    {
        Write-Output("    byte [   25] 0x{0} = Status Code" -F [System.Runtime.InteropServices.Marshal]::ReadByte($OutBuffer, $BaseOffset + $counter * 28 + 25).ToString("X2") );
    }

    Write-Output("    byte [27:26] 0x{0} = Vendor Specific" -F [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, $BaseOffset + $counter * 28 + 26).ToString("X4"));

}
[System.Runtime.InteropServices.Marshal]::FreeHGlobal($OutBuffer);
[void]$KernelService::CloseHandle($DeviceHandle);
