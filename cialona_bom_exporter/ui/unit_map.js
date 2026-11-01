var UnitMap = (function () {
  var UNITS = ["pcs", "m2", "mtr", "m3", "custom"];

  var DEFAULTS = {
    pcs: { export: "pcs", accept: ["stuks", "stuk", "pieces"] },
    m2: { export: "m2", accept: ["m²"] },
    mtr: { export: "mtr", accept: ["mtr.", "m", "meter", "meters", "linear meter"] },
    m3: { export: "m3", accept: ["m³", "m3.", "cubic meter", "cubic meters"] },
    custom: { export: "custom", accept: [] }
  };

  function cloneDefaults() {
    var out = {};
    UNITS.forEach(function (uom) {
      out[uom] = { export: DEFAULTS[uom].export, accept: DEFAULTS[uom].accept.slice() };
    });
    return out;
  }

  function parse(value) {
    var raw = value;
    if (typeof raw === "string") {
      try { raw = JSON.parse(raw); } catch (e) { raw = null; }
    }
    if (!raw || typeof raw !== "object") return cloneDefaults();
    var out = {};
    UNITS.forEach(function (uom) {
      var entry = raw[uom] || {};
      var exportName = entry.export != null ? String(entry.export).trim() : DEFAULTS[uom].export;
      if (!exportName) exportName = uom;
      var accept = Array.isArray(entry.accept) ? entry.accept : DEFAULTS[uom].accept;
      var names = [];
      accept.forEach(function (name) {
        var text = String(name == null ? "" : name).trim();
        if (!text) return;
        if (text.toLowerCase() === uom.toLowerCase()) return;
        if (text.toLowerCase() === exportName.toLowerCase()) return;
        if (names.some(function (existing) { return existing.toLowerCase() === text.toLowerCase(); })) return;
        names.push(text);
      });
      out[uom] = { export: exportName, accept: names };
    });
    return out;
  }

  function namesFor(entry, uom) {
    var names = [uom];
    if (entry.export) names.push(entry.export);
    return names.concat(entry.accept || []);
  }

  function toPlugin(external, map) {
    if (external == null) return "";
    var raw = String(external).trim();
    if (!raw) return "";
    var key = raw.toLowerCase();
    var parsed = parse(map);
    var found = "";
    UNITS.some(function (uom) {
      var hit = namesFor(parsed[uom], uom).some(function (name) {
        return String(name).trim().toLowerCase() === key;
      });
      if (hit) found = uom;
      return hit;
    });
    return found || raw;
  }

  function toExternal(pluginUom, map) {
    var uom = String(pluginUom == null ? "" : pluginUom).trim();
    if (!uom) return "";
    var parsed = parse(map);
    if (parsed[uom] && parsed[uom].export) return parsed[uom].export;
    return uom;
  }

  return {
    UNITS: UNITS,
    parse: parse,
    toPlugin: toPlugin,
    toExternal: toExternal
  };
})();
