module MusikVisulizer
  module Visualizers
    class BaseVisualizer
      def initialize(buffer)
        @buffer = buffer
      end

      def render(analysis)
        raise NotImplementedError, "Subclasses must implement"
      end
      
      private

      def rows
        @buffer.instance_variable_get(:@rows)
      end

      def cols
        @buffer.instance_variable_get(:@cols)
      end

      def map_range(value, out_min, out_max)
        (value * (out_max - out_min)+ out_min).round
      end

      def clamp(value, min, max)
        [[value, min].max, max].min
      end
    end
  end
end

