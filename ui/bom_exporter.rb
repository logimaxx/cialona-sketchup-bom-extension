# ui/bom_exporter.rb — BOM export dialog
# ------------------------------------------------------------------------------
# Dialog for running the actual BOM export. Uses BOM::Exporter for traversal and report.
# ------------------------------------------------------------------------------

module Logimaxx
  module CialonaBOMExporter
    module UI
      module BOMExporter
        DIALOG_ID = :export_bom

        def self.template_path
          File.join(UI::UI_DIR, 'bom_exporter.html')
        end

        def self.opts
          { width: 820, height: 520, title: 'Cialona BOM — Export' }
        end

        BOM_RULES_DICT = "Cialona_BOM_Rules".freeze
        MODEL_DICT = "Cialona_BOM_Exporter".freeze
        MODEL_KEY_PROJECT_ID = "project_id".freeze

        def self.register(dialog)
          dialog.add_action_callback('run_export') { |*_| on_run_export(dialog) }
          dialog.add_action_callback('save_bom_csv') { |_ctx, csv_content| on_save_bom_csv(csv_content) }
          dialog.add_action_callback('select_bom_entity') { |_ctx, entity_id| on_select_bom_entity(entity_id) }
          dialog.add_action_callback('set_exportable') { |_ctx, definition_id, exportable| on_set_exportable(dialog, definition_id, exportable) }
          dialog.add_action_callback('get_plugin_settings') { |*_| on_get_plugin_settings(dialog) }
          dialog.add_action_callback('get_initial_state') { |*_| on_get_initial_state(dialog) }
          dialog.add_action_callback('set_project_id') { |_ctx, project_id| on_set_project_id(project_id) }
          dialog.add_action_callback('check_export_allowed') { |*_| on_check_export_allowed(dialog) }
        end

        # Returns [blocked, message]. When blocked, message is the reason to show the user.
        def self.export_blocked?
          ns = Logimaxx::CialonaBOMExporter
          return [false, nil] unless ns.const_defined?(:TIME_BOMB_ENABLED) && ns::TIME_BOMB_ENABLED
          cutoff = ns.const_defined?(:TIME_BOMB_CUTOFF) ? ns::TIME_BOMB_CUTOFF : nil
          return [false, nil] unless cutoff
          return [false, nil] if Time.now <= cutoff
          date_str = cutoff.respond_to?(:strftime) ? cutoff.strftime("%Y-%m-%d") : cutoff.to_s
          [true, "BOM export has been disabled after #{date_str}. Please contact the supplier at sergiu@logmaxx.ro."]
        end

        def self.on_check_export_allowed(dialog)
          blocked, message = export_blocked?
          payload = blocked ? { allowed: false, message: message } : { allowed: true }
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onExportCheckResult", payload)
        end

        def self.on_get_initial_state(dialog)
          project_id = stored_project_id
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onInitialState", { project_id: project_id })
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
          import_api_url = Logimaxx::CialonaBOMExporter::UI::Settings.stored_import_api_url
          import_api_key = Logimaxx::CialonaBOMExporter::UI::Settings.stored_import_api_key
          Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onPluginSettings", { import_api_url: import_api_url, import_api_key: import_api_key })
        end

        def self.on_set_exportable(dialog, definition_id, exportable)
          model = Sketchup.active_model
          return unless model
          definition = model.definitions.find { |d| d.entityID.to_s == definition_id.to_s }
          return unless definition
          dict = definition.attribute_dictionary(BOM_RULES_DICT, true)
          is_exportable = (exportable == true || exportable == 1 || exportable.to_s.downcase == "true")
          dict["exportable"] = is_exportable ? "true" : "false"
          result = Logimaxx::CialonaBOMExporter::BOM::Exporter.export(model)
          payload = {
            rows: result[:rows],
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

        def self.on_run_export(dialog)
          puts "[BOM Export] on_run_export called"
          blocked, message = export_blocked?
          if blocked
            ::UI.messagebox(message) if message
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onExportResult", { error: true, message: message })
            return
          end
          model = Sketchup.active_model
          unless model
            ::UI.messagebox("No active model.")
            return
          end
          begin
            puts "[BOM Export] calling Exporter.export..."
            result = Logimaxx::CialonaBOMExporter::BOM::Exporter.export(model)
            puts "[BOM Export] export done, rows=#{result[:rows]&.size}, without_rules=#{result[:rows_without_rules]&.size}, geometry_only=#{result[:rows_geometry_only]&.size}"
            payload = {
              rows: result[:rows],
              rows_without_rules: result[:rows_without_rules] || [],
              rows_geometry_only: result[:rows_geometry_only] || [],
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
          blocked, message = export_blocked?
          if blocked
            ::UI.messagebox(message) if message
            return
          end
          return ::UI.messagebox("No content to save.") if csv_content.to_s.strip.empty?
          path = ::UI.savepanel("Save BOM as CSV", "", "bom_export.csv")
          return if path.nil? || path.empty?
          path = path + ".csv" if path.is_a?(String) && !path.end_with?(".csv")
          File.write(path, csv_content.to_s, encoding: "UTF-8")
          ::UI.messagebox("Saved to #{path}")
        end
      end
    end
  end
end
