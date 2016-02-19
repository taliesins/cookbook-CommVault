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
$cmd = join-path '#{node['commvault']['installDirectory']}' 'base\\SIMCallWrapper.exe'
$clientName = '#{node['commvault']['client']['clientName']}'
$clientHostName = '#{node['commvault']['client']['hostName']}'
$csName = '#{node['commvault']['server']['clientName']}'
$csHost = '#{node['commvault']['server']['hostName']}'
$instance = '#{node['commvault']['instanceName']}'
$username = '#{node['commvault']['commcelluser']['username']}'
$password = '#{node['commvault']['commcelluser']['password']}'
$encryptedPassword = '#{node['commvault']['commcelluser']['encryptedpassword']}'

$cmdArgs = @("-OpType", "1000", "-clientName", "$clientName", "-clientHostName", "$clientHostName", "-CSName", "$csName", "-CSHost", "$csHost", "-instance", "$instance", "-output", "register.xml")
if ($username){
	$cmdArgs += "-user", "$username"
}
if ($password){
	$cmdArgs += "-password", "$password"
}
if ($encryptedPassword){
	$cmdArgs += "-passwordEncrypted", "$encryptedPassword"
}

&$cmd $cmdArgs
    EOH
  	action :run
	
end    