require "sketchup.rb"
require "extensions.rb"

module Logimaxx
  module CialonaBOMExporter
    EXT_NAME = "Cialona BOM Exporter"

    # SketchUp loads only this file from the Plugins folder. The sources live in
    # a sibling folder with the same basename:
    #   cialona_bom_exporter.rb
    #   cialona_bom_exporter/main.rb
    # A copy of this loader in Plugins (dev) falls back to ~/work/cialona_bom_exporter
    # when that sibling folder is not installed beside it.
    def self.main_script
      candidates = [
        File.join(__dir__, "cialona_bom_exporter", "main.rb"),
        File.join(__dir__, "main.rb")
      ]
      home = ENV["HOME"]
      home = ENV["USERPROFILE"] if home.nil? || home.empty?
      if home && !home.empty?
        dev_root = File.join(home, "work", "cialona_bom_exporter")
        candidates << File.join(dev_root, "cialona_bom_exporter", "main.rb")
        candidates << File.join(dev_root, "main.rb")
      end
      candidates.find { |path| File.exist?(path) }
    end

    MAIN = main_script

    unless MAIN
      puts "[#{EXT_NAME}] main.rb not found next to the loader or in ~/work/cialona_bom_exporter"
    else
      ex = SketchupExtension.new(EXT_NAME, MAIN)
      ex.description = "BOM Exporter to FileMaker for CIALONA NL"
      ex.version     = "0.1.0"
      ex.creator     = "Logimaxx"
      Sketchup.register_extension(ex, true)
    end
  end
end
