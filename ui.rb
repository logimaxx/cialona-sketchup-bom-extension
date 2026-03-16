# ui.rb — Multi-dialog UI: orchestration and lifecycle
# ------------------------------------------------------------------------------
# Each dialog lives in its own module under UI (e.g. UI::Attributes, UI::BOMExporter).
# Each module defines template_path, opts, register(dialog).
# Show with UI.show(:attributes) or UI.show(:bom_exporter).
# ------------------------------------------------------------------------------

module Logimaxx
  module CialonaBOMExporter
    module UI
      UI_DIR = File.join(__dir__, 'ui')

      require_relative 'ui/attributes'
      require_relative 'ui/bom_exporter'
      require_relative 'ui/settings'

      DIALOG_MODULES = {
        attributes: Attributes,
        export_bom: BOMExporter,
        settings: Settings
      }.freeze

      def self.show(dialog_id)
        dialog_id = dialog_id.to_sym
        mod = DIALOG_MODULES[dialog_id]
        raise ArgumentError, "Unknown dialog: #{dialog_id.inspect}" unless mod

        ns = Logimaxx::CialonaBOMExporter
        ns.close_dialog(dialog_id)

        path = File.join(mod.template_path)

        opts = mod.opts.merge(resizable: true)

        dialog = ::UI::HtmlDialog.new(opts)
        dialog.set_file(path)
        mod.register(dialog)
        dialog.show
        dialog.center unless opts[:preferences_key]

        ns.dialogs[dialog_id] = dialog
      end

      # Inject JSON via Base64 into the dialog: runs JS that calls window[js_callback_name](data).
      # Callers (so you can find who triggers which callback):
      #   onSettingsLoaded  -> ui/settings.rb (on_get_settings)
      #   onSettingsSaved   -> ui/settings.rb (on_save_settings)
      #   onCatalogSettings -> ui/attributes.rb (on_get_catalog_settings)
      #   onSketchUpSelection -> main.rb, ui/attributes.rb
      #   onExportCheckResult, onInitialState, onPluginSettings, onExportResult -> ui/bom_exporter.rb
      def self.inject_json(dialog, js_callback_name, data)
        require "base64"
        json = data.to_json
        b64 = Base64.strict_encode64(json)
        # Base64 uses only A-Za-z0-9+/= so safe inside single-quoted JS string
        script = "(function(){try{var d=JSON.parse(atob('#{b64}'));if(window.#{js_callback_name})window.#{js_callback_name}(d);}catch(e){console.error('inject_json:',e.message||e,e.stack||'');}})();"
        dialog.execute_script(script)
      end
    end
  end
end
