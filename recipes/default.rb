#
# Cookbook Name:: commvault
# Recipe:: default
#
# Copyright (C) 2015 Taliesin Sisson
#
# All rights reserved - Do Not Redistribute
#
include_recipe '7-zip'

::Chef::Recipe.send(:include, Windows::Helper)

filename = File.basename(node['commvault']['url']).downcase
fileextension = File.extname(filename)
download_path = "#{Chef::Config['file_cache_path']}/#{filename}"
extract_path = "#{Chef::Config['file_cache_path']}/#{node['commvault']['filename']}/#{node['commvault']['checksum']}"
winfriendly_extract_path = win_friendly_path(extract_path)
install_path = "#{extract_path}"
install_configuration_path =  "#{install_path}/Install.xml"

remote_file download_path do
  source node['commvault']['url']
  checksum node['commvault']['checksum']
end

execute 'extract_commvault' do
  command "\"#{File.join(node['7-zip']['home'], '7z.exe')}\" x -y -o\"#{winfriendly_extract_path}\" \"#{download_path}\""
  only_if {!(::File.directory?(download_path)) }
end

template install_configuration_path do
  source 'Install.xml.erb'
end

windows_package node['commvault']['name'] do
	source "#{install_path}/Setup.exe"
	installer_type :custom
	options "/Silent /play \"#{install_configuration_path}\""
end

powershell_script 'Register client with comm vault server' do
    guard_interpreter :powershell_script
    code <<-EOH
$ErrorActionPreference="Stop"   

function Get-CommVaultCommandPath($cmd){
    $paths="#{node['commvault']['installDirectory']}",C:\\Program Files\\CommVault\\Simpana\\Base", "C:\\Program Files\\CommVault\\ContentStore\\Base"
    foreach ($path in $paths){
        $cmdPath = join-path $path "$($cmd).exe"

        if (Test-Path $cmdPath){
            $cmd = $cmdPath
            break
        }
    }

    return $cmd
}

function Register-CommVaultClientWithSimWrapper(
    $clientName,
    $clientHostName,
    $csName,
    $csHost,
    $instance,
    $username,
    $password,
    $encryptedPassword
){
    $cmd = Get-CommVaultCommandPath("SIMCallWrapper")

    $cmdArgs = "-OpType 1000 -CSName `"$csName`" -CSHost `"$csHost`" -instance `"$instance`" -output `"register.xml`" -registerme -skipCertificateRevoke"
    if ($clientName){
        $cmdArgs += " -clientName `"$clientName`""
    }
    if ($clientHostName){
        $cmdArgs += " -clientHostName `"$clientHostName`""
    }
    if ($username){
      $cmdArgs += " -user $username"
    }
    if ($password){
      $cmdArgs += " -password $password"
    }
    if ($encryptedPassword){
      $cmdArgs += " -passwordEncrypted $encryptedPassword"
    } 

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $cmd
    $pinfo.RedirectStandardError = $false
    $pinfo.RedirectStandardOutput = $false
    $pinfo.UseShellExecute = $true
    $pinfo.Arguments = $cmdArgs

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    if ($p.ExitCode -eq 150995043){
        $cmdArgs = "-OpType 1000 -CSName `"$csName`" -CSHost `"$csHost`" -instance `"$instance`" -output `"register.xml`" -registerme"
        if ($clientName){
          $cmdArgs += " -clientName `"$clientName`""
        }
        if ($clientHostName){
          $cmdArgs += " -clientHostName `"$clientHostName`""
        }
        if ($username){
          $cmdArgs += " -user $username"
        }
        if ($password){
          $cmdArgs += " -password $password"
        }
        if ($encryptedPassword){
          $cmdArgs += " -passwordEncrypted $encryptedPassword"
        } 

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $cmd
        $pinfo.RedirectStandardError = $false
        $pinfo.RedirectStandardOutput = $false
        $pinfo.UseShellExecute = $true
        $pinfo.Arguments = $cmdArgs

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
    }

    $errorMessage = ''
    if (Test-Path 'register.xml'){
        $errorMessage = Get-Content -Path 'register.xml'
    }

    if ($p.ExitCode -eq 150995043){
        throw "The client and server certificates do not match. Release license for the client and then delete it from CommVault server, then run again. Failed to join client to comm vault server. Exit code was $($p.ExitCode) $errorMessage"
    } elseif ($p.ExitCode -eq 67109051){
        throw "The client is unable to access the comm vault server. Check firewall between server and client/firewall on server and firewall on client. Exit code was $($p.ExitCode) $errorMessage"
    } elseif (($p.ExitCode -ne 0) -and ($p.ExitCode -ne -1)){
        throw "Failed to join client to comm vault server. Exit code was $($p.ExitCode) $errorMessage"
    }
}

