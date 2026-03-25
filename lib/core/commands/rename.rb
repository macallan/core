require 'open3'

module Core
  module Commands
    class Rename < Base
      def run
        new_name = @args.shift

        unless new_name && !new_name.strip.empty?
          UI.say_error("Missing new name argument")
          puts "Usage: core rename NEW_NAME"
          exit 1
        end

        require_relative '../tmux_manager'

        tmux = TmuxManager.new
        unless tmux.in_tmux?
          UI.say_error("Not running inside a tmux session")
          exit 1
        end

        begin
          # Rename the current window (empty target = current window)
          stdout, stderr, status = Open3.capture3('tmux', 'rename-window', new_name)
          unless status.success?
            UI.say_error("Failed to rename window: #{stderr.strip}")
            exit 1
          end

          UI.say_ok("Renamed window to '#{new_name}'")
        end
      end
    end
  end
end
