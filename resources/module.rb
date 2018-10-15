# A resource for managing SE modules

property :module_name, String, name_property: true
property :force, [true, false], default: false
property :directory, String, default: lazy { "#{Chef::Config[:file_cache_path]}/#{module_name}" } # content to work with. Defaults to autogenerated name in the Chef cache. Can be provided and pre-populated
# Content options:
property :content, String # provide a 'te' file directly. Optional
property :directory_source, String # Source directory for module source code. If specified, will use "remote_directory" on the directory specified as `directory`
property :cookbook, String # Related to directory
property :allow_disabled, [true, false], default: true

# deploy should do all three, as it used to do
action :deploy do
  run_action(:fetch)
  run_action(:compile)
  run_action(:install)
end

# Get all the components in the right place
action :fetch do
  directory new_resource.directory do
    only_if { use_selinux }
  end

  raise 'dont specify both directory_source and content' if new_resource.directory_source && new_resource.content

  if new_resource.directory_source # ~FC023
    remote_directory new_resource.directory do
      source new_resource.directory_source
      cookbook new_resource.cookbook
      only_if { use_selinux }
    end
  end

  if new_resource.content
    file "#{new_resource.directory}/#{new_resource.module_name}.te" do
      content new_resource.content
      only_if { use_selinux }
    end
  end
end

action :compile do
  make_command = "/usr/bin/make -f /usr/share/selinux/devel/Makefile #{new_resource.module_name}.pp"
  execute "semodule-compile-#{new_resource.module_name}" do
    command make_command
    not_if "#{make_command} -q", cwd: new_resource.directory # $? = 1 means make wants to execute http://www.gnu.org/software/make/manual/html_node/Running.html
    only_if { use_selinux }
    cwd new_resource.directory
  end
end

# deploy / upgrade module
# XXX this looks ugly because CentOS 6.X doesn't support extracting
# SELinux modules from the current policy, which I planned on comparing
# to my compiled file. I'll be happy to see anything else (that works).
action :install do
  filename = "#{new_resource.directory}/#{new_resource.module_name}.pp"
  execute "semodule-install-#{new_resource.module_name}" do
    command "semodule -i #{filename}"
    only_if "#{shell_boolean(new_resource.updated_by_last_action? || new_resource.force)} || ! (#{module_defined(new_resource.module_name)}) "
    only_if { use_selinux }
  end
end

action :remove do
  execute "semodule-remove-#{new_resource.module_name}" do
    command "semodule -r #{new_resource.module_name}"
    only_if module_defined(new_resource.module_name)
    only_if { use_selinux }
  end
end

action_class do
  include Chef::SELinuxPolicy::Helpers
end
