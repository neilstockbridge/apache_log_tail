
require "test/unit"
require "apache_log_tail"
require "yaml"


class ApacheLogTailTest < Test::Unit::TestCase

  def test_apache_log

    # Remove the state file from previous runs of this test:
    File.unlink "/tmp/my-state.yml"

    # Write a couple of lines to a test file:
    log_file = "/tmp/test_apache_log_tail.log"
    File.open  log_file, "w" do |file|
      file.puts "line1"
      file.puts "line2"
    end

    # Check that those lines are processed:
    process = lambda do
      tail = ApacheLogTail.new  log_file
      tail.state_store.path_to_file = "/tmp/my-state.yml" # Optional: there is a default path
      @lines = []
      tail.each_new_line {|line| @lines << line }
    end
    process[]
    assert_equal ["line1\n", "line2\n"], @lines

    # Check that the custom state file is as expected:
    assert_equal( {:cursor => 12, :first_line => "line1\n"}, YAML.load( File.read "/tmp/my-state.yml") )

    # Write a couple more lines:
    File.open  log_file, "a" do |file|
      file.puts "line3"
      file.puts "line4"
    end

    # Check that the extra lines are processed:
    process[]
    assert_equal ["line3\n", "line4\n"], @lines

    # Check that the custom state file is as expected:
    assert_equal( {:cursor => 24, :first_line => "line1\n"}, YAML.load( File.read "/tmp/my-state.yml") )

    # Write two final lines:
    File.open  log_file, "a" do |file|
      file.puts "line5"
      file.puts "line6"
    end
    # Then rotate the file:
    File.rename  log_file, log_file+".1"
    # And write another line to the new log file:
    File.open  log_file, "a" do |file|
      file.puts "line7"
    end

    # Check that the final two lines from the rotated file and the new lines in
    # the new file are all processed:
    process[]
    assert_equal ["line5\n", "line6\n", "line7\n"], @lines

    # Check that the custom state file is as expected:
    assert_equal( {:cursor => 6, :first_line => "line7\n"}, YAML.load( File.read "/tmp/my-state.yml") )

    # Test not supplying the state file:
    # Remove the state file from previous runs of this test:
    File.unlink "/tmp/.apache_log_tail-state.yml"
    tail = ApacheLogTail.new  log_file
    @lines = []
    tail.each_new_line {|line| @lines << line }
    assert_equal ["line7\n"], @lines
  end

end

