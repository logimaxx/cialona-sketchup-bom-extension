# ui/bom_exporter.rb — BOM export dialog
# ------------------------------------------------------------------------------
# Dialog for running the actual BOM export. Uses BOM::Exporter for traversal and report.
# ------------------------------------------------------------------------------

require "json"

module Logimaxx
  module CialonaBOMExporter
    module UI
      module BOMExporter
        DIALOG_ID = :export_bom

        def self.template_path
          File.join(UI::UI_DIR, 'bom_exporter.html')
        end

        def self.opts
          { width: 920, height: 520, title: 'Cialona BOM — Export' }
        end

        BOM_RULES_DICT = "Cialona_BOM_Rules".freeze
        MODEL_DICT = "Cialona_BOM_Exporter".freeze
        MODEL_KEY_PROJECT_ID = "project_id".freeze

        def self.register(dialog)
          dialog.add_action_callback('run_export') { |_ctx, export_type| on_run_export(dialog, export_type) }
          dialog.add_action_callback('save_bom_csv') { |_ctx, csv_content| on_save_bom_csv(csv_content) }
          dialog.add_action_callback('save_piece_csv') { |_ctx, csv_content| on_save_piece_csv(csv_content) }
          dialog.add_action_callback('select_bom_entity') { |_ctx, entity_id| on_select_bom_entity(entity_id) }
          dialog.add_action_callback('set_exportable') { |_ctx, definition_id, exportable| on_set_exportable(dialog, definition_id, exportable) }
          dialog.add_action_callback('set_exportable_bulk') { |_ctx, definition_ids_json, exportable| on_set_exportable_bulk(dialog, definition_ids_json, exportable) }
          dialog.add_action_callback('get_plugin_settings') { |*_| on_get_plugin_settings(dialog) }
          dialog.add_action_callback('get_initial_state') { |*_| on_get_initial_state(dialog) }
          dialog.add_action_callback('set_project_id') { |_ctx, project_id| on_set_project_id(project_id) }
        end

        def self.on_get_initial_state(dialog)
          project_id = stored_project_id
          free_edit_mode = Logimaxx::CialonaBOMExporter::UI::Settings.stored_free_edit_mode
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onInitialState", {
            project_id: project_id,
            free_edit_mode: free_edit_mode,
            unit_map: Logimaxx::CialonaBOMExporter::UI::Settings.stored_unit_map,
            dev_mode: Logimaxx::CialonaBOMExporter.dev_mode?
          })
        end

        def self.on_set_project_id(project_id)
          model = Sketchup.active_model
          return unless model
          dict = model.attribute_dictionary(MODEL_DICT, true)
          dict[MODEL_KEY_PROJECT_ID] = project_id.to_s
        end

        # Read project ID from the active model's attributes (per-model persistence).
        def self.stored_project_id
          model = Sketchup.active_model
          return "" unless model
          dict = model.attribute_dictionary(MODEL_DICT, false)
          return "" unless dict
          (dict[MODEL_KEY_PROJECT_ID] || "").to_s
        end

        def self.on_get_plugin_settings(dialog)
          settings = Logimaxx::CialonaBOMExporter::UI::Settings
          free_edit_mode = settings.stored_free_edit_mode
          # Withhold connection details so browser-side code cannot call the API in free-edit mode.
          import_api_url = free_edit_mode ? "" : settings.stored_import_api_url
          offer_lines_api_url = free_edit_mode ? "" : settings.stored_offer_lines_api_url
          import_api_key = free_edit_mode ? "" : settings.stored_import_api_key
          import_api_profile = settings.stored_import_api_profile
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onPluginSettings", {
            import_api_url: import_api_url,
            offer_lines_api_url: offer_lines_api_url,
            import_api_key: import_api_key,
            free_edit_mode: free_edit_mode,
            import_api_profile: import_api_profile,
            unit_map: settings.stored_unit_map
          })
        end

        def self.on_set_exportable(dialog, definition_id, exportable)
          model = Sketchup.active_model
          return unless model
          definition = model.definitions.find { |d| d.entityID.to_s == definition_id.to_s }
          return unless definition
          dict = definition.attribute_dictionary(BOM_RULES_DICT, true)
          is_exportable = (exportable == true || exportable == 1 || exportable.to_s.downcase == "true")
          dict["exportable"] = is_exportable ? "true" : "false"
          refresh_quantity_report(dialog, model)
        end

        def self.on_set_exportable_bulk(dialog, definition_ids_json, exportable)
          model = Sketchup.active_model
          return unless model
          ids = JSON.parse(definition_ids_json.to_s)
          return unless ids.is_a?(Array)

          is_exportable = (exportable == true || exportable == 1 || exportable.to_s.downcase == "true")
          val = is_exportable ? "true" : "false"
          ids.each do |definition_id|
            definition = model.definitions.find { |d| d.entityID.to_s == definition_id.to_s }
            next unless definition
            dict = definition.attribute_dictionary(BOM_RULES_DICT, true)
            dict["exportable"] = val
          end
          refresh_quantity_report(dialog, model)
        end

        # Quantity rows only. The piece list comes from its own scan, and this
        # payload leaves piece_rows out so the dialog keeps the rows it has.
        def self.refresh_quantity_report(dialog, model)
          result = Logimaxx::CialonaBOMExporter::BOM::Exporter.export(model)
          payload = {
            rows: result[:rows] || [],
            rows_without_rules: result[:rows_without_rules] || [],
            rows_geometry_only: result[:rows_geometry_only] || [],
            model_length_unit: result[:model_length_unit] || "in"
          }
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onExportResult", payload)
        end

        def self.on_select_bom_entity(entity_id)
          model = Sketchup.active_model
          return unless model
          entity = Logimaxx::CialonaBOMExporter::BOM::Exporter.find_entity_by_id(model, entity_id)
          return unless entity
          model.selection.clear
          model.selection.add(entity)
          model.active_view.zoom(model.selection) if model.active_view.respond_to?(:zoom)
        end

        def self.on_run_export(dialog, export_type = "quantities")
          puts "[BOM Export] on_run_export called"
          model = Sketchup.active_model
          unless model
            ::UI.messagebox("No active model.")
            return
          end
          begin
            puts "[BOM Export] calling Exporter.export..."
            pieces_mode = export_type.to_s == "pieces"
            result = if pieces_mode
                       Logimaxx::CialonaBOMExporter::BOM::Exporter.export_pieces(model)
                     else
                       Logimaxx::CialonaBOMExporter::BOM::Exporter.export(model)
                     end
            puts "[BOM Export] export done, rows=#{result[:rows]&.size}, without_rules=#{result[:rows_without_rules]&.size}, geometry_only=#{result[:rows_geometry_only]&.size}"
            payload = {
              export_type: pieces_mode ? "pieces" : "quantities",
              rows: result[:rows] || [],
              rows_without_rules: result[:rows_without_rules] || [],
              rows_geometry_only: result[:rows_geometry_only] || [],
              piece_rows: result[:piece_rows] || [],
              piece_length_unit: result[:piece_length_unit] || "in",
              model_length_unit: result[:model_length_unit] || "in"
            }
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onExportResult", payload)
            puts "[BOM Export] inject_json done"
          rescue StandardError => e
            puts "[BOM Export] ERROR: #{e.message}"
            puts e.backtrace.first(5).join("\n")
            ::UI.messagebox("BOM export error: #{e.message}")
            payload = { error: true, message: e.message }
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onExportResult", payload)
          end
        end

        def self.on_save_bom_csv(csv_content)
          return ::UI.messagebox("No content to save.") if csv_content.to_s.strip.empty?
          path = ::UI.savepanel("Save BOM as CSV", "", "bom_export.csv")
          return if path.nil? || path.empty?
          path = path + ".csv" if path.is_a?(String) && !path.end_with?(".csv")
          File.write(path, csv_content.to_s, encoding: "UTF-8")
          ::UI.messagebox("Saved to #{path}")
        end

        def self.on_save_piece_csv(csv_content)
          return ::UI.messagebox("No piece data to save.") if csv_content.to_s.strip.empty?
          path = ::UI.savepanel("Save detailed piece list as CSV", "", "piece_export.csv")
          return if path.nil? || path.empty?
          path = path + ".csv" if path.is_a?(String) && !path.end_with?(".csv")
          File.write(path, csv_content.to_s, encoding: "UTF-8")
          ::UI.messagebox("Saved to #{path}")
        end
      end
    end
  end
end
