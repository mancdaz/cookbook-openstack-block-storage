# encoding: UTF-8
#
# Cookbook Name:: openstack-block-storage

require_relative 'spec_helper'

describe 'openstack-block-storage::api' do
  describe 'ubuntu' do
    let(:runner) { ChefSpec::Runner.new(UBUNTU_OPTS) }
    let(:node) { runner.node }
    let(:chef_run) { runner.converge(described_recipe) }

    include_context 'block-storage-stubs'
    include_examples 'common-logging'

    expect_creates_cinder_conf 'service[cinder-api]', 'cinder', 'cinder'

    it 'installs cinder api packages' do
      expect(chef_run).to upgrade_package('cinder-api')
      expect(chef_run).to upgrade_package('python-cinderclient')
    end

    it 'starts cinder api on boot' do
      expect(chef_run).to enable_service('cinder-api')
    end

    it 'installs mysql python packages by default' do
      expect(chef_run).to upgrade_package('python-mysqldb')
    end

    it 'installs postgresql python packages if explicitly told' do
      node.set['openstack']['db']['block-storage']['service_type'] = 'postgresql'

      expect(chef_run).to upgrade_package('python-psycopg2')
      expect(chef_run).not_to upgrade_package('python-mysqldb')
    end

    describe '/var/cache/cinder' do
      let(:dir) { chef_run.directory('/var/cache/cinder') }

      it 'has proper owner' do
        expect(dir.owner).to eq('cinder')
        expect(dir.group).to eq('cinder')
      end

      it 'has proper modes' do
        expect(sprintf('%o', dir.mode)).to eq('700')
      end
    end

    describe 'cinder.conf' do
      let(:file) { chef_run.template('/etc/cinder/cinder.conf') }

      it 'runs logging recipe if node attributes say to' do
        node.set['openstack']['block-storage']['syslog']['use'] = true

        expect(chef_run).to render_file(file.name).with_content('log_config = /etc/openstack/logging.conf')
      end

      context 'rdb driver' do
        before do
          node.set['openstack']['block-storage']['volume'] = {
            'driver' => 'cinder.volume.drivers.rbd.RBDDriver'
          }
        end

        # FIXME(galstrom21): this block needs to check all of the default
        #   rdb_* configuration options
        it 'has default rbd_* options set' do
          expect(chef_run).to render_file(file.name).with_content(/^rbd_/)
          expect(chef_run).not_to render_file(file.name).with_content(/^netapp_/)
        end
      end

      context 'netapp driver' do
        before do
          node.set['openstack']['block-storage']['volume'] = {
            'driver' => 'cinder.volume.drivers.netapp.NetAppISCSIDriver'
          }
        end

        # FIXME(galstrom21): this block needs to check all of the default
        #   netapp_* configuration options
        it 'has default netapp_* options set' do
          expect(chef_run).to render_file(file.name).with_content(/^netapp_/)
          expect(chef_run).not_to render_file(file.name).with_content(/^rbd_/)
        end
      end
    end

    it 'runs db migrations' do
      expect(chef_run).to run_execute('cinder-manage db sync')
    end

    describe 'api-paste.ini' do
      let(:file) { chef_run.template('/etc/cinder/api-paste.ini') }

      it 'has proper owner' do
        expect(file.owner).to eq('cinder')
        expect(file.group).to eq('cinder')
      end

      it 'has proper modes' do
        expect(sprintf('%o', file.mode)).to eq('644')
      end

      it 'notifies cinder-api restart' do
        expect(file).to notify('service[cinder-api]').to(:restart)
      end

      context 'template contents' do
        it 'has signing_dir' do
          node.set['openstack']['block-storage']['api']['auth']['cache_dir'] = 'auth_cache_dir'

          expect(chef_run).to render_file(file.name).with_content(/^signing_dir = auth_cache_dir$/)
        end

        context 'endpoint related' do
          before do
            endpoint = double(port: 'port', host: 'host', scheme: 'scheme')
            Chef::Recipe.any_instance.stub(:endpoint)
              .with('image-api')
              .and_return(endpoint)
            Chef::Recipe.any_instance.stub(:endpoint)
              .with('identity-admin')
              .and_return(endpoint)
            Chef::Recipe.any_instance.stub(:endpoint)
              .with('identity-api')
              .and_return(endpoint)
            Chef::Recipe.any_instance.stub(:endpoint)
              .with('block-storage-api')
              .and_return(endpoint)
            Chef::Recipe.any_instance.stub(:auth_uri_transform)
              .and_return('auth_uri_transform')
          end

          it 'has auth_uri' do
            expect(chef_run).to render_file(file.name).with_content(/^auth_uri = auth_uri_transform$/)
          end

          it 'has auth_host' do
            expect(chef_run).to render_file(file.name).with_content(/^auth_host = host$/)
          end

          it 'has auth_port' do
            expect(chef_run).to render_file(file.name).with_content(/^auth_port = port$/)
          end

          it 'has auth_protocol' do
            expect(chef_run).to render_file(file.name).with_content(/^auth_protocol = scheme$/)
          end
        end

        it 'has no auth_version when auth_version is v2.0' do
          node.set['openstack']['block-storage']['api']['auth']['version'] = 'v2.0'

          expect(chef_run).not_to render_file(file.name).with_content(/^auth_version = v2.0$/)
        end

        it 'has auth_version when auth version is not v2.0' do
          node.set['openstack']['block-storage']['api']['auth']['version'] = 'v3.0'

          expect(chef_run).to render_file(file.name).with_content(/^auth_version = v3.0$/)
        end

        it 'has an admin tenant name' do
          node.set['openstack']['block-storage']['service_tenant_name'] = 'tenant_name'

          expect(chef_run).to render_file(file.name).with_content(/^admin_tenant_name = tenant_name$/)
        end

        it 'has an admin user' do
          node.set['openstack']['block-storage']['service_user'] = 'username'

          expect(chef_run).to render_file(file.name).with_content(/^admin_user = username$/)
        end

        it 'has an admin password' do
          # (fgimenez) the get_password mocking is set in spec/spec_helper.rb
          expect(chef_run).to render_file(file.name).with_content(/^admin_password = cinder-pass$/)
        end
      end
    end
  end
end
