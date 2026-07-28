# ui/settings.rb — Plugin settings dialog (step 1: API URL, stored locally)
# ------------------------------------------------------------------------------
# Persists API URL via Sketchup.write_default / read_default (local machine).
# ------------------------------------------------------------------------------
require "base64"

module Logimaxx
  module CialonaBOMExporter
    module UI
      module Settings
        DIALOG_ID = :settings
        PREF_NAMESPACE = "Logimaxx_CialonaBOMExporter".freeze
        PREF_KEY_IMPORT_API_URL = "import_api_url".freeze
        PREF_KEY_IMPORT_API_KEY = "import_api_key".freeze
        PREF_KEY_CATALOG_API_URL = "catalog_api_url".freeze
        PREF_KEY_CATALOG_API_KEY = "catalog_api_key".freeze
        PREF_KEY_CATALOG_VALIDATE_CODES = "catalog_validate_codes".freeze

        def self.template_path
          File.join(UI::UI_DIR, "settings.html")
        end

        def self.opts
          { width: 440, height: 380, title: 'Cialona BOM — Settings' }
        end

        def self.register(dialog)
          dialog.add_action_callback('get_settings') { |*_| on_get_settings(dialog) }
          dialog.add_action_callback('save_settings') { |_ctx, b64_str| on_save_settings(dialog, b64_str) }
          dialog.add_action_callback('close_dialog') { dialog.close }
        end

        def self.on_get_settings(dialog)
          import_api_url = (Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_URL) || "").to_s
          import_api_key = (Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_KEY) || "").to_s
          catalog_api_url = (Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_URL) || "").to_s
          catalog_api_key = (Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_KEY) || "").to_s
          catalog_validate_codes = stored_catalog_validate_codes
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsLoaded", {
            import_api_url: import_api_url,
            import_api_key: import_api_key,
            catalog_api_url: catalog_api_url,
            catalog_api_key: catalog_api_key,
            catalog_validate_codes: catalog_validate_codes
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
          import_api_key = (data["import_api_key"] || data[:import_api_key] || "").to_s.strip
          catalog_api_url = (data["catalog_api_url"] || data[:catalog_api_url] || "").to_s.strip
          catalog_api_key = (data["catalog_api_key"] || data[:catalog_api_key] || "").to_s.strip
          puts "catalog_validate_codes  : #{data["catalog_validate_codes"]}"
          val = data["catalog_validate_codes"] || data[:catalog_validate_codes]
          puts "val: #{val}"
          catalog_validate_codes = val
          puts "catalog_validate_codes: #{catalog_validate_codes}"
          begin
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_URL, import_api_url)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_KEY, import_api_key)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_URL, catalog_api_url)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_KEY, catalog_api_key)
            Sketchup.write_default(PREF_NAMESPACE, PREF_KEY_CATALOG_VALIDATE_CODES, catalog_validate_codes ? "true" : "false")
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", {})
            puts "catalog_validate_codes: #{catalog_validate_codes}"
          rescue StandardError => e
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSettingsSaved", { error: true, message: e.message })
          end
        end

        def self.stored_import_api_url
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_URL).to_s
        end

        def self.stored_import_api_key
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_IMPORT_API_KEY).to_s
        end

        def self.stored_catalog_api_url
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_URL).to_s
        end

        def self.stored_catalog_api_key
          Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_API_KEY).to_s
        end

        # Default true: validate product codes against catalog API on blur.
        def self.stored_catalog_validate_codes
          v = Sketchup.read_default(PREF_NAMESPACE, PREF_KEY_CATALOG_VALIDATE_CODES)
          puts "stored_catalog_validate_codes: #{v}"
          return true if v.nil?
          v.to_s.downcase != "false"
        end
      end
    end
  end
end
