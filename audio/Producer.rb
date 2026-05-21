require "open3"
require "tmpdir"
require "fileutils"
require_relative "Chunk_queue"



module MusikVisulizer
  module Audio
    class Producer
      CHUNK_DURATION = 10
      SAMPLE_RATE = 44100
      BIT_RATE = 1


      class ProducerError < StandardError; end
      class DependencyError < StandardError; end

      def initialize(queue:, tmp_dir: Dir.tmpdir)
        @queue = queue
        @tmp_dir = tmp_dir
        @thread = nil
        check_dependencies!
      end


      def start(url)
        validate_url!(url)

        @thread = Thread.new do
          Thread.current.abort_on_exception = true
          begin
            if live_stream?(url)
              process_live_stream(url)
            else
              process_static_audio(url)
            end
          rescue => e
            puts "[Producer] Error processing URL #{url}: #{e.message}"
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
        
        offset = 0
        index = 0

        while offset < duration
          chunk_path = download_chunk(url, offset, CHUNK_DURATION, index)
          wav_path = convert_to_wav(chunk_path, index)
          cleanup(chunk_path)
          
          @queue.push(wav_path)

          offset += CHUNK_DURATION
          index += 1
        end
      end

      def doanload_chunk(url, offset, duration, index)
        output_path = File.join(@tmp_dir, "chunk_#{index}.%(ext)s")
        section = "*#{format_time(offset)}-#{format_time(offset + duration)}"

        cmd = [
          "yt-dlp",
          "--no-playlist",
          "--extract-audio",
          "--audio-format", "best",
          "--audio-quality", "0",
          "--download-sections", section,
          "--output", output_path,
          "--print", "after_move:filepath",
          "--no-progress",
          url
        ]
        stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          raise ProducerError, "yt-dlp chunk #{index} fehlgeschlagen:\n#{stderr.strip}"
        end

        path = stdout.lines.map(&:strip).reject(&:empty?).last
        raise ProducerError, "missing" if path.nil? || !File.exist?(path)

        path
      end



      def produce_livestream(url)
        puts "[producer] Livestream erkannt — kontinuierlicher Modus"
 
        # yt-dlp gibt die Stream-URL aus, ffmpeg liest direkt davon
        stream_url = fetch_stream_url(url)
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
 
          puts "[producer] Livestream-Chunk #{index + 1} bereit"
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

    def fetch_stream_url
      cmd = [
        "yt-dlp",
        "--get-url",
        "--extract-audio",
        url
      ]
      stdout, stderr, status = Open3.capture3(*cmd)
      raise ProducerError, "Stream-URL" unless status.success?

      stdout.strip
    end



    def convert_to_wav(input_path, index)
      output_path = File.join(@tmp_dir, "chunk_#{index}.wav")

      cmd = [
        "ffmpeg",
        "-y",
        "-i", input_path,
        "-acodec", "pcm_s16le",
        "-ar", SAMPLE_RATE.to_s,
        "-ac", CHANNELS.to_s,
        output_path,
        "-loglevel", "error"

    ]

    _, stderr, status = Open3.capture3(*cmd)
    raise ProducerError, "ffmpeg conversion" unless status.success?
    output_path
  end

  def fetch_duration(url)
    cmd = [
      "yt-dlp",
      "--print", "duration",
      "--no-playlist", url]
      raise ProducerError, "yt-dlp duration" unless status.success?

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
          _, _, status = Open3.capture3("which #{tool}")
          raise DependencyError, "#{tool} nicht gefunden" unless status.success?
        end 
      end

      def cleanup(path)
        return unless path && File.exist?(path)
        FileUtils.rm_f(path)
      end
    end
  end
end