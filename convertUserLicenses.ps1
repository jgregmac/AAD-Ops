set-psdebug -Strict

$sku1 = Get-MsolAccountSku | ? {$_.accountSkuId -match 'STANDARDWOFFPACK_IW_STUDENT'}
$skuId1 = $sku1.AccountSkuId
#$sku2 = Get-MsolAccountSku | ? {$_.accountSkuId -match 'OFFICESUBSCRIPTION_STUDENT'}
#$skuId2 = $sku2.AccountSkuId
$stuLicOpts = New-MsolLicenseOptions -AccountSkuId $studAdv.AccountSkuId -DisabledPlans YAMMER_EDU,SHAREPOINTWAC_EDU,SHAREPOINTSTANDARD_EDU,EXCHANGE_S_STANDARD,MCOSTANDARD


$users = @()
$users += Get-MsolUser -Synchronized -All

foreach ($u in $users) {
    [bool] $convUser = $false
    $lics = @()
    $lics += $u.licenses
    foreach ($l in $lics) {
        if ($l.AccountSkuId -match 'STANDARDWOFFPACK_IW_STUDENT') {
        Write-Host "User: " $u.UserPrincipalName "needs license conversion."
        $convUser = $true
        }
    }
    if ($convUser) {
        Write-Host 'Attempting to change license options for user: ' $u.UserPrincipalName
        $u | Set-MsolUserLicense -LicenseOptions $stuLicOpts -ErrorAction Continue
        Write-Host 'Hurray!'
        Write-Host ''
    }
}
