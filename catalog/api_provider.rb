module Logimaxx
	module CialonaBOMExporter
		module Catalog
			class APIProvider < Provider
				def initialize(api_url)
					@api_url = api_url
				end
				
				def search(query:, limit:)
					raise NotImplementedError
				end
			end
		end
	end
end