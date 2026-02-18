module Logimaxx
    module CialonaBOMExporter
        module Catalog
            class Provider
                def search(query:, limit:)
                    raise NotImplementedError
                end
                
                def refresh!
                end
            end
        end
    end
end