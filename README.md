# nvmetool-win-powershell: Sample script of accessing NVMe drive using Windows' inbox NVMe driver

## Abstract
Powershell scripts demonstrate issuing NVMe commands to NVMe drive using Windows' inbox NVMe device driver.

## Script list

Scripts are stored in the directory `scripts`.

Table 1. List of scripts

|         script name | Description                 | Note |
| ------------------: | :---------------------------|:-----|
| `get-smart-log.ps1` | Getting S.M.A.R.T. Log Data | refered to NVMe 1.4b[1] |
| `get-subnqn.ps1`    | Retrieving "Serial Number", "Model Name (Number)", "Firmware Revision", and "NVM Subsystem NVMe Qualified Name" from Identify Controller Data |
| `get-command-supported.ps1` | Scan Command Supported and Effects log page (excludes vendor specific commands, ZNS and KVS), refered to NVMe 2.0a[2] |
| `get-selftest-log.ps1` | Retrieve Device Self-test log data (valid entries only) |
| `get-temperature.ps1` | Get and print Composite Temperature periodically |

## Note

Privileged access is required to run the scripts.

## Environment

Confirmed on the following environment:

```powershell
PS C:\users\k-yoshii> $PSVersionTable

Name                           Value
----                           -----
PSVersion                      5.1.19041.1682
PSEdition                      Desktop
PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0...}
BuildVersion                   10.0.19041.1682
CLRVersion                     4.0.30319.42000
WSManStackVersion              3.0
PSRemotingProtocolVersion      2.3
SerializationVersion           1.1.0.1
```

* Tested operating system and device driver
  * Windows 10 Pro 64bit (Version 21H2, Build 19043.1682)
    * stornvme.sys (version 10.0.19041.1566, WinBuild 160101.0800)
  * Windows 11 Pro 64bit (Version 21H2, Build 22000.132)
    * stornvme.sys (version 10.0.22000.132, WinBuild 160101.0800)

## Limitations

Only tested with the NVMe drive directly attached to PC via PCIe.

It is ok to access to M.2 drives and M.2 drives that attached to M.2-PCIe converter Add-In-Card (AIC).

Also, it may be ok with U.2 drives.

But it may not work over protocol translations such as usb-nvme.

## To run scripts

```powershell
PS C:\> ./<script name> <PhysicalDriveNo>
```

You can find `PhysicalDriveNo` in "Disk Management" utility.

See comments in each script for further information.

## License
Scripts are released under the MIT License, see LICENSE.

## References
[1] NVM Express, _"NVM Express\[TM\] Base Specification"_, Revision 1.4b, Sept. 21, 2020

[2] NVM Express, _"NVM Express\[TM\] Base Specification"_, Revision 2.0a, July 26, 2021
