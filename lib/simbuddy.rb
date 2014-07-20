#!/usr/bin/env ruby

require 'trollop'
require 'js_base'
require 'backup_set'

req 'project_info','simbuddy'


# The task of making the derived data 'test_resources' folder mirror the one
# in the project directory is unrelated to the task of updating the project's
# test_resources folder, and could be put in a different script.


class SimBuddyApp

  def initialize
    @verbose = nil
    @backup_set = nil
    @project_directory = nil
    @project_name = nil
    @project_info = nil
    @simulator_dir = nil
    @project_resource_path = nil
    @target = nil
    @application_app_directory = nil
    @application_directory = nil
    @application_resource_directory = nil
    @derived_app_resource_subdirectories = nil
    @application_newfiles_directory = nil
    @project_modified = false
  end

  def run(args = ARGV)

    options = Trollop::options(args) do
        opt :project, "specify project (or project directory)", :type => :string
        opt :verbose, "verbose"
        opt :simulator, "specify iPhone simulator directory", :type => :string
    end

    @verbose = options[:verbose]
    @simulator_dir = options[:simulator]

    @project_directory = find_project(options[:project])
    @project_name = FileUtils.remove_extension(File.basename(@project_directory))
    info "Found XCode project: #{@project_name}"

    update_project_resource_files
  end


  private


  def info(msg)
    puts msg if @verbose
  end

  # Find the XCode project directory
  #
  def find_project(start_path)
    start_path ||= Dir.pwd

    if File.extname(start_path) != '.xcodeproj'
      project_path = start_path
      found = false
      while true
        # info "Looking for .xcodeproject within #{project_path}"
        break if !File.directory?(project_path)
        files = Dir.entries(project_path).select{|x| File.extname(x) == '.xcodeproj'}
        if files.size == 0
          parent = File.dirname(project_path)
          break if parent == project_path
          project_path = parent
          next
        end
        die "Multiple XCode projects found within #{project_path}" if files.size > 1
        start_path = File.join(project_path,files[0])
        found = true
        break
      end
      die "Can't find XCode project within #{start_path}" if !found
    end

    die "Can't find XCode project: #{start_path}" if !File.directory?(start_path)
    start_path
  end

  def app_resources_name
    'test_resources'
  end

  def project_resource_path
    if !@project_resource_path
      @project_resource_path = File.join(File.dirname(@project_directory),app_resources_name)
    end
    @project_resource_path
  end

  def project_info
    if !@project_info
      output,success = scall("xcodebuild -project #{@project_directory} -list",true)
      die("Unable to get information about #{@project_directory}") if !success
      @project_info = ProjectInfo.new(output)
    end
    @project_info
  end

  def target
    if !@target
      die "No targets in project" if project_info.targets.empty?
      @target = project_info.targets[0]
    end
    @target
  end

  def application_directory
    application_app_directory
    @application_directory
  end

  def application_app_directory
    if !@application_app_directory
      app_container_dir = File.join(simulator_dir,'Applications')
      die "Can't find application container directory" if !File.directory?(app_container_dir)
      app_dirs = FileUtils.directory_entries(app_container_dir).select{|x| File.directory?(File.join(app_container_dir,x))}.sort
      our_app_dirs = []
      app_dirs.each do |app_dir|
        app_dir = File.join(app_container_dir,app_dir)
        target_dir = File.join(app_dir,target+".app")
        next if !File.directory?(target_dir)
        our_app_dirs << target_dir
      end
      die "Multiple application directories found for target:\n#{our_app_dirs}" if our_app_dirs.size > 1
      die "No application directory found for target" if our_app_dirs.size == 0
      @application_app_directory = our_app_dirs[0]
      @application_directory = File.dirname(@application_app_directory)
      # info "application_app_directory #{@application_app_directory}\n"
    end
    @application_app_directory
  end

  def application_resource_directory
    if !@application_resource_directory
      @application_resource_directory = File.join(application_app_directory,app_resources_name)
       "No test_app_resources subdirectory found at #{@application_resource_directory}" if !File.directory?(@application_resource_directory)
    end
    @application_resource_directory
  end

  def application_newfiles_directory
    if !@application_newfiles_directory
      @application_newfiles_directory = File.join(application_directory,"Documents/_newfiles_")
    end
    @application_newfiles_directory
  end

  def iphone_simulator_directory
    File.join(Dir.home,"Library/Application Support/iPhone Simulator")
  end

  def simulator_dir
    while true
      break if @simulator_dir
      dir = iphone_simulator_directory
      subdirs = FileUtils.directory_entries(dir).select do |x|
        pth = File.join(dir,x)
        File.directory?(pth) && x =~ /^[0-9]/
      end
      subdirs.sort!

      break if subdirs.length == 0
      warning "Multiple simulators found: #{subdirs}; using last: #{subdirs.last}" if subdirs.length > 1
      @simulator_dir = File.join(dir,subdirs.last)
    end
    die "Can't find simulator" if !@simulator_dir
    @simulator_dir
  end

  def update_newfiles_aux(dir)
    entries = FileUtils.directory_entries(dir)
    entries.each do |filename|
      path = File.join(dir,filename)
      if File.directory?(path)
        update_newfiles_aux(path)
      else
        update_newfile(path)
      end
    end
  end

  def backup_set
    if !@backup_set
      @backup_set = BackupSet.new('simbuddy',project_resource_path)
    end
    @backup_set
  end

  def update_newfile(app_path)
    path_rel = app_path[application_newfiles_directory.length+1..-1]
    status = '.'

    project_path = File.join(project_resource_path,path_rel)

    update = false
    file_exists = File.exist?(project_path)

    if !file_exists
      update = true
    else
      project_time = File.mtime(project_path)
      app_time = File.mtime(app_path)
      if project_time < app_time
        update = true
      end
      # warning "doing special test for file that may not actually be newer"
      # if app_path.end_with?("testNoPrefix.txt")
      #    update = true
      # end
    end

    info "#{status} #{path_rel}"
    if update
      if file_exists
        backup_set.backup_file(project_path)
      end

      FileUtils.mkdir_p(File.dirname(project_path))
      status = 'W'
      FileUtils.cp(app_path,project_path)
      @project_modified = true

      derived_dirs = derived_app_resource_subdirectories
      derived_dirs.each do |subdir|
        derived_path = File.join(subdir,path_rel)
        FileUtils.mkdir_p(File.dirname(derived_path))
        FileUtils.cp(app_path,derived_path)
        info "  ==> #{derived_path}"
      end
    end
  end

  def update_project_resource_files
    newfiles_dir = application_newfiles_directory
    return if !File.directory?(newfiles_dir)
    info "Updating new resource files from: #{newfiles_dir}"
    update_newfiles_aux(newfiles_dir)
    # Now that the new files have been processed, delete their directory
    FileUtils.rm_rf(newfiles_dir)
  end

  def derived_data_directory_subdir(dir)
    subdir_list = []
    entries = FileUtils.directory_entries(dir)
    entries.each do |filename|
      if filename.start_with?(@project_name)
        subdir_list << File.join(dir,filename)
      end
    end

    if subdir_list.length != 1
      die "Could not find exactly one derived data project directory:\n#{subdir_list}"
    end
    subdir_list[0]
  end

  # Find all subdirectories containing a directory named 'test_resources'
  def find_app_resources_subdirectories(dir,results)
    entries = FileUtils.directory_entries(dir)
    entries.each do |filename|
      path = File.join(dir,filename)
      if filename == app_resources_name
        results << path
      else
        if File.directory?(path)
          find_app_resources_subdirectories(path,results)
        end
      end
    end
  end

  def derived_app_resource_subdirectories
    if !@derived_app_resource_subdirectories
      dir = File.join(Dir.home,"Library/Developer/Xcode/DerivedData")
      die "Can't locate #{dir}" if !File.exist?(dir)
      subdir = derived_data_directory_subdir(dir)
      products_dir = File.join(subdir,"Build/Products")
      die "Can't locate products directory: #{products_dir}" if !File.exist?(products_dir)

      subdirs = []
      find_app_resources_subdirectories(products_dir,subdirs)
      @derived_app_resource_subdirectories = subdirs
    end
    @derived_app_resource_subdirectories
  end

end

if __FILE__ == $0
  SimBuddyApp.new.run()
end
