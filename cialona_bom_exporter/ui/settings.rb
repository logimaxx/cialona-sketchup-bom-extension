# ui/settings.rb — Plugin settings dialog
# ------------------------------------------------------------------------------
# Persists settings via Sketchup.write_default / read_default (local machine).
# API profiles stay stored for the FileMaker calls, but this dialog no longer edits them.
# ------------------------------------------------------------------------------
require "base64"

module Logimaxx
  module CialonaBOMExporter
    module UI
      module Settings
        DIALOG_ID = :settings
        PREF_NAMESPACE = "Logimaxx_CialonaBOMExporter".freeze
        PREF_KEY_IMPORT_API_URL = "import_api_url".freeze
        PREF_KEY_OFFER_LINES_API_URL = "offer_lines_api_url".freeze
        PREF_KEY_IMPORT_API_KEY = "import_api_key".freeze
        PREF_KEY_CATALOG_API_URL = "catalog_api_url".freeze
        PREF_KEY_CATALOG_API_KEY = "catalog_api_key".freeze
        PREF_KEY_CATALOG_VALIDATE_CODES = "catalog_validate_codes".freeze
        PREF_KEY_CATALOG_SOURCE = "catalog_source".freeze
        PREF_KEY_FREE_EDIT_MODE = "free_edit_mode".freeze
        PREF_KEY_CATALOG_API_PROFILE = "catalog_api_profile".freeze
        PREF_KEY_IMPORT_API_PROFILE = "import_api_profile".freeze
        PREF_KEY_UNIT_MAP = "unit_map".freeze
        PREF_KEY_CATALOG_CSV_PATH = "catalog_csv_path".freeze
        PREF_KEY_CATALOG_CSV_FIELDS = "catalog_csv_fields".freeze
        PLUGIN_UOMS = %w[pcs m2 mtr m3 custom].freeze
        CSV_PRODUCT_FIELDS = %w[code name unit category].freeze
        CATALOG_SOURCE_API = "api".freeze
        CATALOG_SOURCE_CSV = "csv".freeze

        def self.template_path
          File.join(UI::UI_DIR, "settings.html")
        end

        def self.opts
          { width: 560, height: 720, title: 'Cialona BOM — Settings' }
        end

        def self.register(dialog)
          dialog.add_action_callback('get_settings') { |*_| on_get_settings(dialog) }
          dialog.add_action_callback('save_settings') { |_ctx, b64_str| on_save_settings(dialog, b64_str) }
          dialog.add_action_callback('pick_catalog_csv') { |*_| on_pick_catalog_csv(dialog) }
          dialog.add_action_callback('preview_catalog_csv') { |_ctx, path| on_preview_catalog_csv(dialog, path) }
          dialog.add_action_callback('close_dialog') { dialog.close }
        end

        def self.on_get_settings(dialog)
          csv_status = csv_header_status(resolved_catalog_csv_path)
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsLoaded", {
            import_api_url: stored_import_api_url,
            offer_lines_api_url: stored_offer_lines_api_url,
            filemaker_api_key: stored_filemaker_api_key,
            catalog_api_url: stored_catalog_api_url,
            catalog_validate_codes: stored_catalog_validate_codes,
            catalog_source: stored_catalog_source,
            free_edit_mode: stored_free_edit_mode,
            unit_map: stored_unit_map,
            catalog_csv_path: stored_catalog_csv_path,
            catalog_csv_fields: stored_catalog_csv_fields,
            catalog_csv_headers: csv_status[:headers],
            catalog_csv_header_error: csv_status[:error]
          })
        end

        def self.on_pick_catalog_csv(dialog)
          path = ::UI.openpanel("Select catalog CSV", "", "CSV|*.csv||")
          return if path.nil? || path.to_s.strip.empty?
          deliver_csv_preview(dialog, path.to_s.strip)
        end

        def self.on_preview_catalog_csv(dialog, path)
          path = path[0] if path.is_a?(Array)
          deliver_csv_preview(dialog, path.to_s.strip)
        end

        def self.deliver_csv_preview(dialog, stored_path)
          status = csv_header_status(stored_path)
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onCatalogCsvPicked", {
            path: stored_path,
            headers: status[:headers],
            error: status[:error]
          })
        end

        def self.on_save_settings(dialog, b64_str)
          # JS sends Base64-encoded JSON so the SketchUp bridge doesn't eval the string as Ruby.
          raw = b64_str.is_a?(Array) ? (b64_str[0] || b64_str) : b64_str
          raw = raw.to_s.strip
          if raw.empty?
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", { error: true, message: "No data received." })
            return
          end
          begin
            json_str = Base64.strict_decode64(raw)
            data = JSON.parse(json_str)
          rescue StandardError => e
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", { error: true, message: "Invalid data: #{e.message}" })
            return
          end
          import_api_url = (data["import_api_url"] || data[:import_api_url] || "").to_s.strip
          offer_lines_api_url = (data["offer_lines_api_url"] || data[:offer_lines_api_url] || "").to_s.strip
          filemaker_api_key = if data.key?("filemaker_api_key") || data.key?(:filemaker_api_key)
            (data["filemaker_api_key"] || data[:filemaker_api_key]).to_s.strip
          else
            stored_filemaker_api_key
          end
          catalog_api_url = (data["catalog_api_url"] || data[:catalog_api_url] || "").to_s.strip
          val = data["catalog_validate_codes"] || data[:catalog_validate_codes]
          catalog_validate_codes = val
          raw_source = (data["catalog_source"] || data[:catalog_source] || CATALOG_SOURCE_API).to_s.strip.downcase
          catalog_source = (raw_source == CATALOG_SOURCE_CSV) ? CATALOG_SOURCE_CSV : CATALOG_SOURCE_API
          free_edit_val = data.key?("free_edit_mode") ? data["free_edit_mode"] : data[:free_edit_mode]
          free_edit_mode = (free_edit_val == true || free_edit_val.to_s.downcase == "true")
          csv_path = if data.key?("catalog_csv_path") || data.key?(:catalog_csv_path)
            (data["catalog_csv_path"] || data[:catalog_csv_path]).to_s.strip
          else
            stored_catalog_csv_path
          end
          begin
            unit_map_value = data.key?("unit_map") ? data["unit_map"] : data[:unit_map]
            unit_map = JSON.generate(unit_map_value.nil? ? stored_unit_map : normalize_unit_map(unit_map_value))
            csv_fields_value = data.key?("catalog_csv_fields") ? data["catalog_csv_fields"] : data[:catalog_csv_fields]
            csv_fields_hash = csv_fields_value.nil? ? stored_catalog_csv_fields : normalize_catalog_csv_fields(csv_fields_value)
            if catalog_source == CATALOG_SOURCE_CSV && csv_fields_hash["code"].to_s.strip.empty?
              raise ArgumentError, "Choose the CSV column for the product code."
            end
            csv_fields = JSON.generate(csv_fields_hash)
            catalog_api_profile = profile_from_payload(data, "catalog_api_profile", default_catalog_api_profile)
            import_api_profile = profile_from_payload(data, "import_api_profile", default_import_api_profile)
          rescue StandardError => e
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", { error: true, message: "Invalid settings: #{e.message}" })
            return
          end
          begin
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_URL, import_api_url)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_OFFER_LINES_API_URL, offer_lines_api_url)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_KEY, filemaker_api_key)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_URL, catalog_api_url)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_KEY, filemaker_api_key)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_VALIDATE_CODES, catalog_validate_codes ? "true" : "false")
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_SOURCE, catalog_source)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_FREE_EDIT_MODE, free_edit_mode ? "true" : "false")
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_UNIT_MAP, unit_map)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_CSV_PATH, csv_path)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_CSV_FIELDS, csv_fields)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_PROFILE, catalog_api_profile) unless catalog_api_profile.nil?
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_PROFILE, import_api_profile) unless import_api_profile.nil?
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", {})
          rescue StandardError => e
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", { error: true, message: e.message })
          end
        end

        # Returns the normalized profile when the payload includes the key, otherwise nil
        # so a save from this dialog does not overwrite a profile it no longer edits.
        def self.profile_from_payload(data, key, fallback)
          return nil unless data.key?(key) || data.key?(key.to_sym)
          normalize_profile(data[key] || data[key.to_sym], fallback)
        end

        def self.stored_import_api_url
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_URL).to_s
        end

        # A missing key keeps older installs working: offer lines used to be the import
        # URL with "import-sketch" rewritten to "get-offer-lines". An explicit empty value stays empty.
        def self.stored_offer_lines_api_url
          raw = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_OFFER_LINES_API_URL)
          return raw.to_s.strip unless raw.nil?
          derive_offer_lines_url(stored_import_api_url)
        end

        def self.derive_offer_lines_url(import_url)
          url = import_url.to_s.strip
          return "" if url.empty? || !url.include?("import-sketch")
          url.sub("import-sketch", "get-offer-lines")
        end

        # One FileMaker key. Older installs stored it separately for catalog and import.
        def self.stored_filemaker_api_key
          import_key = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_KEY).to_s.strip
          return import_key unless import_key.empty?
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_KEY).to_s.strip
        end

        def self.stored_import_api_key
          stored_filemaker_api_key
        end

        def self.stored_catalog_api_url
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_URL).to_s
        end

        def self.stored_catalog_api_key
          stored_filemaker_api_key
        end

        # Default true: validate product codes against catalog API on blur.
        def self.stored_catalog_validate_codes
          v = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_VALIDATE_CODES)
          return true if v.nil?
          v.to_s.downcase != "false"
        end

        # Default "api": product search/validate via FileMaker query_products.
        def self.stored_catalog_source
          v = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_SOURCE).to_s.strip.downcase
          return CATALOG_SOURCE_CSV if v == CATALOG_SOURCE_CSV
          CATALOG_SOURCE_API
        end

        def self.stored_free_edit_mode
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_FREE_EDIT_MODE).to_s.downcase == "true"
        end

        def self.stored_catalog_csv_path
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_CSV_PATH).to_s.strip
        end

        def self.resolved_catalog_csv_path
          stored_catalog_csv_path
        end

        def self.empty_catalog_csv_fields
          CSV_PRODUCT_FIELDS.each_with_object({}) { |field, map| map[field] = "" }
        end

        def self.normalize_catalog_csv_fields(value)
          raw = value.is_a?(String) ? JSON.parse(value) : value
          raw = {} unless raw.is_a?(Hash)
          result = {}
          CSV_PRODUCT_FIELDS.each do |field|
            column = raw.key?(field) ? raw[field] : raw[field.to_sym]
            result[field] = column.to_s.strip
          end
          result
        end

        def self.stored_catalog_csv_fields
          raw = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_CSV_FIELDS)
          return empty_catalog_csv_fields if raw.nil? || raw.to_s.strip.empty?
          normalize_catalog_csv_fields(raw)
        rescue StandardError
          empty_catalog_csv_fields
        end

        # { headers:, error: } for the first row. error is "missing", "invalid", or nil.
        def self.csv_header_status(path)
          path = path.to_s.strip
          return { headers: [], error: nil } if path.empty?
          unless File.file?(path)
            return { headers: [], error: "missing" }
          end
          raw = File.read(path).sub(/\A\xEF\xBB\xBF/, "")
          rows = Attributes.parse_csv(raw)
          headers = []
          seen = {}
          (rows.shift || []).each do |header|
            name = header.to_s.strip
            next if name.empty? || seen[name]
            seen[name] = true
            headers << name
          end
          { headers: headers, error: nil }
        rescue StandardError
          { headers: [], error: "invalid" }
        end

        def self.default_catalog_api_profile
          JSON.generate({ method: "POST", auth: { location: "query", name: "apiKey" }, request: { query_path: "query", limit_path: "resultLimit" }, response: { items_path: "scriptResult.result", fallback_items_paths: ["results", "data"], fields: { code: "code", name: "name", unit: "unit", category: "category" } } })
        end

        def self.default_import_api_profile
          JSON.generate({ auth: { location: "query", name: "apiKey" }, load: { method: "POST", url: "{{offer_lines_url}}", request: { offer_id_path: "offer_id" }, response: { items_path: "scriptResult.result", fallback_items_paths: ["result"] } }, export: { method: "POST", url: "{{import_url}}", request: { offer_id_path: "offer_id", items_path: "items" } }, fields: { id: "id", code: "code", quantity: "quantity", uom: "uom", category: "category" } })
        end

        def self.normalize_profile(value, fallback)
          text = value.to_s.strip
          text = fallback if text.empty?
          parsed = JSON.parse(text)
          raise ArgumentError, "API profile must be a JSON object." unless parsed.is_a?(Hash)
          JSON.generate(parsed)
        end

        def self.stored_catalog_api_profile
          normalize_profile(Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_PROFILE), default_catalog_api_profile)
        rescue StandardError
          default_catalog_api_profile
        end

        def self.stored_import_api_profile
          normalize_profile(Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_PROFILE), default_import_api_profile)
        rescue StandardError
          default_import_api_profile
        end

        # Plugin UOM => { "export" => external name written on BOM lines,
        #                 "accept" => extra names read from catalog and offer lines }.
        # The plugin UOM itself is always accepted. export defaults to that UOM.
        def self.default_unit_map
          {
            "pcs" => { "export" => "pcs", "accept" => ["stuks", "stuk", "pieces"] },
            "m2" => { "export" => "m2", "accept" => ["m²"] },
            "mtr" => { "export" => "mtr", "accept" => ["mtr.", "m", "meter", "meters", "linear meter"] },
            "m3" => { "export" => "m3", "accept" => ["m³", "m3.", "cubic meter", "cubic meters"] },
            "custom" => { "export" => "custom", "accept" => [] }
          }
        end

        def self.normalize_unit_map(value)
          raw = value.is_a?(String) ? JSON.parse(value) : value
          raw = {} unless raw.is_a?(Hash)
          result = {}
          seen = {}
          PLUGIN_UOMS.each do |uom|
            entry = raw[uom] || raw[uom.to_sym] || {}
            entry = {} unless entry.is_a?(Hash)
            export_name = (entry["export"] || entry[:export] || uom).to_s.strip
            export_name = uom if export_name.empty?
            accept = entry["accept"] || entry[:accept] || []
            accept = accept.to_s.split(",") unless accept.is_a?(Array)
            names = []
            accept.each do |name|
              text = name.to_s.strip
              next if text.empty?
              next if text.casecmp(uom).zero? || text.casecmp(export_name).zero?
              next if names.any? { |existing| existing.casecmp(text).zero? }
              names << text
            end
            ([uom, export_name] + names).each do |token|
              key = token.downcase
              if seen[key] && seen[key] != uom
                raise ArgumentError, %(Unit alias "#{token}" is used by both #{seen[key]} and #{uom}.)
              end
              seen[key] = uom
            end
            result[uom] = { "export" => export_name, "accept" => names }
          end
          result
        end

        def self.stored_unit_map
          raw = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_UNIT_MAP)
          return default_unit_map if raw.nil? || raw.to_s.strip.empty?
          normalize_unit_map(raw)
        rescue StandardError
          default_unit_map
        end
      end
    end
  end
end
