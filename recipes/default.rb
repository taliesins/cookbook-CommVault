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
install_path = "#{extract_path}/#{node['commvault']['packagename']}/#{node['commvault']['filename']}/#{node['commvault']['packagetype']}"
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

$clientName = '#{node['commvault']['client']['clientName']}'
$clientHostName = '#{node['commvault']['client']['hostName']}'
$csName = '#{node['commvault']['server']['clientName']}'
$csHost = '#{node['commvault']['server']['hostName']}'
$instance = '#{node['commvault']['instanceName']}'
$username = '#{node['commvault']['commcelluser']['username']}'
$password = '#{node['commvault']['commcelluser']['password']}'
$encryptedPassword = '#{node['commvault']['commcelluser']['encryptedpassword']}'
$commVaultDirectory = '#{node['commvault']['installDirectory']}'

Execute-CommVaultRegisterClient -clientName $clientName -clientHostName $clientHostName -csName $csName -csHost $csHost -instance $instance -username $username -password $password -encryptedPassword $encryptedPassword -commVaultDirectory $commVaultDirectory

Exit 0
    EOH
  	action :run
	not_if <<-EOH
$ErrorActionPreference="Stop"   

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

$commVaultHostName = '#{node['commvault']['server']['hostName']}'
$commVaultClientName = '#{node['commvault']['client']['clientName']}'
$username = '#{node['commvault']['commcelluser']['username']}'
$password = '#{node['commvault']['commcelluser']['password']}'
$encryptedPassword = '#{node['commvault']['commcelluser']['encryptedpassword']}'
$commVaultDirectory = '#{node['commvault']['installDirectory']}'

try{
    Open-CommVaultConnection -commVaultHostName $commVaultHostName -commVaultClientName $commVaultClientName -username $username -password $password -encryptedPassword $encryptedPassword -commVaultDirectory $commVaultDirectory
    return $true
} catch {
    return $false
}
    EOH
end    