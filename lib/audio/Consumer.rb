require "fileutils"
require_relative "chunk_queue"

module MusikVisulizer
  module Audio
    class Consumer
      def initialize(queue:)
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
      end

      # Lädt den nächsten Chunk parallel während der aktuelle läuft.
      # Block bekommt: |wav_path, data|
      def each_chunk_preloaded(loader)
        current_path = @queue.pop
        return if current_path.nil? || current_path == ChunkQueue::POISON_PILL

        current_data = loader.load(current_path)

        loop do
          # Nächsten Chunk sofort im Hintergrund laden
          next_path = nil
          next_data = nil
          prefetch_thread = Thread.new do
            np = @queue.pop
            unless np.nil? || np == ChunkQueue::POISON_PILL
              next_path = np
              begin
                next_data = loader.load(np)
              rescue => _e
                # nil bleibt, wird unten behandelt
              end
            end
          end

          begin
            yield current_path, current_data
          ensure
            cleanup(current_path)
          end

          prefetch_thread.join

          break if next_path.nil?

          current_path = next_path
          current_data = next_data || loader.load(current_path)
        end
      end

      private

      def cleanup(path)
        return unless path && File.exist?(path)
        FileUtils.rm_f(path)
      end
    end
  end
end