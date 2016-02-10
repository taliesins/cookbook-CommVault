#
# Author:: Taliesin Sisson (<taliesins@yahoo.com>)
# Cookbook Name:: commvault
# Attributes:: default
# Copyright 2014-2015, Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

default['commvault']['instanceName'] = 'Instance001'
default['commvault']['installDirectory'] = "C:\\Program Files\\CommVault\\Simpana\\"
default['commvault']['server']['clientName'] = 'commvault'
default['commvault']['server']['hostName'] = 'commvault.yourserver.com'
default['commvault']['client']['clientName'] = node['hostname']
default['commvault']['client']['hostName'] = node['fqdn']

default['commvault']['installFlags']['addToFirewallExclusion'] = '1'
default['commvault']['installFlags']['autoRegister'] = '0'
default['commvault']['installFlags']['decoupledInstall'] = '1'
default['commvault']['installFlags']['deletePackagesAfterInstall'] = '0'
default['commvault']['installFlags']['disableOSFirewall'] = '0'
default['commvault']['installFlags']['forceReboot'] = '0'
default['commvault']['installFlags']['ignoreJobsRunning'] = '0'
default['commvault']['installFlags']['install32Base'] = '0'
default['commvault']['installFlags']['install64Base'] = '0'
default['commvault']['installFlags']['installLatestServicePack'] = '1'
default['commvault']['installFlags']['killBrowserProcesses'] = '0'
default['commvault']['installFlags']['launchRegisterMe'] = '1'
default['commvault']['installFlags']['overrideClientInfo'] = '0'
default['commvault']['installFlags']['preferredIPFamily'] = '1'
default['commvault']['installFlags']['restoreOnlyAgents'] = '0'
default['commvault']['installFlags']['showFirewallConfigDialogs'] = '1'
default['commvault']['installFlags']['stopOracleServices'] = '0'
default['commvault']['installFlags']['unixGroupAccess'] = '7'
default['commvault']['installFlags']['unixOtherAccess'] = '7'
default['commvault']['installFlags']['upgradeMode'] = '0'
default['commvault']['installFlags']['useNewOS'] = '0'

default['commvault']['firewallInstall']['bindToInterface'] = ''
default['commvault']['firewallInstall']['enableFirewallConfig'] = '1'
default['commvault']['firewallInstall']['firewallConnectionType'] = '0'
default['commvault']['firewallInstall']['httpProxyPortNumber'] = '0'
default['commvault']['firewallInstall']['portNumber'] = '8403'

default['commvault']['commcelluser']['password'] = ''
default['commvault']['commcelluser']['username'] = ''

default['commvault']['name'] = 'CommVault File System Core (' + default['commvault']['instanceName'] + ')'
default['commvault']['packagename'] = 'CommVault-Client'
default['commvault']['packagetype'] = 'WinX64'
default['commvault']['filename'] = default['commvault']['packagename'] + '_' + default['commvault']['packagetype']
default['commvault']['filenameextension'] = 'exe'
default['commvault']['url'] = 'http://www.yourserver.com/' + default['commvault']['filename'] + '.' + default['commvault']['filenameextension'] 
default['commvault']['checksum'] = '3a0ec7a62f82087a474878e7008f80c8f09eca52a6c5654c52577f62d67d85c5'