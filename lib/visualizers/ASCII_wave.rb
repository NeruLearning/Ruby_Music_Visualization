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
        @last_cols = nil
      end

      def render(analysis)
        spectrum = analysis[:spectrum]

        half_cols = (cols / 2.0).ceil

        # Bei Resize: smoothed zurücksetzen damit keine alten Werte reinlaufen
        if @last_cols != cols
          @smoothed = Array.new(half_cols, 0.0)
          @last_cols = cols
        end

        if spectrum.nil? || spectrum.empty?
          @smoothed = @smoothed.map { |v| v * 0.15 }
        else
          bins = downsample(spectrum, half_cols)
          @smoothed = smooth(bins, @smoothed)
        end

        draw_rows = rows
        center_left = (cols - 1) / 2
        center_right = cols / 2

        @smoothed.each_with_index do |value, i|
          left_col = center_left - i
          right_col = center_right + i

          draw_bar_at(left_col, value, draw_rows) if left_col >= 0
          if right_col < cols && right_col != left_col
            draw_bar_at(right_col, value, draw_rows)
          end
        end
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

      def draw_bar_at(col, value, draw_rows)
        bar_height = map_range(value, 0, draw_rows)
        color = interpolate_color(value)
        color_code = Renderer::Terminal.rgb_fg(*color)

        draw_rows.times do |row_from_top|
          row_from_bottom = draw_rows - 1 - row_from_top

          if row_from_bottom < bar_height
            char = if row_from_bottom == bar_height - 1
                     block_char(value, draw_rows)
                   else
                     CHARS.last
                   end
            @buffer.set(row_from_top, col, char, color: color_code)
          else
            @buffer.set(row_from_top, col, " ")
          end
        end
      end
    end
  end
end