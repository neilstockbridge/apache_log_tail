
# Facilitates reading the most recent additions to a log file.
#
# Example:
#     tail = ApacheLogTail.new "/var/log/apache2/access.log"
#     tail.state_store.path_to_file = "/tmp/my-state.yml" # Optional: there is a default path
#     tail.each_new_line {|line| puts line }
#
# ## A custom StateStore
#
#     tail.state_store = MyStateStore.new
#
# A StateStore object must provide these methods:
#
#  - remember( state:Hash)
#  - recall(): Hash
#
class LogTail

  # @param [String] path_to_file  the path to the file to process
  #
  def initialize path_to_file
    @path_to_file = path_to_file
  end

  # The StateStore provides persistent storage of a Hash.
  #
  def state_store
    @state_store ||= FileStateStore.new
  end
  attr_writer :state_store

  # Goes through each line in the file that has not yet been processed and
  # passes it to the block given.
  #
  # @param [String] path_to_file  the path to the file that should be
  #                               processed.  This parameter is only intended
  #                               for internal use ( processing rotated log
  #                               files) and should be omitted for normal use
  #
  def each_new_line path_to_file = @path_to_file

    # Recall the cursor ( the location in the log file where we left off
    # reading last time)
    state = state_store.recall
    state[:cursor] ||= 0

    File.open  path_to_file do |stream|
      # Move the file reading "head" to the place where we left off reading
      # last time
      stream.seek  state[:cursor]

      stream.each_line {|line| yield line }

      # Remember where the log file reading cursor is for next time:
      state[:cursor] = stream.tell
      state_store.remember  state
    end
  end

  # This is the default implementation of StateStore, which stores the state in
  # a file ( by default in /tmp with a static name although this is
  # configurable).
  #
  class FileStateStore

    # Provides the path to the file that is used to store the state ( unless a
    # custom StateStore is used).
    #
    def path_to_file
      @path_to_file ||= "/tmp/.apache_log_tail-state.yml"
    end
    attr_writer :path_to_file

    require "yaml"

    # Retrieves the state from the store.
    # @return [Hash]
    #
    def recall
      if not File.exists? path_to_file
        {}
      else
        YAML.load File.read( path_to_file)
      end
    end

    # Stores the supplied state.
    # @param [Hash] state
    #
    def remember state
      File.open  path_to_file, "w" do |file|
        file.write  state.to_yaml
      end
    end

  end # of FileStateStore

end


# (see LogTail)
#
# Will not miss any lines when the log file is rotated between two invocations
# of #each_new_line ( as long as the rotated file has the same name as the
# original except for a `.1` suffix and as long as the file hasn't been rotated
# twice between invocations of #each_new_line).
#
# Note that this class does not parse Apache log entries, only knows how Apache
# log files are rotated on Debian.  I have enjoyed using the `apachelogregex`
# gem for parsing.
#
class ApacheLogTail < LogTail

  # (see LogTail#each_new_line)
  #
  # Note: This method must be invoked more frequently than the log file
  # rotation period ( typically 1 week) otherwise an entire file will be
  # missed.
  #
  def each_new_line
    state = state_store.recall
    first_line_now = first_line_of @path_to_file
    # If the Apache log file has been rotated..
    # The file has been rotated if it has been read ( cursor is remembered) but
    # the first line is not as remembered
    file_has_been_rotated = lambda { state[:cursor] and first_line_now != state[:first_line] }
    if file_has_been_rotated[]
      # Check that the renamed file is as we expect before reading the rest of it:
      renamed_file = @path_to_file + ".1"
      if first_line_of( renamed_file) != state[:first_line]
        raise StandardError.new "Rotated file could not be found"
      end
      # Process the last lines of the rotated file:
      super renamed_file
      # Reset the cursor ready for the new file:
      state[:cursor] = 0
    end
    if first_line_now != state[:first_line]
      state[:first_line] = first_line_now
      state_store.remember state
    end
    # Process the lines that have since been added to the new file:
    super
  end


 private

  def first_line_of file
    File.open  file do |f|
      f.gets
    end
  end

end

