<#
get-temperature.ps1: Get Composite Temperature of NVMe drive from S.M.A.R.T. log data

Usage: ./get-temperature.ps1 -dno drive_no [-pd period] [-of filename] [-inK inKelvin]

    @arg[in]    drive_no    physical drive no to access (MANDATORY)
    @arg[in]    period      period in second if you want to get temperature periodically
    @arg[in]    filename    filename for output; if nothing is specified, no output is made to file
    @arg[in]    inKelvin    whether temperature is printed in Kelvin (1) or Celcius (0); default is 0 (Celcius)

Copyright (c) 2022 Kenichiro Yoshii
Copyright (c) 2022 Hagiwara Solutions Co., Ltd.
#>
Param(
    [parameter(mandatory)][Int]$dno,
    [Int]$pd = 0,
    [String]$of = "",
    [Int]$inK = 0
    )

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
}
"@

function GetCompositeTemperature {
    Param([parameter(mandatory)][Int]$dno)
    
    $retcode = 1; # 1: no error, 0: with error
    $rettemp = 0;

    $AccessMask = "3221225472"; # = 0xC00000000 = GENERIC_READ (0x80000000) | GENERIC_WRITE (0x40000000)
    $AccessMode = 3; # FILE_SHARE_READ | FILE_SHARE_WRITE
    $AccessEx   = 3; # OPEN_EXISTING
    $AccessAttr = 0x40; # FILE_ATTRIBUTE_DEVICE

    $DeviceHandle = $KernelService::CreateFile("\\.\PhysicalDrive$dno", [System.Convert]::ToUInt32($AccessMask), $AccessMode, [System.IntPtr]::Zero, $AccessEx, $AccessAttr, [System.IntPtr]::Zero);

    $LastError = [ComponentModel.Win32Exception][Runtime.InteropServices.Marshal]::GetLastWin32Error()
    if ($DeviceHandle -eq [System.IntPtr]::Zero) {
        Write-Host "`n[E] CreateFile failed: $LastError";
        Return $retcode, $rettemp;
    }

    # offsetof(STORAGE_PROPERTY_QUERY, AdditionalParameters)
    #  + sizeof(STORAGE_PROTOCOL_SPECIFIC_DATA)
    #  + sizeof(NVME_SMART_INFO_LOG) = 560
    $OutBufferSize = 8 + 40 + 512; # = 560
    $OutBuffer     = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($OutBufferSize);

    $Property      = New-Object NVMeStorageQueryProperty;
    $PropertySize  = [System.Runtime.InteropServices.Marshal]::SizeOf($Property);

    if ( $PropertySize -ne $OutBufferSize ) {
        Write-Host "`n[E] Size of structure is $PropertySize bytes, expect 560 bytes, stop";
        [void]$KernelService::CloseHandle($DeviceHandle);
        $retcode = 0;
        Return $retcode, $rettemp;
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
        Write-Host "`n[E] DeviceIoControl() failed: $LastError";
        $retcode = 0;
    } elseif ( $ByteRet -ne 560 ) {
        Write-Host "`n[E] Data size returned ($ByteRet bytes) is wrong; expect $OutBufferSize bytes";
        $retcode = 0;
    } else {
        $rettemp = [System.Runtime.InteropServices.Marshal]::ReadInt16($OutBuffer, 49);
    }

    [System.Runtime.InteropServices.Marshal]::FreeHGlobal($OutBuffer);
    [void]$KernelService::CloseHandle($DeviceHandle);
    Return $retcode, $rettemp;
}

# main routine

do {
    $ret = GetCompositeTemperature $dno

    if ( $ret[0] -eq 0 ) { break }; # error
    if ( $inK -eq 0 ) { $ret[1] -= 273; } # in Celcius

    $date = Get-Date -Format "hh:mm:ss";
    if ( -not [String]::IsNullOrEmpty($of) ) {
        Write-Output( "{0},{1}" -F $date, $ret[1] ) >> $of
    }
    Write-Host( "{0},{1}" -F $date, $ret[1] );

    Start-Sleep -Seconds $pd
} while( $pd )

