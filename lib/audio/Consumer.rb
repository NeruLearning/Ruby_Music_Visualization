require "fileutils"
require_relative "chunk_queue"


module MusikVisulizer
  module Audio
    class Consumer
      def initialize(queue: )
        @queue = queue
      end


      def each_chunk
        loop do
          chunk_path = @queue.pop

          break if chunk_path.nil? || chunk_path == ChunkQueue::POISON_PILL

          begin
            yield chunk_path
          ensure
            cleanup(chunk_path)
          end
        end


        puts "[Consumer] No more chunks to process, exiting."
      end

      private


      def cleanup(path)
        return unless path && File.exist?(path)

        FileUtils.rm_f(path)
        puts "[Consumer] Cleaned up chunk file: #{path}"
      end
    end
  end
end



