#!/usr/bin/env ruby

require 'fileutils'

def cleanup
  puts "\nCLEANING UP"
  base_output_dir = File.expand_path('../actual_output', __FILE__) 
  if File.directory? base_output_dir
    FileUtils.rm_rf base_output_dir
  end
end

def build_plugin
  puts "\nBUILDING PLUGIN"
  pkg_dir = File.expand_path('../../pkg', __FILE__) 
  working_dir = Dir.pwd 
  Dir.chdir pkg_dir
  FileUtils.rm( Dir.glob('*.gem') )
  system('rake build')
  Dir.chdir working_dir
end

def install_plugin
  puts "\nINSTALLING PLUGIN"
  pkg_dir = File.expand_path('../../pkg', __FILE__) 
  working_dir = Dir.pwd 
  Dir.chdir pkg_dir
  system('vagrant plugin install *.gem')
  Dir.chdir working_dir
end

def test(input, outputs)
  failures = []
  test_dir = File.expand_path( File.dirname(__FILE__) ) 

  input_box = File.join(test_dir, 'input', input, 'mutate-test.box') 

  vagrant_dir = File.join(test_dir, 'actual_output', input) 
  FileUtils.mkdir_p vagrant_dir
  ENV['VAGRANT_HOME'] = vagrant_dir
  install_plugin

  outputs.each do |output|
    puts "\nTESTING #{input} to #{output}"
    system("vagrant mutate #{input_box} #{output}")
    output_dir = File.join(vagrant_dir, 'boxes', 'mutate-test', output)
    expected_output_dir = File.join(test_dir, 'expected_output', input, output)
    Dir.foreach(expected_output_dir) do |f|
      next if f == '.' or f == '..'
      output = File.join(output_dir, f)
      expected_output = File.join(expected_output_dir, f)
      test_passed = FileUtils.compare_file(output, expected_output)
      unless test_passed
        failures.push "#{output} does not match #{expected_output}"
      end
    end
  end

  return failures
end

cleanup
build_plugin
failures = test( 'virtualbox', ['kvm', 'libvirt'] )

unless failures.empty?
  puts "\nTESTS FAILED"
  failures.each {|f| puts f}
else
  puts "\nALL TESTS PASSED"
end
