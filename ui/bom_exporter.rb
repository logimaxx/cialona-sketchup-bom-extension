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

        def self.register(dialog)
          dialog.add_action_callback('run_export') { |*_| on_run_export(dialog) }
          dialog.add_action_callback('save_bom_csv') { |_ctx, csv_content| on_save_bom_csv(csv_content) }
          dialog.add_action_callback('select_bom_entity') { |_ctx, entity_id| on_select_bom_entity(entity_id) }
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
