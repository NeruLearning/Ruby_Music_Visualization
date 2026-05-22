require "open3"
require "tmpdir"
require "fileutils"
require_relative "chunk_queue"



module MusikVisulizer
  module Audio
    class Producer
      CHUNK_DURATION = 10
      SAMPLE_RATE = 44100
      CHANNELS = 2
      BIT_RATE = 1
      CENTER_STEREO_FILTER = "pan=stereo|c0=0.5*c0+0.5*c1|c1=0.5*c0+0.5*c1"


      class ProducerError < StandardError; end
      class DependencyError < StandardError; end

      def initialize(queue:, tmp_dir: Dir.tmpdir)
        @queue = queue
        @tmp_dir = tmp_dir
        @thread = nil
        @playback_source = nil
        @playback_mutex = Mutex.new
        @playback_cv = ConditionVariable.new
        check_dependencies!
      end

      def wait_for_playback_source(timeout: 30.0)
        deadline = Time.now + timeout
        @playback_mutex.synchronize do
          while @playback_source.nil? && Time.now < deadline
            remaining = deadline - Time.now
            @playback_cv.wait(@playback_mutex, [remaining, 0.1].max)
          end
          @playback_source
        end
      end


      def start(url)
        validate_url!(url)

        @thread = Thread.new do
          Thread.current.abort_on_exception = true
          begin
            if live_stream?(url)
              produce_livestream(url)
            else
              produce_chunks(url)
            end
          rescue => e
            $stderr.puts "[Producer] Error processing URL #{url}: #{e.message}"
          ensure
            @queue.close
          end
        end

        @thread
      end

      def join
        @thread&.join
      end

      def stop
        @thread&.kill
        @queue.close
      end

      private


      # VIdeo
      def produce_chunks(url)
        duration = fetch_duration(url)

        source, temp_source = prepare_source(url)
        set_playback_source(source)
        offset = 0
        index = 0

        begin
          while offset < duration
            segment_duration = [CHUNK_DURATION, duration - offset].min
            wav_path = download_chunk(source, offset, segment_duration, index)

            @queue.push(wav_path)

            offset += segment_duration
            index += 1
          end
        ensure
          cleanup(source) if temp_source
        end
      end

      def download_chunk(source, offset, duration, index)
        output_path = File.join(@tmp_dir, "chunk_#{index}.wav")

        cmd = [
          "ffmpeg",
          "-y",
          "-ss", offset.to_s,
          "-t", duration.to_s,
          "-i", source,
          "-acodec", "pcm_s16le",
          "-ar", SAMPLE_RATE.to_s,
          "-ac", CHANNELS.to_s,
          "-af", CENTER_STEREO_FILTER,
          output_path,
          "-loglevel", "error"
        ]

        _, stderr, status = Open3.capture3(*cmd)
        raise ProducerError, "ffmpeg chunk #{index} fehlgeschlagen:\n#{stderr.strip}" unless status.success?
        output_path
      end



      def produce_livestream(url)
        $stderr.puts "[producer] Livestream erkannt — kontinuierlicher Modus"
 
        # yt-dlp gibt die Stream-URL aus, ffmpeg liest direkt davon
        stream_url = fetch_stream_url(url)
        set_playback_source(stream_url)
        index      = 0
 
        # ffmpeg liest endlos vom Stream und schreibt Segmente
        # segment_time schneidet alle CHUNK_DURATION Sekunden
        segment_pattern = File.join(@tmp_dir, "live_chunk_%03d.wav")
 
        cmd = [
          "ffmpeg",
          "-i", stream_url,
          "-acodec", "pcm_s16le",
          "-ar", SAMPLE_RATE.to_s,
          "-ac", CHANNELS.to_s,
          "-af", CENTER_STEREO_FILTER,
          "-f", "segment",
          "-segment_time", CHUNK_DURATION.to_s,
          "-segment_format", "wav",
          segment_pattern,
          "-loglevel", "error"
        ]
 
        # ffmpeg laeuft im Hintergrund, wir lesen Segmente sobald sie erscheinen
        ffmpeg_pid = spawn(*cmd)
 
        loop do
          chunk_path = segment_pattern % index
 
          # Warten bis Segment existiert und vollstaendig ist
          wait_for_segment(chunk_path)
 
          $stderr.puts "[producer] Livestream-Chunk #{index + 1} bereit"
          @queue.push(chunk_path)
          index += 1
        end
      rescue => e
        Process.kill("TERM", ffmpeg_pid) if ffmpeg_pid
        raise e
      end





      def wait_for_segment(path, timeout: 30)
        start = Time.now
        loop do
          if File.exist?(path)

            size_before = File.size(path)
            sleep 0.2

            return if File.size(path) == size_before
          end

          raise ProducerError, "Timeout" if Time.now - start > timeout
          sleep 0.1
        end
      end

      def fetch_stream_url(url)
        cmd = [
          "yt-dlp",
          "--get-url",
          "-f", "bestaudio",
          "--no-playlist",
          url
        ]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise ProducerError, "Stream-URL: #{stderr.strip}" unless status.success?

        stdout.strip
      end

      def fetch_audio_url(url)
        cmd = [
          "yt-dlp",
          "--get-url",
          "-f", "bestaudio",
          "--no-playlist",
          url
        ]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise ProducerError, "Audio-URL: #{stderr.strip}" unless status.success?

        audio_url = stdout.lines.map(&:strip).reject(&:empty?).first
        raise ProducerError, "Audio-URL fehlt" if audio_url.nil? || audio_url.empty?

        audio_url
      end

      def prepare_source(url)
        output_path = File.join(@tmp_dir, "source.%(ext)s")
        cmd = [
          "yt-dlp",
          "--no-playlist",
          "-f", "bestaudio",
          "--output", output_path,
          "--print", "after_move:filepath",
          url
        ]

        stdout, stderr, status = Open3.capture3(*cmd)
        if status.success?
          path = stdout.lines.map(&:strip).reject(&:empty?).last
          return [path, true] if path && File.exist?(path)
        end

        warn "[Producer] Fallback to stream source: #{stderr.strip}" unless stderr.to_s.strip.empty?
        [fetch_audio_url(url), false]
      end

      def set_playback_source(source)
        @playback_mutex.synchronize do
          return if @playback_source
          @playback_source = source
          @playback_cv.broadcast
        end
      end

      def fetch_duration(url)
        cmd = [
          "yt-dlp",
          "--print", "duration",
          "--no-playlist",
          url
        ]
        stdout, stderr, status = Open3.capture3(*cmd)
        raise ProducerError, "yt-dlp duration: #{stderr.strip}" unless status.success?

        stdout.strip.to_f
      end

      def live_stream?(url)
        cmd = [
          "yt-dlp",
          "--print", "is_live",
          "--no-playlist", url
        ]
        stdout, _, status = Open3.capture3(*cmd)
        status.success? && stdout.strip == "True"

      end
      
      def chunk_count(duration)
        (duration / CHUNK_DURATION).ceil
      end

      def format_time(seconds)
        total = seconds.to_i
        h = total / 3600
        m = (total % 3600) / 60
        s = total % 60

        format("%02d:%02d:%02d", h, m, s)
      end



      def validate_url!(url)
        raise ProducerError, "Ungültige URL" if url.nil? || url.strip.empty?

        valid = [%r{youtube\.com/watch}, %r{youtu\.be/}, %r{youtube\.com/shorts/}]
        raise ProducerError, "Unsupported URL" unless valid.any? { |p| url.match?(p) }

      end

      def check_dependencies!
        %w[yt-dlp ffmpeg].each do |tool|
          raise DependencyError, "#{tool} nicht gefunden" unless tool_available?(tool)
        end
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

      def cleanup(path)
        return unless path && File.exist?(path)
        FileUtils.rm_f(path)
      end
    end
  end
end