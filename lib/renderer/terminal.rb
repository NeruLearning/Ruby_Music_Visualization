require "io/console"

module MusikVisulizer
  module Renderer
    class Terminal
      
      ESC = "\e"
      CLEAR = "#{ESC}[2J"
      HIDE_CURSOR = "#{ESC}[?25l"
      SHOW_CURSOR = "#{ESC}[?25h"
      RESET_COLOR = "#{ESC}[0m"
      CURSOR_HOME = "#{ESC}[H"

      def self.color_fg(index)
        "#{ESC}[38;5;#{index}m"
      end

      def self.color_bg(index)
        "#{ESC}[48;5;#{index}m"
      end

      def self.rgb_fg(r, g, b)
        "#{ESC}[38;2;#{r};#{g};#{b}m"
      end

      def self.rgb_bg(r, g, b)
        "#{ESC}[48;2;#{r};#{g};#{b}m"
      end

      attr_reader :rows, :cols

      def initialize
        @rows, @cols =detect_size
        @output = $stdout
        @setup_done = false
      end

      def setup
        @output.sync = true
        hide_cursor
        clear
        @setup_done = true

        if Signal.list.key?("WINCH")
          Signal.trap("WINCH") { update_size }
        end
      end


      def teardown
        show_cursor
        print RESET_COLOR
        unless ENV["MUSIK_VISUALIZER_KEEP_SCREEN"] == "1"
          clear
          move_cursor(1, 1)
        end
        @setup_done = false
      end
      
      def run
        setup
        yield
      ensure
        teardown
      end


      def move_cursor(row, col)
        print "#{ESC}[#{row};#{col}H"
      end

      def hide_cursor
        print HIDE_CURSOR
      end

      def show_cursor
        print SHOW_CURSOR
      end


      def clear
        print CLEAR
        print CURSOR_HOME
      end

      def write(row, col, text, color: nil)
        move_cursor(row, col)
        print color if color
        print text
        print RESET_COLOR if color
      end

      def write_line (row, text, color: nil)
        padded = text.ljust(cols)[0, cols]
        write(row, 1, padded, color: color)
      end

      def clear_line(row)
        write(row, 1, " " * cols)
      end

      def update_size
        @rows, @cols = detect_size
      end

      def too_small?
        @rows < 10 || @cols < 40
      end

      private


      def detect_size
        if $stdout.respond_to?(:winsize) && $stdout.isatty
          rows, cols = $stdout.winsize
          return [rows, cols] if rows > 0 && cols > 0
        end 
      
      rows = ENV["LINES"]&.to_i || 24
      cols = ENV["COLUMNS"]&.to_i || 80
      [rows, cols]
      end
    end
  end
end

