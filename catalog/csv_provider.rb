require "json"

module Logimaxx
	module CialonaBOMExporter
		module Catalog
			class CsvProvider < Provider
				def initialize(csv_path)
					@csv_path = csv_path
					@loaded_at = nil
					@items = []
					@valid_uoms = %w[pcs m2 m custom].freeze
				end
				
				def search(query:, limit: 20)
					ensure_loaded!
					
					q = normalize(query)
					return [] if q.empty?
					
					# scor simplu: code exact > code prefix > label include
					scored = []
					
					@items.each do |it|
						code_n = it[:code_n]
						label_n = it[:label_n]
						
						score =
						if code_n == q
							300
						elsif code_n.start_with?(q)
							200
						elsif label_n.include?(q)
							100
						else
							0
						end
						
						next if score == 0
						scored << [score, it]
					end
					
					scored.sort_by! { |score, it| [-score, it[:code]] }
					
					scored.first(limit).map do |score, it|
						{
							code: it[:code],
							label: it[:label],
							uom: it[:uom],
							default_measure: it[:default_measure],
							tags: it[:tags]
						}.compact
					end
				end
				
				def refresh!
					@loaded_at = nil
					@items = []
				end
				
				private
				
				def ensure_loaded!
					mtime = File.mtime(@csv_path) rescue nil
					raise "Catalog CSV not found: #{@csv_path}" unless mtime
					
					return if @loaded_at && @loaded_at == mtime
					
					rows = parse_csv_with_headers(@csv_path)
					items = []
					
					rows.each_with_index do |r, idx|
						code  = (r["code"]  || "").strip
						label = (r["label"] || "").strip
						uom   = (r["uom"]   || "").strip
						default_measure = (r["default_measure"] || "").strip
						tags = (r["tags"] || "").split(";").map(&:strip).reject(&:empty?)
						
						raise "Missing code at line #{idx + 2}" if code.empty?
						raise "Missing label for #{code} at line #{idx + 2}" if label.empty?
						raise "Invalid uom '#{uom}' for #{code} at line #{idx + 2}" unless @valid_uoms.include?(uom)
						
						items << {
							code: code,
							label: label,
							uom: uom,
							default_measure: default_measure.empty? ? nil : default_measure,
							tags: tags,
							code_n: normalize(code),
							label_n: normalize(label)
						}
					end
					
					@items = items
					@loaded_at = mtime
				end
				
				def normalize(s)
					s.to_s.downcase.strip
				end

				# Minimal CSV parser to avoid requiring stdlib 'csv' (which pulls in 'date' gem
				# and breaks under SketchUp's embedded Ruby on Windows).
				def parse_csv_with_headers(path)
					raw = File.binread(path)
					raw.sub!(/\A\xEF\xBB\xBF/, "")  # strip BOM if present
					raw.force_encoding("UTF-8")
					lines = raw.lines.map(&:chomp).reject { |l| l.strip.empty? }
					return [] if lines.empty?
					headers = parse_csv_line(lines.shift)
					lines.map { |line| Hash[headers.zip(parse_csv_line(line))] }
				end

				def parse_csv_line(line)
					row = []
					current = +""
					in_quotes = false
					i = 0
					while i < line.length
						c = line[i]
						if in_quotes
							if c == '"'
								if line[i + 1] == '"'
									current << '"'
									i += 1
								else
									in_quotes = false
								end
							else
								current << c
							end
						elsif c == '"'
							in_quotes = true
						elsif c == ","
							row << current
							current = +""
						else
							current << c
						end
						i += 1
					end
					row << current
					row
				end
			end
		end
	end
end
		