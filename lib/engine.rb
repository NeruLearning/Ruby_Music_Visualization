require_relative "audio/chunk_queue"
require_relative "audio/Producer"
require_relative "audio/Consumer"
require_relative "audio/loader"
require_relative "audio/analyzer"
require_relative "audio/player"
require_relative "renderer/terminal"
require_relative "renderer/frame_buffer"
require_relative "visualizers/ASCII_wave"

module MusikVisulizer
	class Engine
		DEFAULT_FRAME_SIZE = 1024
		DEFAULT_HOP_SIZE = 512

		def initialize(url, frame_size: DEFAULT_FRAME_SIZE, hop_size: DEFAULT_HOP_SIZE)
			@url = url
			@frame_size = frame_size
			@hop_size = hop_size
		end

		def run
			ENV["MUSIK_VISUALIZER_KEEP_SCREEN"] ||= "1"

			if should_spawn_terminal_window?
				return if spawn_terminal_window(@url)
			end

			terminal = Renderer::Terminal.new
			buffer = Renderer::FrameBuffer.new(terminal)
			visualizer = Visualizers::AsciiWave.new(buffer)

			queue = Audio::ChunkQueue.new(max_size: 6)
			loader = Audio::Loader.new
			analyzer = Audio::Analyzer.new
			player = Audio::Player.new
			player.warn_unavailable
			continuous = player.backend == :ffplay
			producer = Audio::Producer.new(queue: queue)

			setup_signal_handlers(producer)

			terminal.run do
				wait_for_terminal_size(terminal)
				producer.start(@url)
				prebuffer_target = continuous ? 1 : 4
				prebuffer_chunks(queue, target: prebuffer_target, timeout: 15.0)

				playback_pid = nil
				if continuous
					playback_source = producer.wait_for_playback_source(timeout: 30.0)
					playback_pid = player.play_async(playback_source) if playback_source
				end

				consumer = Audio::Consumer.new(queue: queue)
				consumer.each_chunk_preloaded(loader) do |wav_path, data|
					chunk_pid = nil
					chunk_pid = player.play_async(wav_path) unless continuous

					frames = loader.split_into_frames(
						data[:samples],
						frame_size: @frame_size,
						hop_size: @hop_size
					)
					frame_delay = @hop_size.to_f / data[:sample_rate]

					frames.each do |frame|
						break if playback_pid && !player.running?(playback_pid)
						buffer.sync_size
						analysis = analyzer.analyze(frame)
						buffer.clear
						visualizer.render(analysis)
						buffer.flush
						sleep(frame_delay) if frame_delay.positive?
					end

					player.wait(chunk_pid) if chunk_pid
					break if playback_pid && !player.running?(playback_pid)
				end

				player.wait(playback_pid) if playback_pid
			end
		ensure
			producer&.stop
		end

		private

		def should_spawn_terminal_window?
			return false unless Gem.win_platform?
			return false if ENV["MUSIK_VISUALIZER_NO_POPUP"] == "1"
			return false if ENV["MUSIK_VISUALIZER_POPUPPED"] == "1"
			return true if ENV["MUSIK_VISUALIZER_FORCE_POPUP"] == "1"
			ENV.key?("VSCODE_PID") || ENV["TERM_PROGRAM"] == "vscode"
		end

		def spawn_terminal_window(url)
			project_dir = File.expand_path("..", __dir__)
			escaped_url = escape_powershell(url)
			escaped_dir = escape_powershell(project_dir)
			command = "Set-Location -Path '#{escaped_dir}'; $env:MUSIK_VISUALIZER_POPUPPED='1'; $env:MUSIK_VISUALIZER_KEEP_SCREEN='1'; ruby .\\lib\\engine.rb '#{escaped_url}'"
			pid = Process.spawn(
				"cmd", "/c", "start", "", "powershell",
				"-NoProfile", "-NoExit", "-Command", command,
				out: File::NULL, err: File::NULL
			)
			Process.detach(pid)
			true
		rescue StandardError => e
			warn "[Engine] Could not open new terminal window: #{e.message}"
			false
		end

		def escape_powershell(value)
			value.to_s.gsub("'", "''")
		end

		def wait_for_terminal_size(terminal)
			return unless terminal.too_small?
			loop do
				terminal.clear
				terminal.write_line(1, "Terminal too small (min 10x40). Resize to continue.")
				sleep 0.5
				break unless terminal.too_small?
			end
			terminal.clear
		end

		def prebuffer_chunks(queue, target:, timeout: 15.0)
			deadline = Time.now + timeout
			while queue.size < target && !queue.closed? && Time.now < deadline
				sleep 0.1
			end
		end

		def setup_signal_handlers(producer)
			Signal.trap("INT") { producer.stop }
			Signal.trap("TERM") { producer.stop }
		end
	end
end

if __FILE__ == $PROGRAM_NAME
	url = ARGV[0]
	if url.nil? || url.strip.empty?
		puts "Aufruf: ruby lib/engine.rb \"https://youtube.com/watch?v=...\""
		exit 1
	end

	MusikVisulizer::Engine.new(url).run
end