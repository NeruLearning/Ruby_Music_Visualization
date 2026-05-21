module MusikVisulizer
  module Audio
    class Analyzer
      SAMPLE_RATE = 44100

      BANDS = {
        bass: (20..250),
        mid: (250..2000),
        high: (2000..8000),
        presence: (8000..20000)
      }.freeze

      BEAT_THRESHOLD_MULTIPLIER = 1.5
      BEAT_HISTORY_SIZE = 43

      def initialize
        @energy_history = []
      end

      def analyze(frame)
        spectrum = compute_fft(frame)
        rms = compute_rms(frame)
        bands = compute_bands(spectrum)
        beat = detect_beat(rms)

        update_energy_history(rms)

        {
          spectrum: spectrum,
          rms: rms,
          bass: bands[:bass],
          mid: bands[:mid],
          high: bands[:high],
          presence: bands[:presence],
          beat: beat,
          beat_intensity: beat ? (rms / average_energy).round(3) : 0.0
        }
      end

      private

      def compute_fft(frame)
        n = frame.length
        return [] if n.zero?

        windowed = apply_hanning_window(frame)
        complex_spectrum = windowed.map { |sample| [sample, 0.0] }
        result = fft_recursive(complex_spectrum)

        half = n / 2
        magnitudes = result[0...half].map do |real, imag|
          Math.sqrt(real * real + imag * imag)
        end

        max = magnitudes.max
        return Array.new(half, 0.0) if max.nil? || max.zero?

        magnitudes.map { |m| (m / max).round(6) }
      end

      def fft_recursive(samples)
        n = samples.length
        return samples if n <= 1

        even = fft_recursive(samples.each_with_index.select { |_, i| i.even? }.map(&:first))
        odd = fft_recursive(samples.each_with_index.select { |_, i| i.odd? }.map(&:first))

        result = Array.new(n, [0.0, 0.0])

        (n / 2).times do |k|
          angle = -2 * Math::PI * k / n
          wr = Math.cos(angle)
          wi = Math.sin(angle)
          or_r = odd[k][0]
          or_i = odd[k][1]
          t = [wr * or_r - wi * or_i, wr * or_i + wi * or_r]

          result[k] = [even[k][0] + t[0], even[k][1] + t[1]]
          result[k + n / 2] = [even[k][0] - t[0], even[k][1] - t[1]]
        end

        result
      end

      def apply_hanning_window(frame)
        n = frame.length
        return frame if n <= 1

        frame.each_with_index.map do |sample, i|
          sample * (0.5 * (1 - Math.cos(2 * Math::PI * i / (n - 1))))
        end
      end

      def compute_rms(frame)
        return 0.0 if frame.empty?

        mean_square = frame.sum { |s| s * s } / frame.length
        rms = Math.sqrt(mean_square)
        [[rms, 0.0].max, 1.0].min.round(6)
      end

      def compute_bands(spectrum)
        BANDS.transform_values do |range|
          extract_band_energy(spectrum, range.begin, range.end)
        end
      end

      def extract_band_energy(spectrum, freq_low, freq_high)
        return 0.0 if spectrum.empty?

        bin_low = freq_to_bin(freq_low, spectrum.length)
        bin_high = freq_to_bin(freq_high, spectrum.length)
        band = spectrum[bin_low..bin_high]
        return 0.0 if band.nil? || band.empty?

        energy = band.sum / band.length
        [[energy, 0.0].max, 1.0].min.round(6)
      end

      def freq_to_bin(freq_hz, spectrum_size)
        bin = (freq_hz * spectrum_size * 2.0 / SAMPLE_RATE).round
        [[bin, 0].max, spectrum_size - 1].min
      end

      def detect_beat(rms)
        return false if @energy_history.length < 10

        avg = average_energy
        return false if avg <= 0.0

        rms > avg * BEAT_THRESHOLD_MULTIPLIER
      end

      def average_energy
        return 0.0 if @energy_history.empty?

        @energy_history.sum / @energy_history.length
      end

      def update_energy_history(rms)
        @energy_history << rms
        @energy_history.shift if @energy_history.length > BEAT_HISTORY_SIZE
      end
    end
  end
end