function Open-CommVaultConnection(
    $username,
    $encryptedPassword,
    $commVaultHostName,
    $commVaultClientName
){
    $cmd = Get-CommVaultCommandPath("qlogin")

    $cmdArgs = "-u $username -ps $encryptedPassword -cs `"$commVaultHostName`" -csn `"$commVaultClientName`" -gt"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $cmd
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $cmdArgs

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    if ($p.ExitCode -ne 0){
        throw "Login failed. $stderr"
    }

    return $stdout
}

function Close-CommVaultConnection(
    $loginToken,
    $commVaultHostName
){
    $cmd = Get-CommVaultCommandPath("qlogout")

    $cmdArgs = "-cs `"$commVaultHostName`" -tk `"$loginToken`""

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $cmd
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $cmdArgs

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    if ($p.ExitCode -ne 0){
        throw "Logout failed. $stderr"
    }

    return $stdout
}

function Open-CommVaultConnection(
    $username,
    $password,
    $encryptedPassword,
    $commVaultHostName,
    $commVaultClientName,
    $commVaultDirectory = 'C:\\Program Files\\CommVault\\Simpana'
){
    $cmd = "qlogin"
    if (Test-Path (Join-Path $commVaultDirectory 'base\\QLogin.exe')){
        $cmd = Join-Path $commVaultDirectory 'base\\QLogin.exe'
    }

    $cmdArgs = "-cs `"$commVaultHostName`" -csn `"$commVaultClientName`" -gt"

    if ($username){
      $cmdArgs += " -u $username"
    }

    if ($password){
      $cmdArgs += " -p $password"
    }
    if ($encryptedPassword){
      $cmdArgs += " -ps $encryptedPassword"
    }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $cmd
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $cmdArgs

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    if ($p.ExitCode -ne 0){
        throw "Login failed. $stderr"
    }

    return $stdout
}

function Execute-CommVaultRegisterClient(
    $clientName,
    $clientHostName,
    $csName,
    $csHost,
    $instance,
    $username,
    $password,
    $encryptedPassword,
    $commVaultDirectory = 'C:\\Program Files\\CommVault\\Simpana'
){
    $cmd = "SIMCallWrapper"
    if (Test-Path (Join-Path $commVaultDirectory 'base\\SIMCallWrapper.exe')){
        $cmd = Join-Path $commVaultDirectory 'base\\SIMCallWrapper.exe'
    }

    $cmdArgs = "-OpType 1000 -clientName $clientName -clientHostName $clientHostName -CSName $csName -CSHost $csHost -instance $instance -output register.xml -registerme -skipCertificateRevoke"
    if ($username){
      $cmdArgs += " -user $username"
    }
    if ($password){
      $cmdArgs += " -password $password"
    }
    if ($encryptedPassword){
      $cmdArgs += " -passwordEncrypted $encryptedPassword"
    } 

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $cmd
    $pinfo.RedirectStandardError = $false
    $pinfo.RedirectStandardOutput = $false
    $pinfo.UseShellExecute = $true
    $pinfo.Arguments = $cmdArgs

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    if ($p.ExitCode -eq 150995043){
        $cmdArgs = "-OpType 1000 -clientName $clientName -clientHostName $clientHostName -CSName $csName -CSHost $csHost -instance $instance -output register.xml -registerme"
        if ($username){
          $cmdArgs += " -user $username"
        }
        if ($password){
          $cmdArgs += " -password $password"
        }
        if ($encryptedPassword){
          $cmdArgs += " -passwordEncrypted $encryptedPassword"
        } 

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $cmd
        $pinfo.RedirectStandardError = $false
        $pinfo.RedirectStandardOutput = $false
        $pinfo.UseShellExecute = $true
        $pinfo.Arguments = $cmdArgs

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()
    }

    if ($p.ExitCode -eq 150995043){
        throw "The client and server certificates do not match. Release license for the client and then delete it from CommVault server, then run again. Failed to join client to comm vault server. Exit code was $($p.ExitCode)"
    } elseif (($p.ExitCode -ne 0) -and ($p.ExitCode -ne -1)){
        throw "Failed to join client to comm vault server. Exit code was $($p.ExitCode)"
    }
}

