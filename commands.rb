# commands.rb — UI::Command definitions and menu actions
# ------------------------------------------------------------------------------
# SketchUp pitfall: UI::Command is id-based; redefining the same command on
# reload is fine. Menu items reference commands by name; after cleanup we
# remove the menu and re-add it, so we always use the latest command defs.
# Toolbar pitfall: the toolbar cannot be removed, only hidden, so after reload
# the toolbar still holds the OLD Command. Use indirection: the block must
# resolve the method at click time (via full constant path) so the latest code runs.
# ------------------------------------------------------------------------------

module Logimaxx
  module CialonaBOMExporter
    module Commands

      def self.reload_dev
        return unless File.exist?(File.join(Logimaxx::CialonaBOMExporter::ROOT, "DEV"))
        Logimaxx::CialonaBOMExporter.reload!
        ::UI.messagebox("Reload completed.")
      end

      def self.export_bom
        Logimaxx::CialonaBOMExporter::UI.show(:export_bom)
      end

      def self.attributes
        Logimaxx::CialonaBOMExporter::UI.show(:attributes)
      end

      def self.settings
        Logimaxx::CialonaBOMExporter::UI.show(:settings)
      end

      def self.to_be_implemented
        ::UI.messagebox("To be implemented 1")
      end

      def self.reload_dev_command
        cmd = ::UI::Command.new("Reload (Dev)") do
          Logimaxx::CialonaBOMExporter::Commands.reload_dev
        end
        cmd.tooltip = 'Reload extension (dev only)'
        cmd.small_icon = File.join(ROOT, "icons","reload.png")
        cmd.large_icon = File.join(ROOT, "icons","reload.png")
        cmd.menu_text = "Reload (Dev)"
        cmd
      end

      def self.export_bom_command
        cmd = ::UI::Command.new('Export BOM') do
          Logimaxx::CialonaBOMExporter::Commands.export_bom
        end
        cmd.tooltip = 'Export Bill of Materials'
        cmd.small_icon = File.join(ROOT, "icons","export.png")
        cmd.large_icon = File.join(ROOT, "icons","export.png")
        cmd.menu_text = "Export BOM"
        # Omit small_icon/large_icon unless you have paths; SketchUp does not accept nil.
        cmd
      end


      def self.attributes_command
        cmd = ::UI::Command.new('Attributes') do
          Logimaxx::CialonaBOMExporter::Commands.attributes
        end
        cmd.tooltip = 'Edit attributes'
        cmd.small_icon = File.join(ROOT, "icons","attributes.png")
        cmd.large_icon = File.join(ROOT, "icons","attributes.png")
        cmd.menu_text = "Attributes"
        cmd
      end

      def self.settings_command
        cmd = ::UI::Command.new('Settings') do
          Logimaxx::CialonaBOMExporter::Commands.settings
        end
        cmd.tooltip = 'Plugin settings (API URL, etc.)'
        cmd.small_icon = File.join(ROOT, "icons", "setting.png")
        cmd.large_icon = File.join(ROOT, "icons", "setting.png")
        cmd.menu_text = "Settings"
        cmd
      end

      def self.to_be_implemented_command
        cmd = ::UI::Command.new('Undefined') do
          Logimaxx::CialonaBOMExporter::Commands.to_be_implemented
        end
        cmd.tooltip = 'Undefined'
        cmd.small_icon = File.join(ROOT, "icons","question.png")
        cmd.large_icon = File.join(ROOT, "icons","question.png")
        cmd.menu_text = "To be implemented 1"
        cmd
      end

      
    end
  end
end


