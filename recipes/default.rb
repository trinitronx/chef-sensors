#
# Cookbook Name:: sensors
# Recipe:: default
#
# Copyright 2013, Limelight Networks, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# Don't run on EC2 or virtualized systems
if !node['ec2'] && !node['virtualization']['role']

  # try to load the sensor config data bag for this node.  If it doesn't exist we'll do nothing
  begin
    sensor_config = data_bag_item('sensors', node['dmi']['base_board']['product_name'].downcase)
  rescue
    Chef::Log.info("Mainboard #{node['dmi']['base_board']['product_name'].downcase} does not have a data bag.  Not setting up sensor data gathering")
    return
  end

  # Setup lm-sensors or ipmi depending on which is defined in the mainboard databag
  case sensor_config['type']
  when 'lmsensors'

    # install the lm-sensors package
    package node['sensors']['service_name'] do
      action :install
    end

    # make sure lm-sensors is started and enabled to start at boot
    service node['sensors']['service_name'] do
      supports :status => true, :restart => true
      action [:enable, :start]
    end

    # manage module-init-tools so we can restart it if we add modules to the config
    service 'module-init-tools' do
      action :nothing
    end

    # run the sensor module detection (only once) and then restart module-init-tools
    execute 'load_sensor_modules' do
      command "/usr/bin/yes | /usr/sbin/sensors-detect && touch #{Chef::Config[:file_cache_path]}/sensors_detect_ran"
      creates "#{Chef::Config[:file_cache_path]}/sensors_detect_ran"
      notifies :restart, 'service[module-init-tools]'
      action :run
    end

    template "/etc/sensors.d/#{node['dmi']['base_board']['product_name'].downcase}" do
      source 'lmsensors_config.erb'
      mode 00644
      notifies :restart, 'service[lm-sensors]'
      notifies :restart, 'service[collectd]' if node['recipes'].include?('collectd::default') || node['recipes'].include?('collectd')
      variables(
        :sensor_config => sensor_config
      )
    end

    if node['recipes'].include?('collectd::default') || node['recipes'].include?('collectd')
      collectd_plugin 'sensors'
    end

  when 'ipmi'

    package 'libopenipmi0' do
      action :install
    end

    # if using collectd template out the ipmi plugin config.  The LWRP isn't advanced enough to do this at the moment.
    if node['recipes'].include?('collectd::default') || node['recipes'].include?('collectd')
      template '/etc/collectd/plugins/ipmi.conf' do
        source 'ipmi_config.erb'
        mode 00644
        notifies :restart, 'service[collectd]'
        variables(
          :sensor_config => sensor_config
        )
      end
    end

  else # if type isn't lmsensors or ipmi it's an invalid type and we should log an error
    Chef::Log.error("The databag for mainboard #{node['dmi']['base_board']['product_name'].downcase} lists the invalid type #{sensor_config['type']}")
  end

end
