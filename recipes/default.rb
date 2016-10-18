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
  command "#{File.join(node['7-zip']['home'], '7z.exe')} x -y -o\"#{winfriendly_extract_path}\" #{download_path}"
  only_if {!(::File.directory?(download_path)) }
end

template install_configuration_path do
  source 'Install.xml.erb'
end

windows_package node['commvault']['name'] do
	checksum node['commvault']['checksum']
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