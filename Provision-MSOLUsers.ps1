# Provision-MSOLUsers.ps1 script, by J. Greg Mackinnon, 2014-07-30
# Updated 2014-11-20, new license SKU, corrections to error capture commands, and stronger typing of variables.
# Updated 2014-11-21, added "license options" package to the add license command, for granular service provisioning.
# Updated 2014-12-22, Now provisions student, faculty, and staff Office 365 Pro Plus with different SKUs.
#
# Provisions all active student accounts in Active Directory with an Office 365 ProPlus license.
#
# Requires:
# - PowerShell Module "MSOnline"
# - PowerShell Module "ActiveDirectory"
# - Azure AD account with rights to read account information and set license status
# - Credentials for this account, with password saved in a file, as detailed below.
# - Script runs as a user with rights to read the eduPersonAffiliation property of all accounts in Active Directory.
#
#    Create a credential file using the following procedure:
#    1. Log in as the user that will execute the script.
#    2. Execute the following line of code in PowerShell:
#    ConvertTo-SecureString -String 'password' -AsPlainText -Force | ConvertFrom-SecureString | out-file "c:\local\scripts\msolCreds.txt" -Force
#

Set-PSDebug -Strict

#### Local Variables, modify for your environment: ####
#
# Mail options:
[string] $to           = 'saa-ad@uvm.edu'
[string] $from         = 'Provisioning@skyport.campus.ad.uvm.edu'
[string] $smtp         = 'smtp.uvm.edu'
# Logging: 
[string] $logFQPath    = 'c:\local\temp\provision-MSOLUsers.log'
# MSOL Credentials:
[string] $msolUser     = 'uvm.dirsync@uvmoffice.onmicrosoft.com'
[string] $msolCredPath = 'C:\local\scripts\msolCreds.txt'
[string] $searchBase   = 'ou=people,dc=campus,dc=ad,dc=uvm,dc=edu'
[string] $ea1Filter    = '(&(ObjectClass=inetOrgPerson)(|(extensionAttribute1=*Student*)(extensionAttribute1=*Staff*)(extensionAttribute1=*Faculty*)))'
### Example Filters:
# Filter for all fac/staff/students: 
#   (&(ObjectClass=inetOrgPerson)(|(extensionAttribute1=*Student*)(extensionAttribute1=*Staff*)(extensionAttribute1=*Faculty*)))
# Filter for just students:
#   (&(ObjectClass=inetOrgPerson)(extensionAttribute1=*Student*))
#
#### End Local Variables ##############################


#### Initialize logging and script variables: #########
#initialize log and counter:
[string[]] $log = @()
[long] $pCount = 0

#initialize logging:

New-Item -Path $logFQPath -ItemType file -Force

[DateTime] $sTime = get-date
$log += "Provisioning report for Office 365/Azure AD for: " + ($sTime.ToString()) + "`r`n"


#### Define Functions:  ###############################
#
function errLogMail ($err,$msg) {
    # Write error to log and e-mail function
    # Writes out the error object in $err to the global $log object.
    # Flushes the contents of the $log array to file, 
    # E-mails the log contents to the mail address specified in $to.
    [string] $except = $err.exception;
    [string] $invoke = $err.invocationInfo.Line;
    [string] $posMsg = $err.InvocationInfo.PositionMessage;
    $log +=  $msg + "`r`n`r`nException: `r`n$except `r`n`r`nError Position: `r`n$posMsg";
    $log | Out-File -FilePath $logFQPath -Append;
    [string] $subj = 'Office 365 Provisioning Script:  ERROR'
    [string] $body = $log | % {$_ + "`r`n"}
    Send-MailMessage -To $to -From $from -Subject $subj -Body $body -SmtpServer $smtp
}

function licReport ($sku) {  
    $script:log += 'License report for: ' + $sku.AccountSkuId 
    $total = $sku.ActiveUnits
    $consumed = $sku.ConsumedUnits
    $script:log += 'Total licenses: ' + $total  
    $script:log += 'Consumed licenses: ' + $consumed  
    [int32] $alCount = $total - $consumed
    $script:log += 'Remaining licenses: ' + $alCount.toString() + "`r`n"
}
#
#### End Functions  ###################################

