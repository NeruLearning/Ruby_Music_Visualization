require_relative "audio/chunk_queue"
require_relative "audio/Producer"
require_relative "audio/Consumer"
 
url = ARGV[0]
 
if url.nil? || url.empty?
  puts "Aufruf: ruby test_pipeline.rb \"https://youtube.com/watch?v=...\""
  exit 1
end
 
puts "=== Pipeline Test ==="
puts "URL: #{url}"
puts ""
 
queue    = MusikVisulizer::Audio::ChunkQueue.new(max_size: 3)
producer = MusikVisulizer::Audio::Producer.new(queue: queue)
consumer = MusikVisulizer::Audio::Consumer.new(queue: queue)
 
# Producer startet im Hintergrund
producer.start(url)
 
# Consumer laeuft im Hauptthread
chunk_index = 0
 
consumer.each_chunk do |wav_path|
  chunk_index += 1
  size_kb = (File.size(wav_path) / 1024.0).round(1)
  puts "[test] Chunk #{chunk_index} erhalten: #{File.basename(wav_path)} (#{size_kb} KB)"
  puts "[test] Queue-Groesse gerade: #{queue.size}"
  puts ""
 
  # Simuliert Verarbeitung (spaeter kommt hier Analyzer + Visualizer)
  sleep 2
end
 
puts "=== Fertig — #{chunk_index} Chunks verarbeitet ==="