function Register-CommVaultClient(
    $loginToken,
    $commVaultHostName,
    $clientHostName
) {
    $cmd = Get-CommVaultCommandPath("qoperation")

    $cmdArgs = "register -cs `"$commVaultHostName`" -hn `"$clientHostName`" -tk `"$loginToken`" -dock yes"

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $cmd
    $pinfo.RedirectStandardError = $true
    $pinfo.RedirectStandardOutput = $true
    $pinfo.UseShellExecute = $false
    $pinfo.Arguments = $cmdArgs

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $pinfo
    $p.Start() | Out-Null
    $p.WaitForExit()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    if ($p.ExitCode -ne 0){
        throw "Register client failed. $stderr"
    }

    return $stdout    
}

function Get-CommVaultClientsForGroup(
    $loginToken,
    $commVaultHostName,
    $clientGroupName
){
    $tmpFile = [System.IO.Path]::GetTempFileName() + ".xml"

    $cmd = Get-CommVaultCommandPath("qlist")

    $cmdArgs = "client -cs `"$commVaultHostName`" -tk `"$loginToken`""

    if ($clientGroupName) {
        $cmdArgs = " -cg `"$clientGroupName`""
    }

    try {
        if (Test-Path $tmpFile) {
            Remove-Item -Path $tmpFile
        }
        Write-Output $xml | Out-File $tmpFile -Encoding utf8

        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $cmd
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.Arguments = $cmdArgs

        $p = New-Object System.Diagnostics.Process
        $p.StartInfo = $pinfo
        $p.Start() | Out-Null
        $p.WaitForExit()

        $stdout = $p.StandardOutput.ReadToEnd()
        $stderr = $p.StandardError.ReadToEnd()
    }
    finally{
        if (Test-Path $tmpFile) {
            Remove-Item -Path $tmpFile
        }
    }

    if ($p.ExitCode -ne 0){
        throw "Failed to execute operation. $stderr"
    }

    $clients = $stdout -split '\\r\\n' | select -skip 2 | ?{$_ -ne ''}
    return $clients
}

function Test-CommVaultClientForGroup(
    $loginToken,
    $commVaultHostName,
    $clientName,
    $clientGroupName
){
    $client = Get-CommVaultClientsForGroup -loginToken $loginToken -commVaultHostName $commVaultHostName -clientGroupName $clientGroupName | %{$_.ToLower() -eq $clientName.ToLower()}

    if ($client) {
        return $true
    }

    return $false
}

$clientName = '#{node['commvault']['client']['clientName']}'
$clientHostName = '#{node['commvault']['client']['hostName']}'
$csName = '#{node['commvault']['server']['clientName']}'
$csHost = '#{node['commvault']['server']['hostName']}'
$commVaultHostName = $csHost
$commVaultClientName = $csName
$clientGroupName = 'APP - Portal Dynamic'
$instance = '#{node['commvault']['instanceName']}'
$username = '#{node['commvault']['client']['domainName']}\\#{node['commvault']['client']['userName']}'
$password = ''
$clientGroupName = '#{node['commvault']['client']['groupName']}'
$encryptedPassword = '#{node['commvault']['client']['encryptedPassword']}'

try{
    $loginToken = Open-CommVaultConnection -username $username -encryptedPassword $encryptedPassword -commVaultHostName $commVaultHostName -commVaultClientName $commVaultClientName
    if (Test-CommVaultClientForGroup -loginToken $loginToken -commVaultHostName $commVaultHostName -clientGroupName $clientGroupName -clientName $clientName){
        Write-Host 'Client registered'
    } else {
        Write-Host 'Client not registered'
        Register-CommVaultClient -loginToken $loginToken -commVaultHostName $commVaultHostName -clientName $clientName
    }
    Close-CommVaultConnection -loginToken $loginToken -commVaultHostName $commVaultHostName
} catch {
    Register-CommVaultClientWithSimWrapper -clientName $clientName -clientHostName $clientHostName -csName $csName -csHost $csHost -instance $instance -username $username -encryptedPassword $encryptedPassword
}

Exit 0
    EOH
  	action :run
	not_if { node['commvault']['installFlags']['decoupledInstall'] == '0'}
end    

#PS C:\Program Files\CommVault\Simpana\Base> get-item *.exe | %{ $_.Name -replace '.exe'  } | %{ "windows_firewall_rule 'CommVault_Process_$_' do`r`n`tprogram `"#{node['commvault']['installDirectory']}\\$_.exe`"`r`n`tfirewall_action :allow`r`nend`r`n"} | clip

windows_firewall_rule 'CommVault_Process_7z' do
    program "#{node['commvault']['installDirectory']}\\7z.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_adLdapTool' do
    program "#{node['commvault']['installDirectory']}\\adLdapTool.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_AuditQiNetix' do
    program "#{node['commvault']['installDirectory']}\\AuditQiNetix.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_AuthorUtil' do
    program "#{node['commvault']['installDirectory']}\\AuthorUtil.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_BLKWinSetup' do
    program "#{node['commvault']['installDirectory']}\\BLKWinSetup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_BlockRestore' do
    program "#{node['commvault']['installDirectory']}\\BlockRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CLAFRestore' do
    program "#{node['commvault']['installDirectory']}\\CLAFRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CLBackup' do
    program "#{node['commvault']['installDirectory']}\\CLBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_clBackupXP' do
    program "#{node['commvault']['installDirectory']}\\clBackupXP.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CLDBengine' do
    program "#{node['commvault']['installDirectory']}\\CLDBengine.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ClDctmFTIBackup' do
    program "#{node['commvault']['installDirectory']}\\ClDctmFTIBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ClDctmScan' do
    program "#{node['commvault']['installDirectory']}\\ClDctmScan.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CLIFRestore' do
    program "#{node['commvault']['installDirectory']}\\CLIFRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ClMgrS' do
    program "#{node['commvault']['installDirectory']}\\ClMgrS.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CLReboot' do
    program "#{node['commvault']['installDirectory']}\\CLReboot.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CLRestore' do
    program "#{node['commvault']['installDirectory']}\\CLRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ConfigureClientTool' do
    program "#{node['commvault']['installDirectory']}\\ConfigureClientTool.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVBlkLevelBackup' do
    program "#{node['commvault']['installDirectory']}\\CVBlkLevelBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVCacheSet' do
    program "#{node['commvault']['installDirectory']}\\CVCacheSet.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVClusterNotify' do
    program "#{node['commvault']['installDirectory']}\\CVClusterNotify.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_cvcl_test' do
    program "#{node['commvault']['installDirectory']}\\cvcl_test.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_cvcl_ver' do
    program "#{node['commvault']['installDirectory']}\\cvcl_ver.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVConvertUnicode' do
    program "#{node['commvault']['installDirectory']}\\CVConvertUnicode.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_cvd' do
    program "#{node['commvault']['installDirectory']}\\cvd.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvDiagnostics' do
    program "#{node['commvault']['installDirectory']}\\CvDiagnostics.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVDiskPerf' do
    program "#{node['commvault']['installDirectory']}\\CVDiskPerf.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVExpPluginRegSvr' do
    program "#{node['commvault']['installDirectory']}\\CVExpPluginRegSvr.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVForeignHandler' do
    program "#{node['commvault']['installDirectory']}\\CVForeignHandler.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVFSSnap' do
    program "#{node['commvault']['installDirectory']}\\CVFSSnap.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVGACUtil' do
    program "#{node['commvault']['installDirectory']}\\CVGACUtil.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVGACUtil40' do
    program "#{node['commvault']['installDirectory']}\\CVGACUtil40.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVIPInfo' do
    program "#{node['commvault']['installDirectory']}\\CVIPInfo.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVLegalHold' do
    program "#{node['commvault']['installDirectory']}\\CVLegalHold.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVMapDrive' do
    program "#{node['commvault']['installDirectory']}\\CVMapDrive.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVMountImage' do
    program "#{node['commvault']['installDirectory']}\\CVMountImage.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVNetChk' do
    program "#{node['commvault']['installDirectory']}\\CVNetChk.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVNetworkTestTool' do
    program "#{node['commvault']['installDirectory']}\\CVNetworkTestTool.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVNRDS' do
    program "#{node['commvault']['installDirectory']}\\CVNRDS.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVODS' do
    program "#{node['commvault']['installDirectory']}\\CVODS.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVPing' do
    program "#{node['commvault']['installDirectory']}\\CVPing.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVPLink' do
    program "#{node['commvault']['installDirectory']}\\CVPLink.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvPostOps' do
    program "#{node['commvault']['installDirectory']}\\CvPostOps.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVPSCP' do
    program "#{node['commvault']['installDirectory']}\\CVPSCP.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVRenameDirChange' do
    program "#{node['commvault']['installDirectory']}\\CVRenameDirChange.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVRestart' do
    program "#{node['commvault']['installDirectory']}\\CVRestart.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVRetrieveResults' do
    program "#{node['commvault']['installDirectory']}\\CVRetrieveResults.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_cvsleep' do
    program "#{node['commvault']['installDirectory']}\\cvsleep.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVSPBackup' do
    program "#{node['commvault']['installDirectory']}\\CVSPBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVSPBackup2013' do
    program "#{node['commvault']['installDirectory']}\\CVSPBackup2013.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLAddInConfig' do
    program "#{node['commvault']['installDirectory']}\\CvSQLAddInConfig.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLBackup' do
    program "#{node['commvault']['installDirectory']}\\CvSQLBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLBackupProxy' do
    program "#{node['commvault']['installDirectory']}\\CvSQLBackupProxy.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLBackupUtility' do
    program "#{node['commvault']['installDirectory']}\\CvSQLBackupUtility.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVSQLDBArchive' do
    program "#{node['commvault']['installDirectory']}\\CVSQLDBArchive.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVSQLDBBackup' do
    program "#{node['commvault']['installDirectory']}\\CVSQLDBBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSqlLogBackupUtility' do
    program "#{node['commvault']['installDirectory']}\\CvSqlLogBackupUtility.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLQCmd' do
    program "#{node['commvault']['installDirectory']}\\CvSQLQCmd.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLRestore' do
    program "#{node['commvault']['installDirectory']}\\CvSQLRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSQLRestoreProxy' do
    program "#{node['commvault']['installDirectory']}\\CvSQLRestoreProxy.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVSVCStat' do
    program "#{node['commvault']['installDirectory']}\\CVSVCStat.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CvSyncProxy' do
    program "#{node['commvault']['installDirectory']}\\CvSyncProxy.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVSystemTray' do
    program "#{node['commvault']['installDirectory']}\\CVSystemTray.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVVDTool' do
    program "#{node['commvault']['installDirectory']}\\CVVDTool.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVVersion' do
    program "#{node['commvault']['installDirectory']}\\CVVersion.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVVICleanup' do
    program "#{node['commvault']['installDirectory']}\\CVVICleanup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVVIRestore' do
    program "#{node['commvault']['installDirectory']}\\CVVIRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_CVVSSnap' do
    program "#{node['commvault']['installDirectory']}\\CVVSSnap.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_DlpRecaller' do
    program "#{node['commvault']['installDirectory']}\\DlpRecaller.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_DM2ExMBRestore' do
    program "#{node['commvault']['installDirectory']}\\DM2ExMBRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_DM2SPDocRestore' do
    program "#{node['commvault']['installDirectory']}\\DM2SPDocRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_DM2ZipFiles' do
    program "#{node['commvault']['installDirectory']}\\DM2ZipFiles.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_dmc' do
    program "#{node['commvault']['installDirectory']}\\dmc.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_DriverInstaller' do
    program "#{node['commvault']['installDirectory']}\\DriverInstaller.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ExIntegCheck' do
    program "#{node['commvault']['installDirectory']}\\ExIntegCheck.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_exitNTbat' do
    program "#{node['commvault']['installDirectory']}\\exitNTbat.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_FailOverSetup' do
    program "#{node['commvault']['installDirectory']}\\FailOverSetup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_FirewallConfigDeprecated' do
    program "#{node['commvault']['installDirectory']}\\FirewallConfigDeprecated.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_FSVSSRestore' do
    program "#{node['commvault']['installDirectory']}\\FSVSSRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_getBackupList' do
    program "#{node['commvault']['installDirectory']}\\getBackupList.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GxAdmin' do
    program "#{node['commvault']['installDirectory']}\\GxAdmin.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GXHSMPopup' do
    program "#{node['commvault']['installDirectory']}\\GXHSMPopup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GXHSMSelDel' do
    program "#{node['commvault']['installDirectory']}\\GXHSMSelDel.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GXHSMStub' do
    program "#{node['commvault']['installDirectory']}\\GXHSMStub.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GXHSMUtility' do
    program "#{node['commvault']['installDirectory']}\\GXHSMUtility.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GxKill' do
    program "#{node['commvault']['installDirectory']}\\GxKill.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GxSplash' do
    program "#{node['commvault']['installDirectory']}\\GxSplash.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GxTail' do
    program "#{node['commvault']['installDirectory']}\\GxTail.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_GxWinClusterPlugin' do
    program "#{node['commvault']['installDirectory']}\\GxWinClusterPlugin.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_IFind' do
    program "#{node['commvault']['installDirectory']}\\IFind.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ImgFileLvlRestore' do
    program "#{node['commvault']['installDirectory']}\\ImgFileLvlRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_IndexingService' do
    program "#{node['commvault']['installDirectory']}\\IndexingService.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_InstallUpdates' do
    program "#{node['commvault']['installDirectory']}\\InstallUpdates.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_Laptop2Taskbaricon' do
    program "#{node['commvault']['installDirectory']}\\Laptop2Taskbaricon.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_ListFilesForJob' do
    program "#{node['commvault']['installDirectory']}\\ListFilesForJob.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_LogMonitoring' do
    program "#{node['commvault']['installDirectory']}\\LogMonitoring.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_MigrationAssistant' do
    program "#{node['commvault']['installDirectory']}\\MigrationAssistant.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_MoveDDBClientCacheClient' do
    program "#{node['commvault']['installDirectory']}\\MoveDDBClientCacheClient.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_MoveDir' do
    program "#{node['commvault']['installDirectory']}\\MoveDir.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_MSIRemoveOrphanedRegKeys' do
    program "#{node['commvault']['installDirectory']}\\MSIRemoveOrphanedRegKeys.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_OneTchUtl' do
    program "#{node['commvault']['installDirectory']}\\OneTchUtl.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_OneTouch' do
    program "#{node['commvault']['installDirectory']}\\OneTouch.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_PassPhraseTool' do
    program "#{node['commvault']['installDirectory']}\\PassPhraseTool.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_PseudoMountClient' do
    program "#{node['commvault']['installDirectory']}\\PseudoMountClient.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QCreate' do
    program "#{node['commvault']['installDirectory']}\\QCreate.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QCURL' do
    program "#{node['commvault']['installDirectory']}\\QCURL.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QDelete' do
    program "#{node['commvault']['installDirectory']}\\QDelete.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QDrive' do
    program "#{node['commvault']['installDirectory']}\\QDrive.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QGetErrorString' do
    program "#{node['commvault']['installDirectory']}\\QGetErrorString.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QInfo' do
    program "#{node['commvault']['installDirectory']}\\QInfo.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QLibrary' do
    program "#{node['commvault']['installDirectory']}\\QLibrary.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QList' do
    program "#{node['commvault']['installDirectory']}\\QList.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QLogin' do
    program "#{node['commvault']['installDirectory']}\\QLogin.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QLogout' do
    program "#{node['commvault']['installDirectory']}\\QLogout.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QMedia' do
    program "#{node['commvault']['installDirectory']}\\QMedia.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QModify' do
    program "#{node['commvault']['installDirectory']}\\QModify.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QOperation' do
    program "#{node['commvault']['installDirectory']}\\QOperation.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QSCM' do
    program "#{node['commvault']['installDirectory']}\\QSCM.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QST2' do
    program "#{node['commvault']['installDirectory']}\\QST2.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QUninstallAll' do
    program "#{node['commvault']['installDirectory']}\\QUninstallAll.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_QUninstaller' do
    program "#{node['commvault']['installDirectory']}\\QUninstaller.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_Remotc' do
    program "#{node['commvault']['installDirectory']}\\Remotc.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_RemoveUpdates' do
    program "#{node['commvault']['installDirectory']}\\RemoveUpdates.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_restoreClusterDb' do
    program "#{node['commvault']['installDirectory']}\\restoreClusterDb.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_SetPreImagedNames' do
    program "#{node['commvault']['installDirectory']}\\SetPreImagedNames.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_SIMCallWrapper' do
    program "#{node['commvault']['installDirectory']}\\SIMCallWrapper.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_SQLBackup' do
    program "#{node['commvault']['installDirectory']}\\SQLBackup.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_SQLBackupMaster' do
    program "#{node['commvault']['installDirectory']}\\SQLBackupMaster.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_SQLVSSRestore' do
    program "#{node['commvault']['installDirectory']}\\SQLVSSRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_StubRecaller' do
    program "#{node['commvault']['installDirectory']}\\StubRecaller.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_syncRegKeys' do
    program "#{node['commvault']['installDirectory']}\\syncRegKeys.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_unzip' do
    program "#{node['commvault']['installDirectory']}\\unzip.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_UpdateNotificationCenter' do
    program "#{node['commvault']['installDirectory']}\\UpdateNotificationCenter.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_VMWareSnapRestore' do
    program "#{node['commvault']['installDirectory']}\\VMWareSnapRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_VSAAppNotifier' do
    program "#{node['commvault']['installDirectory']}\\VSAAppNotifier.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_w2dbRestore' do
    program "#{node['commvault']['installDirectory']}\\w2dbRestore.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_WinSysMonSetupTool' do
    program "#{node['commvault']['installDirectory']}\\WinSysMonSetupTool.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_XMLParser' do
    program "#{node['commvault']['installDirectory']}\\XMLParser.exe"
    firewall_action :allow
end

windows_firewall_rule 'CommVault_Process_zip' do
    program "#{node['commvault']['installDirectory']}\\zip.exe"
    firewall_action :allow
end