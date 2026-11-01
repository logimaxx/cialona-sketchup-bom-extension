# ui/attributes.rb — Attribute editor dialog
# ------------------------------------------------------------------------------
# Saved on the component definition as schema_version and bom_rules:
# code, label, uom, measure, category, rounding{mode, step}, params.material.
# ------------------------------------------------------------------------------
module Logimaxx
  module CialonaBOMExporter
    module UI
      module Attributes
        DIALOG_ID = :attributes
        BOM_RULES_DICT = "Cialona_BOM_Rules".freeze
        UOM_OPTIONS = %w[pcs m2 mtr m3 custom].freeze
        MEASURE_OPTIONS = %w[
          count top_area bottom_area total_area material_area
          top_perimeter bottom_perimeter edge_length smart_length
          bbox_volume bbox_dimensions
        ].freeze
        ROUNDING_MODES = %w[none ceil floor round].freeze

        def self.template_path
          File.join(UI::UI_DIR, 'attributes.html')
        end

        # Unique key so SketchUp saves/restores position and size in the tray.
        PREFERENCES_KEY = "Logimaxx_CialonaBOMExporter_Attributes".freeze

        # Show this dialog in the right-side inspector tray (Windows Tray) instead of a floating window.
        USE_INSPECTOR = false

        def self.opts
          {
            width: 720,
            height: 520,
            title: 'Cialona BOM — Attribute editor',
            preferences_key: PREFERENCES_KEY,
            style: ::UI::HtmlDialog::STYLE_DIALOG  # Required for Tray / show_inspector
          }
        end

        def self.register(dialog)
          dialog.add_action_callback('ready') { |*_| on_ready }
          dialog.add_action_callback('test') { |*_| on_test }
          dialog.add_action_callback('save_attributes') { |_ctx, json| on_save_attributes(json) }
          dialog.add_action_callback('get_catalog_settings') { |*_| on_get_catalog_settings(dialog) }
          if dialog.respond_to?(:set_on_closed)
            dialog.set_on_closed { on_closed }
          end
        end

        def self.on_get_catalog_settings(dialog)
          settings = Logimaxx::CialonaBOMExporter::UI::Settings
          catalog_source = settings.stored_catalog_source
          payload = {
            catalog_api_url: settings.stored_catalog_api_url,
            catalog_api_key: settings.stored_catalog_api_key,
            catalog_api_profile: settings.stored_catalog_api_profile,
            catalog_validate_codes: settings.stored_catalog_validate_codes,
            free_edit_mode: settings.stored_free_edit_mode,
            catalog_source: catalog_source,
            unit_map: settings.stored_unit_map,
            dev_mode: Logimaxx::CialonaBOMExporter.dev_mode?,
            csv_items: [],
            csv_loaded: false,
            csv_error: nil
          }

          if catalog_source == "csv"
            csv_status = load_catalog_csv
            payload[:csv_items] = csv_status[:items]
            payload[:csv_loaded] = csv_status[:loaded]
            payload[:csv_error] = csv_status[:error]
            payload[:csv_path] = csv_status[:path]
          end

          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onCatalogSettings", payload)
        end

        # Returns { items:, loaded:, error:, path: } for the catalog CSV chosen in settings.
        def self.load_catalog_csv
          settings = Logimaxx::CialonaBOMExporter::UI::Settings
          path = settings.resolved_catalog_csv_path
          fields = settings.stored_catalog_csv_fields
          if path.empty?
            return { items: [], loaded: false, error: "unset", path: path }
          end
          unless File.file?(path)
            return { items: [], loaded: false, error: "missing", path: path }
          end
          if fields["code"].to_s.strip.empty?
            return { items: [], loaded: false, error: "unmapped", path: path }
          end

          begin
            items = []
            raw = File.read(path)
            raw = raw.sub(/\A\xEF\xBB\xBF/, "") # strip UTF-8 BOM if present
            rows = parse_csv(raw)
            header_indexes = {}
            (rows.shift || []).each_with_index do |header, index|
              name = header.to_s.strip
              next if name.empty? || header_indexes.key?(name)
              header_indexes[name] = index
            end
            code_column = fields["code"].to_s
            rows.each do |row|
              code = csv_value(row, header_indexes, code_column).strip
              next if code.empty?
              items << {
                code: code,
                name: csv_value(row, header_indexes, fields["name"].to_s).strip,
                unit: csv_value(row, header_indexes, fields["unit"].to_s).strip,
                category: csv_value(row, header_indexes, fields["category"].to_s).strip
              }
            end
            if items.empty?
              { items: [], loaded: false, error: "empty", path: path }
            else
              { items: items, loaded: true, error: nil, path: path }
            end
          rescue StandardError => e
            puts "[CialonaBOM] catalog CSV load failed: #{e.message}"
            { items: [], loaded: false, error: "invalid", path: path }
          end
        end

        # SketchUp's Ruby can accidentally activate native gems from the user's
        # GEM_PATH. Requiring Ruby's csv library also requires the native date
        # extension, so keep catalog parsing self-contained. This handles the CSV
        # features used by the catalog: quoted fields, doubled quotes, commas and
        # newlines inside quoted fields, and CRLF/LF line endings.
        def self.parse_csv(text)
          rows = []
          row = []
          field = +""
          quoted = false
          index = 0

          while index < text.length
            char = text[index]
            if quoted
              if char == '"'
                if text[index + 1] == '"'
                  field << '"'
                  index += 1
                else
                  quoted = false
                end
              else
                field << char
              end
            else
              case char
              when '"'
                raise ArgumentError, "unexpected quote in CSV field" unless field.empty?
                quoted = true
              when ','
                row << field
                field = +""
              when "\n"
                row << field
                rows << row unless row.length == 1 && row[0].empty?
                row = []
                field = +""
              when "\r"
                # Ignore CR; LF completes a Windows line ending.
              else
                field << char
              end
            end
            index += 1
          end

          raise ArgumentError, "unterminated quoted CSV field" if quoted
          unless row.empty? && field.empty?
            row << field
            rows << row
          end
          rows
        end

        def self.csv_value(row, header_indexes, name)
          index = header_indexes[name]
          index.nil? ? "" : row[index].to_s
        end

        def self.on_ready
          ns = Logimaxx::CialonaBOMExporter
          # Attach selection observer only while this dialog is open; it pushes current selection.
          ns.ensure_selection_observer_for_model(Sketchup.active_model)
        end

        def self.on_closed
          ns = Logimaxx::CialonaBOMExporter
          ns.remove_selection_observer
          ns.dialogs.delete(DIALOG_ID)
        end

        def self.on_test
          ::UI.messagebox("Test button clicked")
        end

        def self.on_save_attributes(json)
          return ::UI.messagebox("No data to save.") if json.nil? || json.to_s.strip.empty?
          payload = JSON.parse(json)
          schema_version = (payload["schema_version"] || "1.0").to_s
          bom_rules = payload["bom_rules"]
          bom_rules = bom_rules.is_a?(String) ? bom_rules : JSON.generate(bom_rules)
          exportable = (payload["exportable"] == true || payload["exportable"].to_s.downcase == "true")

          model = Sketchup.active_model
          return ::UI.messagebox("No active model.") unless model
          selection = model.selection.to_a
          return ::UI.messagebox("Select a single component to save attributes.") unless selection.size == 1

          entity = selection.first
          unless entity.is_a?(Sketchup::ComponentInstance) && entity.definition && !entity.definition.group?
            return ::UI.messagebox("Selection must be a component instance (not a group, face, or edge).")
          end

          definition = entity.definition
          dict = definition.attribute_dictionary(BOM_RULES_DICT, true)
          dict["schema_version"] = schema_version
          dict["bom_rules"] = bom_rules
          dict["exportable"] = exportable ? "true" : "false"

          category = last_ruleset_category(bom_rules)
          if category && category.to_s.strip != ""
            tag = model.layers[category] || model.layers.add(category)
            entity.layer = tag
          end
          # ::UI.messagebox("Attributes saved.")
        end

        def self.last_ruleset_category(bom_rules_json)
          return nil if bom_rules_json.to_s.strip.empty?
          rules = JSON.parse(bom_rules_json)
          return nil unless rules.is_a?(Array) && rules.any?
          last_rule = rules.last
          last_rule.is_a?(Hash) ? last_rule["category"] : nil
        end
      end
    end
  end
end
