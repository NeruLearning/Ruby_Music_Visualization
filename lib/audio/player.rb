module MusikVisulizer
  module Audio
    class Player
      class PlaybackError < StandardError; end

      def initialize
        @backend = detect_backend
      end

      attr_reader :backend

      def available?
        !@backend.nil?
      end

      def warn_unavailable
        return if available?

        warn "[Audio] No audio backend found. Install ffplay or enable Windows SoundPlayer."
      end

      def play_async(path)
        return nil unless available?

        case @backend
        when :ffplay
          spawn_ffplay(path)
        when :sound_player
          spawn_sound_player(path)
        else
          nil
        end
      end

      def wait(pid)
        return if pid.nil?

        Process.wait(pid)
      rescue Errno::ECHILD
        nil
      end

      def running?(pid)
        return false if pid.nil?

        result = Process.waitpid(pid, Process::WNOHANG)
        result.nil?
      rescue Errno::ECHILD
        false
      end

      private

      def detect_backend
        return :ffplay if tool_available?("ffplay")
        return :sound_player if Gem.win_platform? && tool_available?("powershell")

        nil
      end

      def tool_available?(tool)
        path_env = ENV.fetch("PATH", "")
        return false if path_env.empty?

        extensions = if Gem.win_platform?
                       ENV.fetch("PATHEXT", ".EXE;.BAT;.CMD").split(";")
                     else
                       [""]
                     end

        path_env.split(File::PATH_SEPARATOR).any? do |dir|
          extensions.any? do |ext|
            File.executable?(File.join(dir, "#{tool}#{ext}"))
          end
        end
      end

      def spawn_ffplay(path)
        spawn(
          "ffplay",
          "-nodisp",
          "-autoexit",
          "-loglevel",
          "error",
          path.to_s,
          out: File::NULL,
          err: File::NULL
        )
      end

      def spawn_sound_player(path)
        escaped = path.to_s.gsub("'", "''")
        command = "(New-Object System.Media.SoundPlayer '#{escaped}').PlaySync()"
        spawn(
          "powershell",
          "-NoProfile",
          "-Command",
          command,
          out: File::NULL,
          err: File::NULL
        )
      end
    end
  end
end
