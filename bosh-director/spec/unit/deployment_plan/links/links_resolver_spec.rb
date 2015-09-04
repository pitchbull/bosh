require 'spec_helper'

describe Bosh::Director::DeploymentPlan::LinksResolver do
  subject(:links_resolver) { described_class.new(deployment_plan, logger) }

  let(:deployment_plan) do
    planner_factory = Bosh::Director::DeploymentPlan::PlannerFactory.create(event_log, logger)
    planner = planner_factory.create_from_manifest(deployment_manifest, nil, {})
    planner.bind_models
    planner
  end

  let(:deployment_manifest) do
    generate_deployment_manifest('fake-deployment', links, ['127.0.0.3', '127.0.0.4'])
  end

  def generate_deployment_manifest(name, links, mysql_static_ips)
    {
      'name' => name,
      'jobs' => [
        {
          'name' => 'api-server',
          'templates' => [
            {'name' => 'api-server-template', 'release' => 'fake-release', 'links' => links}
          ],
          'resource_pool' => 'fake-resource-pool',
          'instances' => 1,
          'networks' => [
            {
              'name' => 'fake-manual-network',
              'static_ips' => ['127.0.0.2']
            }
          ],
        },
        {
          'name' => 'mysql',
          'templates' => [
            {'name' => 'mysql-template', 'release' => 'fake-release'}
          ],
          'resource_pool' => 'fake-resource-pool',
          'instances' => 2,
          'networks' => [
            {
              'name' => 'fake-manual-network',
              'static_ips' => mysql_static_ips,
              'default' => ['dns', 'gateway']
            },
            {
              'name' => 'fake-dynamic-network',
            }
          ],
        }
      ],
      'resource_pools' => [
        {
          'name' => 'fake-resource-pool',
          'stemcell' => {
            'name' => 'fake-stemcell',
            'version' => 'fake-stemcell-version',
          },
          'network' => 'fake-manual-network',
        }
      ],
      'networks' => [
        {
          'name' => 'fake-manual-network',
          'type' => 'manual',
          'subnets' => [
            {
              'name' => 'fake-subnet',
              'range' => '127.0.0.0/20',
              'gateway' => '127.0.0.1',
              'static' => ['127.0.0.2'].concat(mysql_static_ips),
            }
          ]
        },
        {
          'name' => 'fake-dynamic-network',
          'type' => 'dynamic',
        }
      ],
      'releases' => [
        {
          'name' => 'fake-release',
          'version' => '1.0.0',
        }
      ],
      'compilation' => {
        'workers' => 1,
        'network' => 'fake-manual-network',
      },
      'update' => {
        'canaries' => 1,
        'max_in_flight' => 1,
        'canary_watch_time' => 1,
        'update_watch_time' => 1,
      },
    }
  end

  let(:event_log) { Bosh::Director::Config.event_log }
  let(:logger) { Logging::Logger.new('TestLogger') }

  let(:api_server_job) do
    deployment_plan.job('api-server')
  end

  before do
    fake_locks

    Bosh::Director::Models::Stemcell.make(name: 'fake-stemcell', version: 'fake-stemcell-version')

    allow(Bosh::Director::Config).to receive(:cloud).and_return(nil)
    allow(Bosh::Director::Config).to receive(:dns_domain_name).and_return('fake-dns')
    Bosh::Director::Config.dns = {'address' => 'fake-dns-address'}

    release_model = Bosh::Director::Models::Release.make(name: 'fake-release')
    version = Bosh::Director::Models::ReleaseVersion.make(version: '1.0.0')
    release_model.add_version(version)

    template_model = Bosh::Director::Models::Template.make(name: 'api-server-template', requires: requires_links)
    version.add_template(template_model)

    template_model = Bosh::Director::Models::Template.make(name: 'mysql-template', provides: provided_links)
    version.add_template(template_model)
  end

  let(:requires_links) { ['db'] }
  let(:provided_links) { ['db'] }

  describe '#resolve' do
    context 'when job requires link from the same deployment' do
      context 'when link source is provided by some job' do
        let(:links) { {'db' => 'fake-deployment.mysql.mysql-template.db'} }

        it 'adds link to job' do
          links_resolver.resolve(api_server_job)
          # require 'pry'; binding.pry
          instance1 = Bosh::Director::Models::Instance.where(job: 'mysql', index: 0).first
          instance2 = Bosh::Director::Models::Instance.where(job: 'mysql', index: 1).first
          expect(api_server_job.link_spec).to eq({
                'db' => {
                  'nodes' => [
                    {
                      'name' => 'mysql',
                      'index' => 0,
                      'id' => instance1.uuid,
                      'networks' => {
                        'fake-manual-network' => {
                          'address' => '127.0.0.3',
                        },
                        'fake-dynamic-network' => {
                          'address' => '0.mysql.fake-dynamic-network.fake-deployment.fake-dns',
                        }
                      }
                    },
                    {
                      'name' => 'mysql',
                      'index' => 1,
                      'id' => instance2.uuid,
                      'networks' => {
                        'fake-manual-network' => {
                          'address' => '127.0.0.4',
                        },
                        'fake-dynamic-network' => {
                          'address' => '1.mysql.fake-dynamic-network.fake-deployment.fake-dns',
                        }
                      }
                    }
                  ]
                }
              })
        end
      end
    end

    context 'when job requires link from another deployment' do
      let(:links) { {'db' => 'other-deployment.mysql.mysql-template.db'} }

      context 'when another deployment has link source' do
        before do
          other_deployment_manifest = generate_deployment_manifest('other-deployment', links, ['127.0.0.4', '127.0.0.5'])

          planner_factory = Bosh::Director::DeploymentPlan::PlannerFactory.create(event_log, logger)
          deployment_plan = planner_factory.create_from_manifest(other_deployment_manifest, nil, {})
          deployment_plan.bind_models

          links_resolver = described_class.new(deployment_plan, logger)
          mysql_job = deployment_plan.job('mysql')
          links_resolver.resolve(mysql_job)

          deployment_plan.persist_updates!
        end

        it 'returns link from another deployment' do
          links_resolver.resolve(api_server_job)
          instance1 = Bosh::Director::Models::Instance.where(job: 'mysql', index: 0).first
          instance2 = Bosh::Director::Models::Instance.where(job: 'mysql', index: 1).first

          expect(api_server_job.link_spec).to eq({
            'db' => {
              'nodes' => [
                {
                  'name' => 'mysql',
                  'index' => 0,
                  'id' => instance1.uuid,
                  'networks' => {
                    'fake-manual-network' => {
                      'address' => '127.0.0.4',
                    },
                    'fake-dynamic-network' => {
                      'address' => '0.mysql.fake-dynamic-network.other-deployment.fake-dns',
                    }
                  }
                },
                {
                  'name' => 'mysql',
                  'index' => 1,
                  'id' => instance2.uuid,
                  'networks' => {
                    'fake-manual-network' => {
                      'address' => '127.0.0.5',
                    },
                    'fake-dynamic-network' => {
                      'address' => '1.mysql.fake-dynamic-network.other-deployment.fake-dns',
                    }
                  }
                }
              ]
            }
          })
        end
      end

      context 'when another deployment does not have link source' do
        let(:links) { {'db' => 'non-existent.mysql.mysql-template.db'} }

        it 'fails' do
          expect {
            links_resolver.resolve(api_server_job)
          }.to raise_error Bosh::Director::DeploymentInvalidLink,
              "Link 'name: db, type: db' references unknown deployment 'non-existent'"
        end
      end
    end

    context 'when provided link type does not match required link type' do
      let(:links) { {'db' => 'fake-deployment.mysql.mysql-template.db'} }

      let(:requires_links) { [{'name' => 'db', 'type' => 'other'}] }
      let(:provided_links) { ['db'] } # name and type is implicitly db

      it 'fails to find link' do
        expect {
          links_resolver.resolve(api_server_job)
        }.to raise_error Bosh::Director::DeploymentInvalidLink,
            "Link 'db' can not be found by path 'fake-deployment.mysql.mysql-template.db'"
      end
    end

    context 'when provided link name matches links name' do
      let (:links) { {'backup_db' => 'fake-deployment.mysql.mysql-template.db'} }

      let(:requires_links) { [{'name' => 'backup_db', 'type' => 'db'}]}
      let(:provided_links) { ['db'] }

      it 'adds link to job' do
        links_resolver.resolve(api_server_job)
        instance1 = Bosh::Director::Models::Instance.where(job: 'mysql', index: 0).first
        instance2 = Bosh::Director::Models::Instance.where(job: 'mysql', index: 1).first

        expect(api_server_job.link_spec).to eq({
            'backup_db' => {
            'nodes' => [
              {
                'name' => 'mysql',
                'index' => 0,
                'id' => instance1.uuid,
                'networks' => {
                  'fake-manual-network' => {
                      'address' => '127.0.0.3'
                  },
                  'fake-dynamic-network' => {
                      'address' => '0.mysql.fake-dynamic-network.fake-deployment.fake-dns'
                    }
                }
              },
              {
                'name' => 'mysql',
                'index' => 1,
                'id' => instance2.uuid,
                'networks' => {
                  'fake-manual-network' => {
                    'address' => '127.0.0.4'
                  },
                  'fake-dynamic-network' => {
                    'address' => '1.mysql.fake-dynamic-network.fake-deployment.fake-dns'
                  }
                }
              }
            ]
          }
        })
      end
    end

    context 'when link source is does not specify deployment name' do
      let(:links) { {'db' => 'mysql.mysql-template.db'} }

      it 'defaults to current deployment' do
        links_resolver.resolve(api_server_job)
        expect(api_server_job.link_spec['db']['nodes'].first['name']).to eq('mysql')
      end
    end

    context 'when links source is not provided' do
      let(:links) { {'db' => 'fake-deployment.mysql.non-existent.db'} }

      it 'fails' do
        expect {
          links_resolver.resolve(api_server_job)
        }.to raise_error Bosh::Director::DeploymentInvalidLink,
            "Link 'db' can not be found by path 'fake-deployment.mysql.non-existent.db'"
      end
    end

    context 'when link format is invalid' do
      let(:links) { {'db' => 'mysql.mysql-template'} }

      it 'fails' do
        expect {
          links_resolver.resolve(api_server_job)
        }.to raise_error Bosh::Director::DeploymentInvalidLink, "Link 'mysql.mysql-template' is in invalid format"
      end
    end

    context 'when required link is not specified in manifest' do
      let(:links) { {'other' => 'a.b.c'} }

      it 'fails' do
        expect {
          links_resolver.resolve(api_server_job)
        }.to raise_error(
            Bosh::Director::JobMissingLink,
            "Link path was not provided for required link 'db' in job 'api-server'"
          )
      end
    end

    context 'when link specified in manifest is not required' do

      let(:links) { {'db' => 'fake-deployment.mysql.mysql-template.db'} }
      let(:links) { {'db' => 'fake-deployment.mysql.mysql-template.db'} }

      let(:requires_links) { [] }
      let(:provided_links) { ['db'] } # name and type is implicitly db

      it 'raises unknown link error' do
        expect {
          links_resolver.resolve(api_server_job)
        }.to raise_error Bosh::Director::UnusedProvidedLink,
            "Link 'db' is not required in job 'api-server'"
      end
    end
  end
end
