require_relative "base_Visualizer"
require_relative "../renderer/terminal"

module MusikVisulizer
  module Visualizers
    class AsciiWave < BaseVisualizer
      CHARS = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"].freeze

      COLRS = [
        [0, 0, 255],   # Blue
        [0, 255, 200],
        [0, 255, 0],    # Green
        [255, 255, 0],  # Yellow
        [255, 100, 0],  # Orange
        [255, 0, 0],    # Red
      ].freeze

      def initialize(buffer)
        super
        @smoothed = []
      end

      def render(analysis)
        spectrum = analysis[:spectrum]
        return if spectrum.nil? || spectrum.empty?

        bins = downsample(spectrum, cols)
        @smoothed = smooth(bins, @smoothed)

        draw_rows = rows - 1

        @smoothed.each_with_index do |value, col|
          bar_height = map_range(value, 0, draw_rows)
          color = interpolate_color(value)
          color_code = Renderer::Terminal.rgb_fg(*color)

          draw_rows.times do |row_from_top|
            row_from_bottom = draw_rows -1 - row_from_top
            row = row_from_top

            if row_from_bottom < bar_height
              char = if row_from_bottom == bar_height - 1
                       block_char(value, draw_rows)
                      else
                        CHARS.last
                      end
              @buffer.set(row, col, char, color: color_code)
            else
              @buffer.set(row, col, " ")
            end
          end
        end

        draw_info(analysis)
      end

      private


      def downsample(spectrum, target_size)
        return spectrum if spectrum.length <= target_size
        chunk_size = spectrum.length.to_f / target_size
        Array.new(target_size) do |i|
          start_idx = (i * chunk_size).floor
          end_idx = ((i + 1) * chunk_size).floor
          slice = spectrum[start_idx...end_idx]
          slice.sum / slice.length
        end
      end


      def smooth(current, previous)
        return current if previous.empty? || previous.length != current.length
        current.each_with_index.map do |val, i|
          prev = previous[i]
          if val > prev
            prev * 0.8 + val * 0.2
          else
            val * 0.1 + prev * 0.9
          end
        end
      end

      def block_char(value, max_height)
        fraction = (value * max_height) % 1.0
        index = (fraction * (CHARS.length - 1)).round
        CHARS[clamp(index, 0, CHARS.length - 1)]
      end

      def interpolate_color(value)
        scaled = value * (COLRS.length - 1)
        lower = scaled.floor
        upper = [lower + 1, COLRS.length - 1].min
        frac = scaled - lower

        c1 = COLRS[lower]
        c2 = COLRS[upper]

        [
          (c1[0] + (c2[0] - c1[0]) * frac).round,
          (c1[1] + (c2[1] - c1[1]) * frac).round,
          (c1[2] + (c2[2] - c1[2]) * frac).round
        ]
      end

      def draw_info(analysis)
        beat_marker = analysis[:beat] ? " *** BEAT *** " : ""
        info =  "Bass:#{(analysis[:bass] * 100).round}% " +
                "Mid:#{(analysis[:mid] * 100).round}% " +
                "High:#{(analysis[:high] * 100).round}% " +
                "RMS:#{(analysis[:rms] * 100).round}%" +
                beat_marker

        color = analysis[:beat] ? Renderer::Terminal.rgb_fg(255, 50, 50) : nil
        @buffer.write(rows - 1, 0, info.ljust(cols), color: color)
      end
    end
  end
end