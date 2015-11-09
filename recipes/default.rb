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
is_commvault_installed = is_package_installed?("#{node['commvault']['name']}")
extract_path = "#{Chef::Config['file_cache_path']}/#{node['commvault']['filename']}/#{node['commvault']['checksum']}"
install_path = "#{extract_path}/#{node['commvault']['packagename']}/#{node['commvault']['filename']}/node['commvault']['packagetype']"
install_configuration_path =  "#{install_path}/Install.xml"

windows_zipfile extract_path do
	source node['commvault']['url']
	checksum node['commvault']['checksum']
	action :unzip
	not_if {is_commvault_installed}
end

template install_configuration_path do
  source 'Install.xml.erb'
end

windows_package node['commvault']['name'] do
	checksum node['commvault']['checksum']
	source "#{install_path}/Setup.exe"
	installer_type :custom
	options "/Silent /play \"#{install_configuration_path}/\""
end

download_path = "#{Chef::Config['file_cache_path']}/#{filename}"
remote_file download_path do
  source package_url
  checksum package_checksum
  only_if {is_iso}
end
