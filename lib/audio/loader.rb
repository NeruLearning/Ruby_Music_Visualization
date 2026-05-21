require "wavefile"

module MusikVisulizer
  module Audio
    class Loader
      class LoaderError < StandardError; end


      EXPECTED_SAMPLE_RATE = 44100
      ACCEPTED_CHANNELS = [1, 2].freeze


      def load(wav_path)
        raise LoaderError, "File not found: #{wav_path}" unless File.exist?(wav_path)

        samples = []

        sample_rate = nil

        WaveFile::Reader.new(wav_path) do |reader|
          native_format = reader.native_format
          validate_format!(native_format, wav_path)
          sample_rate = native_format.sample_rate

          reader.each_buffer(4096) do |buffer|
            samples.concat(normalize_samples(buffer.samples, native_format))
          end
        end

        raise LoaderError, "Leere WAV-Datei" if samples.empty?
        duration = samples.length.to_f / sample_rate

        {
          samples: samples,
          sample_rate: sample_rate,
          duration: duration.round(3),
          num_samples: samples.length
        }

      rescue WaveFile::InvalidFormatError => e
        raise LoaderError, "Ungültiges WAV-Format"
      end



      def split_into_frames(samples, frame_size: 1024, hop_size: 512)
        frames = []
        offset = 0

        while offset + frame_size <= samples.length
          frames << samples[offset, frame_size]
          offset += hop_size
        end


        remainder = samples.length - offset
        if remainder > 0
          last_frame = samples[offset, remainder] + Array.new(frame_size - remainder, 0.0)
          frames << last_frame
        end

        frames
      end

      private


      def validate_format!(native_format, path)
        unless ACCEPTED_CHANNELS.include?(native_format.channels)
          raise LoaderError, "Unerwartete Kanalanzahl"
        end

        if native_format.sample_rate != EXPECTED_SAMPLE_RATE
          raise LoaderError, "Unerwartete Abtastrate"
        end
      end

      def normalize_samples(raw_samples, format)
        scale = scale_for_format(format.sample_format)
        channels = format.channels

        if channels == 1
          raw_samples.map { |sample| normalize_sample(sample, scale) }
        else
          raw_samples.map do |sample|
            left, right = sample
            (normalize_sample(left, scale) + normalize_sample(right, scale)) / 2.0
          end
        end
      end

      def normalize_sample(sample, scale)
        value = scale == 1.0 ? sample.to_f : sample.to_f / scale
        [[value, -1.0].max, 1.0].min
      end

      def scale_for_format(sample_format)
        case sample_format
        when :float
          1.0
        when :pcm_8
          128.0
        when :pcm_16
          32_768.0
        when :pcm_24
          8_388_608.0
        when :pcm_32
          2_147_483_648.0
        else
          1.0
        end
      end
    end
  end
end



