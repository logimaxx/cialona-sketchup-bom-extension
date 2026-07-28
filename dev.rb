# dev.rb — Reload logic and file list for DEV mode

module Logimaxx
  module CialonaBOMExporter
    # Ordered list for reload. Main is last so menu/toolbar are built after
    # Commands and UI are defined. Do not include the loader (it stays loaded).
    # Must match FILES in main.rb so all required code is re-executed on reload.
    RELOAD_FILES = %w[
      bom/exporter.rb
      commands.rb
      ui.rb
      ui/attributes.rb
      ui/bom_exporter.rb
      ui/settings.rb
      catalog/provider.rb
      catalog/csv_provider.rb
      dev.rb
      main.rb
    ].freeze

    def self.reload!
      # 1. Cleanup: avoid duplicate menus, toolbars, observers, and orphan dialogs.
      cleanup
      # 2. Clear our files from $LOADED_FEATURES so load() re-executes them.
      root = ROOT
      RELOAD_FILES.each do |rel|
        full = File.join(root, rel)
        $LOADED_FEATURES.delete(full)
        $LOADED_FEATURES.delete(File.expand_path(full))
      end
      # 3. Re-load in order. Suppress "already initialized constant" warnings during reload.
      old_verbose = $VERBOSE
      $VERBOSE = nil
      begin
        RELOAD_FILES.each do |rel|
          path = File.join(root, rel)
          load path if File.exist?(path)
        end
        puts '[Cialona BOM Exporter] Reloaded.'
      ensure
        $VERBOSE = old_verbose
      end
      nil
    end
  end
end
