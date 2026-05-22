module MusikVisulizer
  module Renderer
    class FrameBuffer
      Cell = Struct.new(:char, :color)
      EMPTY_CELL = Cell.new(" ", nil).freeze

      def initialize(terminal)
        @terminal = terminal
        @rows = terminal.rows
        @cols = terminal.cols
        @current = build_empty_buffer
        @next = build_empty_buffer
        @needs_full_redraw = false
      end

      def set(row, col, char, color: nil)
        return if out_of_bounds?(row, col)
        @next[row][col] = Cell.new(char, color)
      end

      def write(row, col, text, color: nil)
        text.each_char.with_index do |char, i|
          set(row, col + i, char, color: color)
        end
      end

      def clear_row(row)
        return if row < 0 || row >= @rows
        @cols.times { |col| @next[row][col] = EMPTY_CELL }
      end

      def clear
        @rows.times { |row| clear_row(row) }
      end

      def sync_size
        @terminal.update_size
        return false if @terminal.rows == @rows && @terminal.cols == @cols

        @rows = @terminal.rows
        @cols = @terminal.cols
        @terminal.clear
        @current = build_empty_buffer
        @next = build_empty_buffer
        true
      end

      def flush
        # Resize zwischen Render und Flush: @next ist ungueltig, Frame verwerfen.
        return if sync_size

        # Vollständigen Redraw erzwingen falls angefordert
        if @needs_full_redraw
          @current = build_empty_buffer
          @needs_full_redraw = false
        end

        changes = collect_changes
        render_changes(changes)

        @current, @next = @next, @current
        copy_buffer(@current, @next)
      end

      attr_reader :last_changes_count

      private

      def collect_changes
        changes = []
        @rows.times do |row|
          @cols.times do |col|
            next_cell = @next[row][col]
            current_cell = @current[row][col]
            unless cells_equal?(next_cell, current_cell)
              changes << [row, col, next_cell]
            end
          end
        end
        @last_changes_count = changes.length
        changes
      end

      def render_changes(changes)
        last_color = nil

        changes.each do |row, col, cell|
          @terminal.move_cursor(row + 1, col + 1)

          if cell.color != last_color
            if cell.color
              print cell.color
            else
              print "\e[0m"
            end
            last_color = cell.color
          end

          print cell.char
        end

        print "\e[0m" if last_color
      end

      def cells_equal?(a, b)
        a.char == b.char && a.color == b.color
      end

      def build_empty_buffer
        Array.new(@rows) { Array.new(@cols) { EMPTY_CELL.dup } }
      end

      def copy_buffer(source, target)
        @rows.times do |row|
          @cols.times do |col|
            target[row][col] = source[row][col].dup
          end
        end
      end

      def out_of_bounds?(row, col)
        row < 0 || row >= @rows || col < 0 || col >= @cols
      end
    end
  end
end