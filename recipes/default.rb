id = 'volgactf-2018-final-cloud'
instance = ::ChefCookbook::Instance::Helper.new(node)

# %w(
#   python-dev
#   python-gmpy2
#   libgmp-dev
#   libmpfr-dev
#   libmpc-dev
# ).each do |package_name|
#   package package_name do
#     action :install
#   end
# end

secret = ::ChefCookbook::Secret::Helper.new(node)

postgres_root_username = 'postgres'

postgresql_connection_info = {
  host: node['latest-postgres']['listen']['address'],
  port: node['latest-postgres']['listen']['port'],
  username: postgres_root_username,
  password: secret.get("postgres:password:#{postgres_root_username}")
}

postgresql_database node[id]['db']['name'] do
  connection postgresql_connection_info
  action :create
end

postgresql_database_user node[id]['db']['user'] do
  connection postgresql_connection_info
  database_name node[id]['db']['name']
  password secret.get("postgres:password:#{node[id]['db']['user']}")
  privileges [:all]
  action [:create, :grant]
end

namespace = 'volgactf.final'

directory node[id]['basedir'] do
  owner instance.user
  group instance.group
  mode 0755
  recursive true
  action :create
end

ssh_private_key instance.user
ssh_known_hosts_entry 'git.volgactf.org'
url_repository = "gitea@git.volgactf.org:#{node[id]['git_repository']}.git"

git2 node[id]['basedir'] do
  url url_repository
  branch node[id]['revision']
  user instance.user
  group instance.group
  action :create
end

if node.chef_environment.start_with?('development')
  git_data_bag_item = nil
  begin
    git_data_bag_item = data_bag_item('git', node.chef_environment)
  rescue
    ::Chef::Log.warn('Check whether git data bag exists!')
  end

  git_options = \
    if git_data_bag_item.nil?
      {}
    else
      git_data_bag_item.to_hash.fetch('config', {})
    end

  git_options.each do |key, value|
    git_config "git-config #{key} at #{node[id]['basedir']}" do
      key key
      value value
      scope 'local'
      path node[id]['basedir']
      user instance.user
      action :set
    end
  end
end

cloud_virtualenv_path = ::File.join(node[id]['basedir'], '.venv')

python_virtualenv cloud_virtualenv_path do
  user instance.user
  group instance.group
  python '2'
  action :create
end

pip_options = {}

pip_requirements ::File.join(node[id]['basedir'], 'requirements.txt') do
  user instance.user
  group instance.group
  virtualenv cloud_virtualenv_path
  options pip_options.map { |k, v| "--#{k}=#{v}" }.join(' ')
  action :install
end

supervisor_service "#{namespace}.cloud" do
  command 'sh script/server'
  process_name 'server-%(process_num)s'
  numprocs node[id]['processes']
  numprocs_start 0
  priority 300
  autostart node[id]['autostart']
  autorestart true
  startsecs 1
  startretries 3
  exitcodes [0, 2]
  stopsignal :INT
  stopwaitsecs 10
  stopasgroup true
  killasgroup true
  user instance.user
  redirect_stderr false
  stdout_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.cloud-%(process_num)s-stdout.log")
  stdout_logfile_maxbytes '10MB'
  stdout_logfile_backups 10
  stdout_capture_maxbytes '0'
  stdout_events_enabled false
  stderr_logfile ::File.join(node['supervisor']['log_dir'], "#{namespace}.cloud-%(process_num)s-stderr.log")
  stderr_logfile_maxbytes '10MB'
  stderr_logfile_backups 10
  stderr_capture_maxbytes '0'
  stderr_events_enabled false
  directory node[id]['basedir']
  environment(
    'DB_HOST' => node['latest-postgres']['listen']['address'],
    'DB_PORT' => node['latest-postgres']['listen']['port'],
    'DB_NAME' => node[id]['db']['name'],
    'DB_USER' => node[id]['db']['user'],
    'DB_PASS' => secret.get("postgres:password:#{node[id]['db']['user']}")
  )
  serverurl 'AUTO'
  action :enable
end

cloud_script_dir = ::File.join(node[id]['basedir'], 'script')

template ::File.join(cloud_script_dir, 'tail-cloud-stdout') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.cloud-#{ndx}-stdout.log")
    end
  )
  action :create
end

template ::File.join(cloud_script_dir, 'tail-cloud-stderr') do
  source 'tail.sh.erb'
  owner instance.user
  group instance.group
  mode 0755
  variables(
    files: ::Range.new(0, node[id]['processes'], true).map do |ndx|
      ::File.join(node['supervisor']['log_dir'], "#{namespace}.cloud-#{ndx}-stderr.log")
    end
  )
  action :create
end

supervisor_group namespace do
  programs [
    "#{namespace}.cloud"
  ]
  action :enable
end
