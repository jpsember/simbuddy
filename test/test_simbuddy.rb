#!/usr/bin/env ruby

require 'js_base/test'
require 'simbuddy'

class TestSimBuddy < Test::Unit::TestCase

  def setup
    enter_test_directory
    test_dir = File.dirname(Dir.pwd)

    TestUtils.generate_files(nil,{
      'simulator_directory' => {
        'Applications' => {
          'AAA' => {},
          'CCC' => {},
          'BBB' => {
            'sample_xcode_project.app' => {},
            'tmp' => {},
            'Documents' => {},
            'Library' => {}
          }
        }
      }
    }
    )

    @project_dir = File.join(test_dir,'sample_xcode_project')
    @res_dir = File.join(@project_dir,'app_resources')
    clean_directory(@res_dir)

    time = Time.now - 500

    TestUtils.generate_files(@res_dir,{
      'a.txt' => 'a_old',
      'b.txt' => 'b_old',
      },time)
    TestUtils.generate_files(@res_dir,{
      'e.txt' => 'e_original',
      },time + 200)

    @sim_dir = File.join(Dir.pwd,'simulator_directory')
    doc_dir = File.join(@sim_dir,'Applications/BBB/Documents')

    TestUtils.generate_files(doc_dir,{'_newfiles_' => {
      'a.txt' => 'a_new',
      'e.txt' => 'e_app',
      'c' => {
        'd.txt' => 'd',
      }
      }},time + 100)
  end

  def teardown
    clean_directory(@res_dir)
    leave_test_directory
  end

  def clean_directory(dir)
    FileUtils.directory_entries(dir).each do |x|
      FileUtils.rm_rf(File.join(dir,x))
    end
  end

  def test_update
    IORecorder.new.perform do
      SimBuddyApp.new.run ['-v','-s',@sim_dir,'-p',@project_dir]
    end
    assert_equal(FileUtils.read_text_file(File.join(@res_dir,'a.txt')),'a_new')
    assert_equal(FileUtils.read_text_file(File.join(@res_dir,'c/d.txt')),'d')
    assert_equal(FileUtils.read_text_file(File.join(@res_dir,'e.txt')),'e_original')
  end

  def test_update_from_subdir
    IORecorder.new.perform do
      Dir.chdir(File.join(@project_dir,'sample_xcode_project.xcodeproj/xcuserdata'))
      SimBuddyApp.new.run ['-v','-s',@sim_dir]
    end
    assert_equal(FileUtils.read_text_file(File.join(@res_dir,'a.txt')),'a_new')
    assert_equal(FileUtils.read_text_file(File.join(@res_dir,'c/d.txt')),'d')
    assert_equal(FileUtils.read_text_file(File.join(@res_dir,'e.txt')),'e_original')
  end

  def test_no_project_found
    Dir.chdir(Dir.home)
    output,success = scall("simbuddy -v -s \"#{@sim_dir}\"",false)
    assert(!success)
    assert(output.start_with? "Can't find XCode project")
  end

end
