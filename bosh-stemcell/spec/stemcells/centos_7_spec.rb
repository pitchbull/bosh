require 'spec_helper'

describe 'CentOS 7 stemcell', stemcell_image: true do
  it_behaves_like 'All Stemcells'
  it_behaves_like 'a CentOS 7 or RHEL 7 stemcell'

  context 'installed by system_parameters' do
    describe file('/var/vcap/bosh/etc/operating_system') do
      it { should contain('centos') }
    end
  end

  context 'installed by image_vsphere_cdrom stage', {
    exclude_on_aws: true,
    exclude_on_vcloud: true,
    exclude_on_warden: true,
    exclude_on_openstack: true,
    exclude_on_cloudstack: true,
    exclude_on_azure: true,
  } do
    describe file('/etc/udev/rules.d/60-cdrom_id.rules') do
      it { should be_file }
      its(:content) { should eql(<<HERE) }
# Generated by BOSH stemcell builder

ACTION=="remove", GOTO="cdrom_end"
SUBSYSTEM!="block", GOTO="cdrom_end"
KERNEL!="sr[0-9]*|xvd*", GOTO="cdrom_end"
ENV{DEVTYPE}!="disk", GOTO="cdrom_end"

# unconditionally tag device as CDROM
KERNEL=="sr[0-9]*", ENV{ID_CDROM}="1"

# media eject button pressed
ENV{DISK_EJECT_REQUEST}=="?*", RUN+="cdrom_id --eject-media $devnode", GOTO="cdrom_end"

# Do not lock CDROM drive when cdrom is inserted
# because vSphere will start asking questions via API.
# IMPORT{program}="cdrom_id --lock-media $devnode"
IMPORT{program}="cdrom_id $devnode"

KERNEL=="sr0", SYMLINK+="cdrom", OPTIONS+="link_priority=-100"

LABEL="cdrom_end"
HERE
    end
  end

  context 'installed by bosh_cloudstack_agent_settings', {
    exclude_on_aws: true,
    exclude_on_vcloud: true,
    exclude_on_vsphere: true,
    exclude_on_warden: true,
    exclude_on_azure: true,
    exclude_on_openstack: true
  } do
    describe file('/var/vcap/bosh/agent.json') do
      it { should be_valid_json_file }
      it { should contain('"CreatePartitionIfNoEphemeralDisk": true') }
      it { should contain('"Type": "HTTP"') }
    end
  end


  context 'installed by bosh_openstack_agent_settings', {
    exclude_on_aws: true,
    exclude_on_vcloud: true,
    exclude_on_vsphere: true,
    exclude_on_warden: true,
    exclude_on_azure: true,
    exclude_on_cloudstack: true
  } do
    describe file('/var/vcap/bosh/agent.json') do
      it { should be_valid_json_file }
      it { should contain('"CreatePartitionIfNoEphemeralDisk": true') }
      it { should contain('"Type": "ConfigDrive"') }
      it { should contain('"Type": "HTTP"') }
    end
  end

end

describe 'CentOS 7 stemcell tarball', stemcell_tarball: true do
  context 'installed by bosh_rpm_list stage' do
    describe file("#{ENV['STEMCELL_WORKDIR']}/stemcell/stemcell_rpm_qa.txt") do
      it { should be_file }
    end
  end
end
