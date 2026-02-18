# ui/attributes.rb — Attribute editor dialog (BOM schema / export config)
# ------------------------------------------------------------------------------
# Schema: schema_version, items[] with code, label, uom, measure, scope,
#        multiplier, rounding{mode, step}, params (measure-specific).
# ------------------------------------------------------------------------------

module Logimaxx
  module CialonaBOMExporter
    module UI
      module Attributes
        DIALOG_ID = :attributes
        BOM_RULES_DICT = "Cialona_BOM_Rules".freeze

        UOM_OPTIONS = %w[pcs m2 m custom].freeze
        MEASURE_OPTIONS = %w[
          count top_area total_area material_area top_perimeter
          edge_length bbox_volume bbox_dimensions
        ].freeze
        SCOPE_OPTIONS = %w[definition instance].freeze
        ROUNDING_MODES = %w[none ceil floor round].freeze

        def self.template_path
          File.join(UI::UI_DIR, 'attributes.html')
        end

        def self.opts
          { width: 720, height: 520, title: 'Cialona BOM — Attribute editor' }
        end

        def self.register(dialog)
          dialog.add_action_callback('ready') { |*_| on_ready }
          dialog.add_action_callback('test') { |*_| on_test }
          dialog.add_action_callback('save_attributes') { |_ctx, json| on_save_attributes(json) }
        end

        def self.on_ready
          ns = Logimaxx::CialonaBOMExporter
          dialog = ns.dialogs[DIALOG_ID]
          if dialog
            model = Sketchup.active_model
            entities = model ? model.selection.to_a : []
            payload = ns.build_attributes_selection_payload(entities)
            Logimaxx::CialonaBOMExporter::UI.inject_json(dialog, "onSketchUpSelection", payload)
          end
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

          category = last_ruleset_category(bom_rules)
          if category && category.to_s.strip != ""
            tag = model.layers[category] || model.layers.add(category)
            entity.layer = tag
          end
          ::UI.messagebox("Attributes saved.")
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
