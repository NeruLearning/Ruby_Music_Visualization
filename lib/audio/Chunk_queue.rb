require "thread"

module MusikVisulizer
  module Audio
    class ChunkQueue

      POISON_PILL = :done

      def initialize(max_size: 3)
        @max_size = max_size
        @queue = []
        @mutex = Mutex.new
        @not_full = ConditionVariable.new
        @not_empty = ConditionVariable.new
        @closed = false
      end

      def push(chunk_path)
        @mutex.synchronize do
          @not_full.wait(@mutex) while @queue.size >= @max_size && !@closed
          return if @closed

          @queue << chunk_path
          @not_empty.signal
        end
      end


      def pop
        @mutex.synchronize do
          @not_empty.wait(@mutex) while @queue.empty? && !@closed
          chunk = @queue.shift
          @not_full.signal
          chunk
        end
      end

      def close
        @mutex.synchronize do
          @closed = true
          @not_full.broadcast
          @not_empty.broadcast
        end
      end



      def closed?
        @mutex.synchronize { @closed }
      end


      def size
        @mutex.synchronize { @queue.size }
      end

      def empty?
        @mutex.synchronize { @queue.empty? }
      end
    end
  end
end


