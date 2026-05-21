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
			if should_spawn_terminal_window?
				spawn_terminal_window(@url)
				return
			end

			terminal = Renderer::Terminal.new
			buffer = Renderer::FrameBuffer.new(terminal)
			visualizer = Visualizers::AsciiWave.new(buffer)

			queue = Audio::ChunkQueue.new(max_size: 3)
			producer = Audio::Producer.new(queue: queue)
			consumer = Audio::Consumer.new(queue: queue)
			loader = Audio::Loader.new
			analyzer = Audio::Analyzer.new
			player = Audio::Player.new
			player.warn_unavailable

			setup_signal_handlers(producer)

			terminal.run do
				wait_for_terminal_size(terminal)
				producer.start(@url)

				consumer.each_chunk do |wav_path|
					data = loader.load(wav_path)
					playback_pid = player.play_async(wav_path)
					frames = loader.split_into_frames(
						data[:samples],
						frame_size: @frame_size,
						hop_size: @hop_size
					)
					frame_delay = @hop_size.to_f / data[:sample_rate]

					frames.each do |frame|
						analysis = analyzer.analyze(frame)
						buffer.clear
						visualizer.render(analysis)
						buffer.flush
						sleep(frame_delay) if frame_delay.positive?
					end

					player.wait(playback_pid)
				end
			end
		ensure
			producer&.stop
		end

		private

		def should_spawn_terminal_window?
			return false unless Gem.win_platform?
			return false if ENV["MUSIK_VISUALIZER_POPUPPED"] == "1"
			ENV["MUSIK_VISUALIZER_NO_POPUP"] != "1"
		end

		def spawn_terminal_window(url)
			project_dir = File.expand_path("..", __dir__)
			escaped_url = escape_powershell(url)
			command = "cd /d \"#{project_dir}\"; $env:MUSIK_VISUALIZER_POPUPPED='1'; ruby .\\lib\\engine.rb '#{escaped_url}'"

			pid = Process.spawn(
				"cmd",
				"/c",
				"start",
				"",
				"powershell",
				"-NoProfile",
				"-Command",
				command,
				out: File::NULL,
				err: File::NULL
			)
			Process.detach(pid)
		rescue StandardError => e
			warn "[Engine] Could not open new terminal window: #{e.message}"
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