#Import PS Modules used by this script:
try {
    Import-Module MSOnline -ErrorAction Stop ;
} catch {
    $myError = $_
    [string] $myMsg = "Error encountered loading Azure AD (MSOnline) PowerShell module."
    errLogMail $myError $myMsg
    exit 101
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop ;
} catch {
    $myError = $_
    [string] $myMsg = "Error encountered loading ActiveDirectory PowerShell module."
    errLogMail $myError $myMsg
    exit 102
}

#Get credentials for use with MS Online Services:
try {
    $msolPwd = get-content $msolCredPath | convertto-securestring -ErrorAction Stop ;
} catch {
    $myError = $_
    [string] $myMsg = "Error encountered getting creds from file."
    errLogMail $myError $myMsg
    exit 110
}

try {
    $msolCreds = New-Object System.Management.Automation.PSCredential ($msolUser, $msolPwd) -ErrorAction Stop ;
} catch {
    $myError = $_
    [string] $myMsg = "Error encountered in generating credential object."
    errLogMail $myError $myMsg
    exit 120
}
#Use the following credential command instead of the block above if running this script interactively:
#$msolCreds = get-credential

#Connect to MS Online Services:
try {
    #ErrorAction set to "Stop" for force any errors to be terminating errors.
    # default behavior for connection errors is non-terminating, so the "catch" block will not be processed.
    Connect-MsolService -Credential $msolCreds -ErrorAction Stop
} catch {
    $myError = $_
    [string] $myMsg = "Error encountered in connecting to MSOL Services."
    errLogMail $myError $myMsg
    exit 130
}
$log += "Connected to MS Online Services.`r`n"

#Generate license report:
$studAdv = Get-MsolAccountSku | ? {$_.accountSkuId -match 'STANDARDWOFFPACK_IW_STUDENT'}  
$facStaffBene = Get-MsolAccountSku | ? {$_.accountSkuId -match 'OFFICESUBSCRIPTION_FACULTY'} 
licReport($studAdv)
licReport($facStaffBene)

#Set license options for student and faculty/staff SKUs: 
# NOTE: License options for a SKU can be enumerated by examining the "ServiceStatus" property of the MsolAccountSku objects fetched above using "Get-MsolAccountSku".
$stuLicOpts = New-MsolLicenseOptions -AccountSkuId $studAdv.AccountSkuId -DisabledPlans YAMMER_EDU,SHAREPOINTWAC_EDU,SHAREPOINTSTANDARD_EDU,EXCHANGE_S_STANDARD,MCOSTANDARD
$facStaffLicOpts = New-MsolLicenseOptions -AccountSkuId $facStaffBene.AccountSkuId -DisabledPlans ONEDRIVESTANDARD

#Retrieve active fac/staff/student accounts into a hashtable:
[hashtable] $adAccounts = @{}
try {
    #$NOTE:  The filter used for collecting students needed to be modified to fetch admitted students that are not yet active
    #   This is a 'hack' implemented by FCS to address the tendency for the registrar not to change student status until the first day of class.
    #   (Actual student count should be lower, but we have no way to know what the final count will be until the first day of classes.)
    #
    #get-aduser -LdapFilter '(&(ObjectClass=inetOrgPerson)(eduPersonAffiliation=Student))' -SearchBase 'ou=people,dc=campus,dc=ad,dc=uvm,dc=edu' -SearchScope Subtree -ErrorAction Stop | % {$students.Add($_.userPrincipalName,$_.Enabled)}
    get-aduser -LdapFilter $ea1Filter -Properties extensionAttribute1 -SearchBase $searchBase -SearchScope Subtree -ErrorAction Stop | ? {$_.Enabled -eq $true} | % {$adAccounts.Add($_.userPrincipalName,$_.extensionAttribute1)}
} catch {
    $myError = $_
    $myMsg = "Error encountered in reading accounts from Active Directory."
    errLogMail $myError $myMsg
    exit 200
}
$log += "Retrieved accounts from Active Directory."
$log += "Current account count: " + $adAccounts.count


