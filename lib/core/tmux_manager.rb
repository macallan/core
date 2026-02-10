require 'open3'

module Core
  class TmuxManager
    class TmuxError < StandardError; end

    def initialize(repo: nil)
      @repo = repo
      @config = Config.tmux_config(repo)
    end

    # Check if currently running inside a tmux session
    def in_tmux?
      !ENV['TMUX'].nil? && !ENV['TMUX'].empty?
    end

    # Create a new tmux window in the current session
    # @param directory_path [String] The directory to open in the new window
    # @param window_name [String] The name for the new window (default: 'review')
    # @return [Hash] Result with :success, :window_name, :directory keys
    def create_window(directory_path, window_name = 'review')
      raise TmuxError, "Not running inside a tmux session" unless in_tmux?
      raise TmuxError, "Directory does not exist: #{directory_path}" unless File.directory?(directory_path)

      # Create new window with name and starting directory
      stdout, stderr, status = Open3.capture3(
        'tmux', 'new-window',
        '-n', window_name,
        '-c', directory_path
      )

      unless status.success?
        raise TmuxError, "Failed to create tmux window: #{stderr.strip}"
      end

      # Create additional panes based on configuration
      create_panes(directory_path)

      {
        success: true,
        window_name: window_name,
        directory: directory_path,
        session: current_session_name,
        panes: @config['panes'],
        split: @config['split']
      }
    end

    private

    # Create additional panes in the current window based on configuration
    # @param directory_path [String] The directory for the panes
    def create_panes(directory_path)
      pane_count = @config['panes'] || 2
      split_direction = @config['split'] || 'horizontal'

      # We already have 1 pane from the window creation, so create (pane_count - 1) more
      (pane_count - 1).times do
        split_flag = split_direction == 'horizontal' ? '-h' : '-v'

        stdout, stderr, status = Open3.capture3(
          'tmux', 'split-window',
          split_flag,
          '-c', directory_path
        )

        unless status.success?
          # Don't fail the whole operation if pane creation fails
          # Just log the error and continue
          warn "Warning: Failed to create tmux pane: #{stderr.strip}"
          break
        end
      end

      # Balance the panes to make them evenly sized
      balance_panes
    end

    # Balance the panes in the current window to make them evenly sized
    def balance_panes
      Open3.capture3('tmux', 'select-layout', 'even-horizontal')
      # Ignore errors - not critical if this fails
    end

    # Get the current tmux session name for debugging
    def current_session_name
      return nil unless in_tmux?

      stdout, status = Open3.capture2('tmux', 'display-message', '-p', '#S')
      status.success? ? stdout.strip : nil
    end
  end
end
