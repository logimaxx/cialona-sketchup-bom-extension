# main.rb — Extension lifecycle and initialization
# ------------------------------------------------------------------------------
# Load order: this file is loaded last (see dev.rb RELOAD_FILES).
# SketchUp cannot remove a submenu or a toolbar button (no remove_item API).
# Menu and toolbar are created once per SketchUp session. Command procs call
# Commands.* at click time, so reload! picks up new code without rebuilding UI.
# The app observer is removed in cleanup and added again by init, so reload
# does not stack ModelSwitchObserver.
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
        # Skip work when the active model is unchanged (e.g. user just switched window focus).
        return if Logimaxx::CialonaBOMExporter.selection_observer_attached_to?(model)
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

    # Unique material names used by faces in the component definition (for material_area measure).
    def self.definition_material_names(definition)
      return [] unless definition.respond_to?(:entities) && definition.entities
      definition.entities.grep(Sketchup::Face).map { |f| f.material }.compact.uniq.map do |m|
        m.respond_to?(:name) ? m.name.to_s : m.to_s
      end.uniq.sort
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
      materials = definition_material_names(definition)
      exportable = (dict && dict["exportable"].to_s.downcase == "false") ? false : true
      { type: "attributes", schema_version: schema_version.to_s, bom_rules: bom_rules.to_s, materials: materials, exportable: exportable }
    end

    ROOT = __dir__

    # Reload and the debug panels follow the load location. The loader in
    # Plugins falls back to ~/work/cialona_bom_exporter; that checkout is dev
    # mode. An installed copy sits next to the loader and stays in normal mode.
    def self.dev_mode?
      return @dev_mode unless @dev_mode.nil?
      anchor = loader_directory
      anchor = (Sketchup.find_support_file("Plugins") rescue nil) if anchor.nil? || anchor.to_s.strip.empty?
      @dev_mode = anchor ? !within_directory?(anchor, ROOT) : false
    end

    def self.loader_directory
      feature = $LOADED_FEATURES.find { |loaded| File.basename(loaded) == "cialona_bom_exporter.rb" }
      feature ? File.dirname(feature) : nil
    end

    def self.within_directory?(directory, path)
      dir = normalize_load_path(directory)
      child = normalize_load_path(path)
      return false if dir.empty? || child.empty?
      return true if child.casecmp(dir).zero?
      child.downcase.start_with?("#{dir.downcase}/")
    end

    def self.normalize_load_path(path)
      File.expand_path(path.to_s).tr("\\", "/").sub(%r{/+$}, "")
    end

    # Preferabil: nu umbla la $LOAD_PATH, folosește require_relative.
    FILES = %w[
      bom/exporter
      commands
      ui
      ui/attributes
      ui/bom_exporter
    ].freeze


    FILES.each { |rel| require_relative rel }
    require_relative "dev" if dev_mode?

    # init runs on every load, including reload!. UI creation is guarded below.

    def self.init
      ensure_app_observer
      register_observers
      build_menu
      build_toolbar
    end

    # One app observer per session. cleanup drops it; the next init adds it back.
    def self.ensure_app_observer
      remove_app_observer
      @app_observer = ModelSwitchObserver.new
      Sketchup.add_observer(@app_observer)
    end

    def self.remove_app_observer
      observer = @app_observer
      @app_observer = nil
      return unless observer
      Sketchup.remove_observer(observer)
    rescue StandardError
      nil
    end

    def self.build_menu
      return if @menu

      @menu = ::UI.menu("Extensions").add_submenu(MENU_TITLE)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.reload_dev_command) if dev_mode?
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.export_bom_command)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.attributes_command)
      @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.settings_command)
      # @menu.add_item(Logimaxx::CialonaBOMExporter::Commands.to_be_implemented_command)
    end

    def self.build_toolbar
      @toolbar = ::UI.toolbar(TOOLBAR_NAME)
      # count covers a session that already added buttons before this guard existed.
      return if @toolbar_built || @toolbar.count.to_i > 0

      # SketchUp toolbars cannot be removed, only hidden. Add buttons once per session.
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.export_bom_command)
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.attributes_command)
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.settings_command)
      # @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.to_be_implemented_command)
      @toolbar.add_item(Logimaxx::CialonaBOMExporter::Commands.reload_dev_command) if dev_mode?
      @toolbar_built = true
    end

    def self.register_observers
      # Selection observer is attached only when the Attributes dialog is open (see ensure_selection_observer_for_model and Attributes on_ready / on_closed).
    end

    # Returns true if the selection observer is already attached to the given model (no need to re-attach or push).
    def self.selection_observer_attached_to?(model)
      return false unless model
      @selection_observer_model && @selection_observer_model.valid? && @selection_observer_model == model
    end

    # Removes the selection observer (e.g. when the Attributes dialog is closed). Does not remove ModelSwitchObserver.
    def self.remove_selection_observer
      if @selection_observer_model && @selection_observer_model.valid? && @selection_observer
        @selection_observer_model.selection.remove_observer(@selection_observer) rescue nil
      end
      @selection_observer_model = nil
      @selection_observer = nil
    end

    # When opening another file or switching document, observers are lost. Re-attach for the active model.
    def self.ensure_selection_observer_for_model(model)
      return unless model
      return unless dialogs[:attributes]  # Only maintain observer while Attributes dialog is open
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
      remove_app_observer
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


    MENU_TITLE = 'Cialona BOM Exporter'
    TOOLBAR_NAME = 'Cialona BOM Exporter'

  end
end

Logimaxx::CialonaBOMExporter.init