#Retrieve unprovisioned accounts from Azure AD:
[array] $ulUsers = @()
try {
    #Note use of "Synchronized" to suppress processing of cloud-only accounts.
    $ulUsers += Get-MsolUser -UnlicensedUsersOnly -Synchronized -All -errorAction Stop
} catch {
    $myError = $_
    $myMsg = "Error encountered in reading accounts from Azure AD. "
    errLogMail $myError $myMsg
    exit 300
}
$log += "Retrieved unlicensed MSOL users."
$log += "Unlicensed user count: " + $ulUsers.Count + "`r`n"

#Provision any account in $ulUsers that also is in the $adAccounts array:
foreach ($u in $ulUsers) {
    #Lookup current unlicensed user in the AD account hashtable:
    $acct = $adAccounts.item($u.UserPrincipalName)
    if ($acct -ne $null) {
        #Uncomment to enable verbose logging of user to be processed.
        #$log += $u.UserPrincipalName + " is an active student."
        try {
            if ($u.UsageLocation -notmatch 'US') {
                #Set the usage location to the US... this is a prerequisite to assigning licenses.
                $u | Set-MsolUser -UsageLocation 'US' -ErrorAction Stop ;
                #Uncomment to enable verbose logging of usage location assignments.
                #$log += 'Successfully set them usage location for the user. '
            }
        } catch {
            $myError = $_
            $myMsg = "Error encountered in setting Office 365 usage location to user. "
            errLogMail $myError $myMsg
            exit 410
        }
        try {
            # Note: Order of if/elseif logic determines which SKU "wins" for people with multiple affiliations (both student and faculty/staff)
            # At present student affiliation "wins", which is preferable because we have 1 million student licenses and only 6 thousand fac/staff.
            # If we change licensing options in the future, we will want to revisit this logic.
            if ($acct -match 'Student') {
                #Uncomment to enable verbose logging of Student license assignments.
                #$log += 'Setting Student license options for user...'
                $u | Set-MsolUserLicense -AddLicenses $studAdv.AccountSkuId -LicenseOptions $stuLicOpts -ErrorAction Stop ;
            } elseif ($acct -match 'Faculty|Staff') {
                #Uncomment to enable verbose logging of Fac/Staff license assignments.
                #$log += 'Setting Fac/Staff license options for user...'
                #Assign the student advantage license to the user, with desired license options
                $u | Set-MsolUserLicense -AddLicenses $facStaffBene.AccountSkuId -LicenseOptions $facStaffLicOpts -ErrorAction Stop ;
            }
            #Uncomment to enable verbose logging of license assignments.
            #$log += 'Successfully set the Office license for user: ' + $u.UserPrincipalName
            $pCount += 1
        } catch {
            $myError = $_
            $myMsg = "Error encountered in assigning Office 365 license to user. "
            errLogMail $myError $myMsg
            exit 420
        }
    } else {
        $log += $u.UserPrincipalName + " does not have an active AD account.  Skipped Provisioning."
    }
    Remove-Variable acct
}

#Add reporting details to the log:
$eTime = Get-Date
$log += "`r`nProvisioning successfully completed at: " + ($eTime.ToString())
$log += "Provisioned $pCount accounts."
$tTime = new-timespan -Start $stime -End $etime
$log += 'Elapsed Time (hh:mm:ss): ' + $tTime.Hours + ':' + $tTime.Minutes + ':' + $tTime.Seconds

#Flush out the log and mail it:
$log | Out-File -FilePath $logFQPath -Append;
[string] $subj = 'Office 365 Provisioning Script:  SUCCESS'
[string] $body = $log | % {$_ + "`r`n"}
Send-MailMessage -To $to -From $from -Subject $subj -Body $body -SmtpServer $smtp
