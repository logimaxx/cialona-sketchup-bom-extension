# main.rb — Extension lifecycle and initialization
# ------------------------------------------------------------------------------
# Load order: this file is loaded last (see dev.rb RELOAD_FILES). SketchUp
# pitfall: add_submenu adds a new item every time; we remove the old submenu
# in cleanup so reload! doesn't duplicate "Cialona BOM Exporter" under Extensions.
# ------------------------------------------------------------------------------

module Logimaxx
  module CialonaBOMExporter
    # When the user opens another file or switches document, re-attach selection observer to the new model.
    class ModelSwitchObserver < Sketchup::AppObserver
      def onNewModel(model)
        Logimaxx::CialonaBOMExporter.ensure_selection_observer_for_model(model)
      end

      def onOpenModel(model)
        Logimaxx::CialonaBOMExporter.ensure_selection_observer_for_model(model)
      end

      def onActivateModel(model)
        Logimaxx::CialonaBOMExporter.ensure_selection_observer_for_model(model)
      end
    end

    # Sends a standardized payload to the Attributes HTML dialog when selection changes.
    # Payload types:
    #   - error: none_selected | multiple_selected | not_a_component (single selection is not a component instance)
    #   - attributes: when exactly one ComponentInstance (not Group/Face/Edge/…) is selected
    class SelectionToAttributesObserver < Sketchup::SelectionObserver
      def onSelectionBulkChange(selection)
        push_selection_to_ui(selection.to_a)
      end

      # Called when the selection is cleared (e.g. click on empty space). onSelectionBulkChange
      # is not always called for that case, so we handle it explicitly.
      def onSelectionCleared(selection)
        push_selection_to_ui([])
      end

      private

      def push_selection_to_ui(entities)
        ns = Logimaxx::CialonaBOMExporter
        dialog = ns.dialogs[:attributes]
        return unless dialog

        payload = ns.build_attributes_selection_payload(entities)
        UI.inject_json(dialog, "onSketchUpSelection", payload)
      end
    end

    # Shared payload builder so the attributes dialog can show current selection on open.
    BOM_RULES_DICT = "Cialona_BOM_Rules".freeze
    DEFAULT_SCHEMA_VERSION = "1.0".freeze
    DEFAULT_BOM_RULES_JSON = "[]".freeze

    def self.build_attributes_selection_payload(entities)
      case entities.size
      when 0
        { type: "error", reason: "none_selected" }
      when 1
        entity = entities.first
        if component_instance?(entity)
          build_attributes_payload_for_entity(entity)
        else
          { type: "error", reason: "not_a_component" }
        end
      else
        { type: "error", reason: "multiple_selected" }
      end
    end

    def self.component_instance?(entity)
      return false unless entity.is_a?(Sketchup::ComponentInstance)
      return false if entity.definition.nil?
      !entity.definition.group?
    end

    def self.build_attributes_payload_for_entity(entity)
      definition = entity.definition
      dict = definition.respond_to?(:attribute_dictionaries) && definition.attribute_dictionaries &&
             definition.attribute_dictionary(BOM_RULES_DICT)
      schema_version = (dict && dict["schema_version"]) ? dict["schema_version"].to_s : DEFAULT_SCHEMA_VERSION
      bom_rules_raw = (dict && dict["bom_rules"]) ? dict["bom_rules"] : nil
      bom_rules = case bom_rules_raw
                  when String then bom_rules_raw
                  when nil then DEFAULT_BOM_RULES_JSON
                  else bom_rules_raw.to_s
                  end
      bom_rules = DEFAULT_BOM_RULES_JSON if bom_rules.to_s.strip.empty?
      { type: "attributes", schema_version: schema_version.to_s, bom_rules: bom_rules.to_s }
    end

    ROOT = __dir__
    # DEV_MODE = File.exist?(File.join(ROOT, "DEV"))

    # Preferabil: nu umbla la $LOAD_PATH, folosește require_relative.
    FILES = %w[
      bom/exporter
      commands
      ui
      ui/attributes
      ui/bom_exporter
      catalog/provider
      catalog/csv_provider
    ].freeze


    FILES.each { |rel| require_relative rel }
    require_relative "dev" if File.exist?(File.join(ROOT, "DEV"))

    # init (o singură dată)
   

  

    def self.init
      Sketchup.add_observer(ModelSwitchObserver.new)
      register_observers
      return if defined?(@initialized) && @initialized
      @initialized = true
      build_menu
      build_toolbar
    end

    def self.build_menu
      title = "#{MENU_TITLE} #{Time.now.strftime('%H:%M:%S')}"
      @menu = ::UI.menu.add_submenu(title)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.reload_dev_command)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.export_bom_command)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.attributes_command)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.to_be_implemented_command)
    end

    def self.build_toolbar
      name = TOOLBAR_NAME
      @toolbar = ::UI.toolbar(name)
      # SketchUp toolbars cannot be removed, only hidden. Only add items when empty (e.g. first load).
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.export_bom_command)
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.attributes_command)
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.to_be_implemented_command)
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.reload_dev_command)
    end

    def self.register_observers
      ensure_selection_observer_for_model(Sketchup.active_model)
    end

    # When opening another file or switching document, observers are lost. Re-attach for the active model.
    def self.ensure_selection_observer_for_model(model)
      return unless model
      if @selection_observer_model && @selection_observer_model.valid? && @selection_observer_model == model
        return # already attached to this model
      end
      if @selection_observer_model && @selection_observer_model.valid? && @selection_observer
        @selection_observer_model.selection.remove_observer(@selection_observer) rescue nil
      end
      @selection_observer_model = model
      @selection_observer = SelectionToAttributesObserver.new
      model.selection.add_observer(@selection_observer)
      # Push current selection so UI updates for the new model
      payload = build_attributes_selection_payload(model.selection.to_a)
      dialog = dialogs[:attributes]
      UI.inject_json(dialog, "onSketchUpSelection", payload) if dialog
    end

    def self.cleanup
      close_dialogs
      remove_observers
    end

    def self.dialogs
      @dialogs ||= {}
    end

    def self.close_dialog(id)
      d = dialogs[id]
      d&.close
      dialogs.delete(id)
    end

    def self.close_dialogs
      dialogs.each_value { |d| d.close rescue nil }
      dialogs.clear
    end

    def self.remove_observers
      if @selection_observer_model && @selection_observer_model.valid? && @selection_observer
        @selection_observer_model.selection.remove_observer(@selection_observer) rescue nil
      end
      @selection_observer_model = nil
      @selection_observer = nil
      model = Sketchup.active_model
      if model && defined?(@observers) && @observers
        @observers.each { |obs| model.remove_observer(obs) rescue nil }
      end
      @observers = []
    end


    def self.menu
      @menu
    end

    def self.toolbar
      @toolbar
    end


    def self.catalog_provider
      @catalog_provider ||= Catalog::CsvProvider.new(File.join(ROOT, 'schema', 'catalog.csv'))
    end

    MENU_TITLE = 'Cialona BOM Exporter'
    TOOLBAR_NAME = 'Cialona BOM Exporter'

    unless defined?(@initialized) && @initialized
      @initialized = true
      build_menu
      build_toolbar
    end
  end
end

Logimaxx::CialonaBOMExporter.init
