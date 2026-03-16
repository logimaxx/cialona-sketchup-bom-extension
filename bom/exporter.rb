# bom/exporter.rb — BOM export: traverse model, collect components, compute quantities from bom_rules
# ----------------------------------------------------------------------------------------------
# Traversal: recurse into Groups, stop at ComponentInstance (do not recurse into component definitions).
# Report: one row per (definition, rule) with quantity computed from the rule's measure type.
#
# Units: SketchUp's API returns lengths in INCHES internally (areas in in², volumes in in³).
# Quantities are converted to the model's length unit (Window > Model Info > Units) so that
# area measures are in (model length)² and volume in (model length)³.
# ----------------------------------------------------------------------------------------------

module Logimaxx
  module CialonaBOMExporter
    module BOM
      class Exporter
        BOM_RULES_DICT = "Cialona_BOM_Rules".freeze
        DEFAULT_BOM_RULES_JSON = "[]".freeze

        # Model length unit codes (OptionsManager UnitsOptions LengthUnit)
        LENGTH_UNIT_INCHES = 0
        LENGTH_UNIT_FEET = 1
        LENGTH_UNIT_MILLIMETER = 2
        LENGTH_UNIT_CENTIMETER = 3
        LENGTH_UNIT_METER = 4

        # Set to true to log top_area details to Ruby Console (Window > Ruby Console).
        DEBUG_TOP_AREA = true

        attr_reader :model

        def initialize(model)
          @model = model
        end

        # Traverse model iteratively: open groups, collect component instances and all groups.
        # Uses a stack and a visited set to avoid infinite loops from any cyclic or corrupted hierarchy.
        MAX_TRAVERSAL_DEPTH = 500
        MAX_INSTANCES = 500_000

        # Returns [instances, groups]: component instances (excluding group definitions) and all groups seen.
        def collect_component_instances_and_groups(entities = nil)
          entities = entities || model.entities
          out_instances = []
          out_groups = []
          visited = {}
          stack = [[entities, 0]]
          while stack.any?
            ents, depth = stack.pop
            next if depth > MAX_TRAVERSAL_DEPTH
            id = ents.object_id
            next if visited[id]
            visited[id] = true
            next unless ents.respond_to?(:each)
            ents.each do |e|
              case e
              when Sketchup::Group
                next unless e.respond_to?(:entities)
                out_groups << e
                child = e.entities
                stack << [child, depth + 1] if child && !visited[child.object_id]
              when Sketchup::ComponentInstance
                next if e.definition.nil?
                next if e.definition.group?
                out_instances << e
                return [out_instances, out_groups] if out_instances.size >= MAX_INSTANCES
              else
                # Face, Edge, etc. — skip
              end
            end
          end
          [out_instances, out_groups]
        end

        def collect_component_instances(entities = nil)
          collect_component_instances_and_groups(entities).first
        end

        # Groups that contain at least one of the given component instances (ancestor chain).
        def group_ids_containing_instances(instances)
          ids = {}
          instances.each do |inst|
            owner = inst.respond_to?(:parent) && inst.parent && inst.parent.respond_to?(:parent) ? inst.parent.parent : nil
            while owner
              ids[owner.object_id] = true if owner.is_a?(Sketchup::Group)
              owner = owner.respond_to?(:parent) && owner.parent && owner.parent.respond_to?(:parent) ? owner.parent.parent : nil
            end
          end
          ids
        end

        # Groups that contain no component instance (only geometry and possibly nested geometry-only groups).
        def geometry_only_groups(all_groups, instances)
          containing_ids = group_ids_containing_instances(instances)
          all_groups.reject { |g| containing_ids[g.object_id] }
        end

        # Group instances by their definition. Returns Hash: definition => [instance, ...]
        def group_by_definition(instances)
          instances.group_by(&:definition)
        end

        # Load bom_rules (array of rule hashes) from a component definition. Returns [] if none.
        def bom_rules_for_definition(definition)
          dict = definition.respond_to?(:attribute_dictionaries) && definition.attribute_dictionaries &&
                 definition.attribute_dictionary(BOM_RULES_DICT)
          return [] unless dict
          raw = dict["bom_rules"]
          return [] if raw.to_s.strip.empty?
          rules = JSON.parse(raw.to_s)
          rules.is_a?(Array) ? rules : []
        end

        # True unless dict["exportable"] == "false". Default is exportable.
        def exportable_for_definition(definition)
          dict = definition.respond_to?(:attribute_dictionaries) && definition.attribute_dictionaries &&
                 definition.attribute_dictionary(BOM_RULES_DICT)
          return true unless dict
          dict["exportable"].to_s.downcase != "false"
        end

        # Build report: { rows: [...], rows_without_rules: [...], rows_geometry_only: [...] }.
        # rows = components that have bom_rules (one row per rule).
        # rows_without_rules = components with no bom_rules, one row per definition, count only.
        # rows_geometry_only = groups that contain no component instances (geometry only), one row per group.
        def build_report(instances_by_definition = nil)
          instances, all_groups = collect_component_instances_and_groups
          instances_by_definition ||= group_by_definition(instances)
          rows = []
          rows_without_rules = []
          instances_by_definition.each do |definition, insts|
            definition_name = definition.name.to_s.strip
            definition_name = definition.entityID.to_s if definition_name.empty?
            first_instance = insts&.first
            rules = bom_rules_for_definition(definition)
            if rules.empty?
              rows_without_rules << report_row_without_rules(definition, definition_name, insts.size, first_instance)
            else
              rules.each do |rule|
                qty = compute_quantity(insts, rule)
                rows << report_row(definition, definition_name, rule, qty, first_instance)
              end
            end
          end
          geometry_only = geometry_only_groups(all_groups, instances)
          rows_geometry_only = geometry_only.map { |g| report_row_geometry_only(g) }
          {
            rows: rows,
            rows_without_rules: rows_without_rules,
            rows_geometry_only: rows_geometry_only,
            model_length_unit: model_length_unit_name
          }
        end

        def report_row_without_rules(definition, definition_name, count, first_instance = nil)
          {
            definition_name: definition_name,
            definition_id: definition.entityID,
            select_entity_id: first_instance.respond_to?(:entityID) ? first_instance.entityID : nil,
            code: "",
            label: "",
            measure: "count",
            uom: "pcs",
            quantity: count.to_f,
            category: "",
            section: "without_rules",
            exportable: exportable_for_definition(definition)
          }
        end

        def report_row_geometry_only(group)
          name = group.respond_to?(:name) ? group.name.to_s.strip : ""
          name = group.entityID.to_s if name.empty?
          {
            definition_name: name,
            definition_id: group.respond_to?(:entityID) ? group.entityID : nil,
            select_entity_id: group.respond_to?(:entityID) ? group.entityID : nil,
            code: "",
            label: "",
            measure: "count",
            uom: "pcs",
            quantity: 1.0,
            category: "",
            section: "geometry_only"
          }
        end

        def report_row(definition, definition_name, rule, quantity, first_instance = nil)
          {
            definition_name: definition_name,
            definition_id: definition.entityID,
            select_entity_id: first_instance.respond_to?(:entityID) ? first_instance.entityID : nil,
            code: (rule["code"] || rule[:code]).to_s,
            label: (rule["label"] || rule[:label]).to_s,
            measure: (rule["measure"] || rule[:measure]).to_s,
            uom: (rule["uom"] || rule[:uom]).to_s,
            quantity: quantity,
            category: (rule["category"] || rule[:category]).to_s,
            section: "with_rules",
            exportable: exportable_for_definition(definition)
          }
        end

        def length_unit_enum
          (model.options["UnitsOptions"] && model.options["UnitsOptions"]["LengthUnit"]) rescue nil
        end

        # Multiplier: inches → report length unit. Used for edge_length, etc.
        # Metric (mm, cm, m): report in m for consistency. Imperial: in or ft.
        def length_unit_factor
          unit = length_unit_enum
          case unit
          when LENGTH_UNIT_INCHES then 1.0
          when LENGTH_UNIT_FEET then 1.0 / 12.0
          when LENGTH_UNIT_MILLIMETER, LENGTH_UNIT_CENTIMETER, LENGTH_UNIT_METER then 0.0254 # in → m
          else 1.0
          end
        end

        # Multiplier: sq inches → report area unit. Metric → m² so values like 100, not 100000000.
        def area_unit_factor
          unit = length_unit_enum
          case unit
          when LENGTH_UNIT_INCHES then 1.0
          when LENGTH_UNIT_FEET then (1.0 / 12.0) ** 2
          when LENGTH_UNIT_MILLIMETER, LENGTH_UNIT_CENTIMETER, LENGTH_UNIT_METER then 0.0254 ** 2 # in² → m²
          else 1.0
          end
        end

        # Multiplier: cubic inches → report volume unit. Metric → m³.
        def volume_unit_factor
          unit = length_unit_enum
          case unit
          when LENGTH_UNIT_INCHES then 1.0
          when LENGTH_UNIT_FEET then (1.0 / 12.0) ** 3
          when LENGTH_UNIT_MILLIMETER, LENGTH_UNIT_CENTIMETER, LENGTH_UNIT_METER then 0.0254 ** 3 # in³ → m³
          else 1.0
          end
        end

        # Human-readable report units (what we actually output).
        def model_length_unit_name
          unit = length_unit_enum
          case unit
          when LENGTH_UNIT_INCHES then "in"
          when LENGTH_UNIT_FEET then "ft"
          when LENGTH_UNIT_MILLIMETER, LENGTH_UNIT_CENTIMETER, LENGTH_UNIT_METER then "m"
          else "in"
          end
        end

        # Compute quantity for a list of instances and a single rule (measure type).
        # Length/area/volume measures are converted to the model's length unit.
        def compute_quantity(instances, rule)
          measure = (rule["measure"] || rule[:measure]).to_s
          raw = case measure
                when "count" then compute_count(instances)
                when "bbox_volume" then compute_bbox_volume(instances)
                when "bbox_dimensions" then compute_bbox_dimensions(instances)
                when "total_area" then compute_total_area(instances)
                when "top_area" then compute_top_area(instances)
                when "bottom_area" then compute_bottom_area(instances)
                when "material_area" then compute_material_area(instances, rule)
                when "top_perimeter" then compute_top_perimeter(instances, rule)
                when "bottom_perimeter" then compute_bottom_perimeter(instances, rule)
                when "edge_length" then compute_edge_length(instances)
                when "smart_length" then compute_smart_length(instances)
                else compute_count(instances)
                end
          apply_rounding(raw, rule)
        end

        def compute_count(instances)
          instances.size.to_f
        end

        def compute_bbox_volume(instances)
          total = 0.0
          instances.each do |inst|
            b = inst.bounds
            next unless b.valid?
            total += b.width * b.height * b.depth
          end
          total * volume_unit_factor
        end

        def compute_bbox_dimensions(instances)
          return 0.0 if instances.empty?
          b = instances.first.bounds
          instances.drop(1).each { |inst| b.add(inst.bounds) }
          return 0.0 unless b.valid?
          (b.width * b.height * b.depth) * volume_unit_factor
        end

        def compute_total_area(instances)
          total = 0.0
          instances.each do |inst|
            tr = inst.transformation
            inst.definition.entities.grep(Sketchup::Face).each do |face|
              area = face.area
              scale = scale_from_transformation(tr)
              total += area * scale * scale
            end
          end
          total * area_unit_factor
        end

        # Top area = faces at bbox max Z with normal up (world). Uses bounds.max.z and face.area(tr).
        # z_tol: faces within this of max Z (inches). up_tol: normal.z >= this for "up".
        Z_TOL_TOP_AREA = 0.004 # ~0.1 mm in inches
        UP_TOL_TOP_AREA = 0.99

        def compute_top_area(instances)
          total = 0.0
          z_tol = Z_TOL_TOP_AREA
          up_tol = UP_TOL_TOP_AREA
          instances.each_with_index do |inst, idx|
            next unless inst.bounds.valid?
            tr = inst.transformation
            max_z = inst.bounds.max.z
            faces = inst.definition.entities.grep(Sketchup::Face)
            top_faces = faces.select do |f|
              n = f.normal.clone
              n.transform!(tr)
              n.normalize!
              next false if n.z < up_tol
              p = f.vertices[0].position.clone
              p.transform!(tr)
              (max_z - p.z).abs <= z_tol
            end
            area_sq_in = top_faces.sum { |f| f.area(tr) }
            total += area_sq_in

            if DEBUG_TOP_AREA && idx == 0
              puts "\n[BOM top_area DEBUG] #{inst.definition.name} max_z=#{max_z} top_faces=#{top_faces.size} area_sq_in=#{area_sq_in}\n"
            end
          end
          total * area_unit_factor
        end

        # Bottom area = faces at bbox min Z with normal down (world). Same logic as top_area for min_z.
        def compute_bottom_area(instances)
          total = 0.0
          z_tol = Z_TOL_TOP_AREA
          down_tol = -UP_TOL_TOP_AREA # n.z <= down_tol for "down"
          instances.each do |inst|
            next unless inst.bounds.valid?
            tr = inst.transformation
            min_z = inst.bounds.min.z
            faces = inst.definition.entities.grep(Sketchup::Face)
            bottom_faces = faces.select do |f|
              n = f.normal.clone
              n.transform!(tr)
              n.normalize!
              next false if n.z > down_tol
              p = f.vertices[0].position.clone
              p.transform!(tr)
              (min_z - p.z).abs <= z_tol
            end
            area_sq_in = bottom_faces.sum { |f| f.area(tr) }
            total += area_sq_in
          end
          total * area_unit_factor
        end

        # Area of faces that have the selected material (rule["params"]["material"] = material name).
        def compute_material_area(instances, rule)
          material_name = (rule["params"] || rule[:params]) && ((rule["params"] || rule[:params])["material"] || (rule["params"] || rule[:params])[:material])
          material_name = material_name.to_s.strip
          return 0.0 if material_name.empty?

          total = 0.0
          instances.each do |inst|
            tr = inst.transformation
            scale = scale_from_transformation(tr)
            inst.definition.entities.grep(Sketchup::Face).each do |face|
              next unless face.material
              next unless face.material.name.to_s == material_name
              total += face.area * scale * scale
            end
          end
          total * area_unit_factor
        end

        # Top boundary perimeter = length of edges that belong to exactly one top face (contour at max Z).
        # Same top-face selection as top_area (bounds.max.z, up_tol, z_tol).
        def compute_top_perimeter(instances, _rule = nil)
          total = 0.0
          z_tol = Z_TOL_TOP_AREA
          up_tol = UP_TOL_TOP_AREA
          instances.each do |inst|
            next unless inst.bounds.valid?
            tr = inst.transformation
            max_z = inst.bounds.max.z
            faces = inst.definition.entities.grep(Sketchup::Face)
            top_faces = faces.select do |f|
              n = f.normal.clone
              n.transform!(tr)
              n.normalize!
              next false if n.z < up_tol
              p = f.vertices[0].position.clone
              p.transform!(tr)
              (max_z - p.z).abs <= z_tol
            end
            next if top_faces.empty?

            top_set = top_faces.map { |f| [f, true] }.to_h
            boundary_edges = []
            top_faces.each do |f|
              f.edges.each do |e|
                top_adj = e.faces.count { |ff| top_set[ff] }
                boundary_edges << e if top_adj == 1
              end
            end
            perim_in = boundary_edges.uniq.sum { |e| edge_length_in_world(e, tr) }
            total += perim_in
          end
          total * length_unit_factor
        end

        # Bottom boundary perimeter = length of edges that belong to exactly one bottom face (contour at min Z).
        def compute_bottom_perimeter(instances, _rule = nil)
          total = 0.0
          z_tol = Z_TOL_TOP_AREA
          down_tol = -UP_TOL_TOP_AREA
          instances.each do |inst|
            next unless inst.bounds.valid?
            tr = inst.transformation
            min_z = inst.bounds.min.z
            faces = inst.definition.entities.grep(Sketchup::Face)
            bottom_faces = faces.select do |f|
              n = f.normal.clone
              n.transform!(tr)
              n.normalize!
              next false if n.z > down_tol
              p = f.vertices[0].position.clone
              p.transform!(tr)
              (min_z - p.z).abs <= z_tol
            end
            next if bottom_faces.empty?

            bottom_set = bottom_faces.map { |f| [f, true] }.to_h
            boundary_edges = []
            bottom_faces.each do |f|
              f.edges.each do |e|
                bottom_adj = e.faces.count { |ff| bottom_set[ff] }
                boundary_edges << e if bottom_adj == 1
              end
            end
            perim_in = boundary_edges.uniq.sum { |e| edge_length_in_world(e, tr) }
            total += perim_in
          end
          total * length_unit_factor
        end

        def edge_length_in_world(edge, tr)
          edge.length(tr)
        rescue ArgumentError, NoMethodError
          p1 = edge.start.position.transform(tr)
          p2 = edge.end.position.transform(tr)
          p1.distance(p2)
        end

        def compute_edge_length(instances)
          total = 0.0
          instances.each do |inst|
            tr = inst.transformation
            scale = scale_from_transformation(tr)
            inst.definition.entities.grep(Sketchup::Edge).each do |edge|
              total += edge.length * scale
            end
          end
          total * length_unit_factor
        end

        # Length of a curve (arc/polyline) in world space (inches).
        def curve_length_in_inches(curve, tr)
          curve.edges.sum { |e| edge_length_in_world(e, tr) }
        end

        # Max curve length in component (recursive into nested instances/groups). Returns inches.
        def dominant_curve_length_in_inches(comp_instance, recursive: true)
          best_len_in = 0.0
          walker = lambda do |entities, tr_acc|
            entities.grep(Sketchup::Edge).each do |e|
              c = e.curve
              next unless c
              len_in = curve_length_in_inches(c, tr_acc)
              best_len_in = len_in if len_in > best_len_in
            end
            return unless recursive
            entities.each do |ent|
              case ent
              when Sketchup::ComponentInstance
                walker.call(ent.definition.entities, tr_acc * ent.transformation)
              when Sketchup::Group
                walker.call(ent.entities, tr_acc * ent.transformation)
              end
            end
          end
          walker.call(comp_instance.definition.entities, comp_instance.transformation)
          best_len_in
        end

        # Per-instance length: dominant curve length, or max bbox dimension in world (inches).
        def smart_length_single_in_inches(comp_instance)
          len_in = dominant_curve_length_in_inches(comp_instance, recursive: true)
          return len_in if len_in > 0.0
          bb = comp_instance.definition.bounds
          return 0.0 unless bb.valid?
          tr = comp_instance.transformation
          sx = tr.xaxis.length
          sy = tr.yaxis.length
          sz = tr.zaxis.length
          [bb.width * sx, bb.depth * sy, bb.height * sz].max.to_f
        end

        def compute_smart_length(instances)
          total_in = instances.sum { |inst| smart_length_single_in_inches(inst) }
          total_in * length_unit_factor
        end

        def scale_from_transformation(tr)
          # Approximate uniform scale from transformation matrix
          x = Geom::Vector3d.new(1, 0, 0).transform(tr).length
          [x, 1.0].max
        end

        def apply_rounding(value, rule)
          rnd = rule["rounding"] || rule[:rounding]
          return value.to_f unless rnd.is_a?(Hash)
          mode = (rnd["mode"] || rnd[:mode]).to_s
          step = (rnd["step"] || rnd[:step]).to_f
          step = 0.01 if step <= 0
          case mode
          when "ceil" then (value.to_f / step).ceil * step
          when "floor" then (value.to_f / step).floor * step
          when "round" then (value.to_f / step).round * step
          else value.to_f
          end
        end

        # Find a Group or ComponentInstance in the model by entityID (for selection from UI).
        def self.find_entity_by_id(model, entity_id)
          return nil if model.nil? || entity_id.nil?
          id_str = entity_id.to_s
          return nil if id_str.empty?
          visited = {}
          stack = [model.entities]
          while stack.any?
            ents = stack.pop
            next if visited[ents.object_id]
            visited[ents.object_id] = true
            next unless ents.respond_to?(:each)
            ents.each do |e|
              if e.respond_to?(:entityID) && e.entityID.to_s == id_str
                return e
              end
              if e.is_a?(Sketchup::Group) && e.respond_to?(:entities)
                child = e.entities
                stack << child if child && !visited[child.object_id]
              end
            end
          end
          nil
        end

        # Convenience: run full export and return report rows.
        def self.export(model)
          new(model).build_report
        end
      end
    end
  end
end
