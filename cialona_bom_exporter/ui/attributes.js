  var autoSaveTimer = null;
  var AUTO_SAVE_DEBOUNCE_MS = 600;

  // Measurement options: value -> label. Used to refill measure dropdown by UOM.
  var MEASURE_OPTIONS = [
    { value: "count", label: "Count" },
    { value: "top_area", label: "Top area" },
    { value: "bottom_area", label: "Bottom area" },
    { value: "total_area", label: "Total area" },
    { value: "material_area", label: "Material area" },
    { value: "top_perimeter", label: "Top perimeter" },
    { value: "bottom_perimeter", label: "Bottom perimeter" },
    { value: "smart_length", label: "Length" },
    { value: "bbox_volume", label: "BBox volume" },
    { value: "bbox_dimensions", label: "BBox dimensions" }
  ];
  // Allowed measure values per UOM. Empty string = placeholder only.
  var MEASURE_BY_UOM = {
    pcs: ["count"],
    m2: ["top_area", "bottom_area", "total_area", "material_area"],
    mtr: ["smart_length", "top_perimeter", "bottom_perimeter"],
    m3: ["bbox_volume"],
    custom: ["count", "top_area", "bottom_area", "total_area", "material_area", "top_perimeter", "bottom_perimeter", "smart_length", "bbox_volume", "bbox_dimensions"]
  };
  // Applied when the unit changes, or when the current measure is not valid for that unit.
  var DEFAULT_MEASURE_BY_UOM = {
    pcs: "count",
    m2: "top_area",
    mtr: "smart_length",
    m3: "bbox_volume",
    custom: "count"
  };

  function defaultMeasureForUom(uom, allowed) {
    var fallback = DEFAULT_MEASURE_BY_UOM[uom];
    if (fallback && allowed.indexOf(fallback) !== -1) return fallback;
    return allowed[0] || "";
  }

  function refillMeasureOptionsForForm(form, options) {
    var measureSelect = form && form.querySelector("[name='bom_measure']");
    var uomSelect = form && form.querySelector("[name='bom_uom']");
    if (!measureSelect || !uomSelect) return;
    var uom = (uomSelect.value || "").trim() || "pcs";
    var allowed = MEASURE_BY_UOM[uom] || MEASURE_BY_UOM.pcs;
    var current = measureSelect.value || "";
    var keepCurrent = !(options && options.forceDefault) && allowed.indexOf(current) !== -1;
    measureSelect.innerHTML = "";
    var empty = document.createElement("option");
    empty.value = "";
    empty.textContent = "Select measure";
    measureSelect.appendChild(empty);
    (allowed || []).forEach(function(val) {
      var rec = MEASURE_OPTIONS.find(function(r) { return r.value === val; });
      if (rec) {
        var opt = document.createElement("option");
        opt.value = rec.value;
        opt.textContent = rec.label;
        measureSelect.appendChild(opt);
      }
    });
    measureSelect.value = keepCurrent ? current : defaultMeasureForUom(uom, allowed);
    toggleMaterialParamVisibility(form);
  }

  window.refillMeasureOptionsForForm = refillMeasureOptionsForForm;

  function getEmptyRulesPlaceholder() {
    var p = document.createElement("div");
    p.className = "empty-rules-placeholder";
    p.textContent = "No rules yet. Click «Add rule» above to create one.";
    return p;
  }

  function ensureEmptyRulesPlaceholder(container) {
    if (!container) return;
    if (container.querySelectorAll("form").length === 0 && !container.querySelector(".empty-rules-placeholder")) {
      container.appendChild(getEmptyRulesPlaceholder());
    }
  }

  function removeEmptyRulesPlaceholder(container) {
    if (!container) return;
    var el = container.querySelector(".empty-rules-placeholder");
    if (el) el.remove();
  }

  function getBlockForm(block) {
    return block && block.querySelector && block.querySelector("form");
  }

  function updateBlockSummary(block) {
    var form = getBlockForm(block);
    var summaryEl = block && block.querySelector && block.querySelector(".attributes-block-summary");
    if (!form || !summaryEl) return;
    var code = (form.querySelector("[name='bom']") && form.querySelector("[name='bom']").value) || "—";
    var uomSelect = form.querySelector("[name='bom_uom']");
    var uom = (uomSelect && uomSelect.options[uomSelect.selectedIndex] && uomSelect.options[uomSelect.selectedIndex].text) ? uomSelect.options[uomSelect.selectedIndex].text : (uomSelect && uomSelect.value) || "—";
    var measureSelect = form.querySelector("[name='bom_measure']");
    var measure = (measureSelect && measureSelect.options[measureSelect.selectedIndex] && measureSelect.options[measureSelect.selectedIndex].text) ? measureSelect.options[measureSelect.selectedIndex].text : (measureSelect && measureSelect.value) || "—";
    summaryEl.textContent = code + " / " + uom + " / " + measure;
  }

  function addItem(content) {
    content = content || {};
    var template = document.getElementById("attributes-template");
    if (!template || !template.content) return;
    var clone = template.content.cloneNode(true);
    var container = document.getElementById("attributes-container");
    if (!container) return;
    container.appendChild(clone);
    removeEmptyRulesPlaceholder(container);
    var blocks = container.querySelectorAll(".attributes-block");
    var block = blocks[blocks.length - 1];
    var form = block && getBlockForm(block);
    if (form) {
      var forms = container.querySelectorAll("form");
      var idxInput = form.querySelector("input[name='ruleset_idx']");
      if (idxInput) idxInput.value = forms.length - 1;
      form.reset();
      if (idxInput) idxInput.value = forms.length - 1;
      fillMaterialSelectForForm(form);
      applyValuesToForm(form, content);
      refillMeasureOptionsForForm(form);
      updateBlockSummary(block);
      var header = block.querySelector(".attributes-block-header");
      if (header) {
        header.addEventListener("click", function() {
          block.classList.toggle("collapsed");
        });
      }
    }
  }

  function applyValuesToForm(form, values) {
    if (!form || !values || typeof values !== "object") return;
    Object.keys(values).forEach(function(key) {
      var input = form.querySelector("[name='" + key + "']");
      if (input && values[key] != null) {
        if (input.tagName === "SELECT") {
          var opt = input.querySelector("option[value='" + String(values[key]) + "']");
          if (opt) input.value = values[key];
        } else {
          input.value = values[key];
        }
      }
    });
  }

  window.onSketchUpSelection = function(payload) {
    try {
      console.log("onSketchUpSelection", payload);
      var emptyMsg = document.getElementById("empty-selection-message");
      var container = document.getElementById("attributes-container");
      if (!payload || !payload.type) return;

      if (payload.type === "error") {
        setNoSelectionState(emptyMsg, payload.reason, container, document.getElementById("toolbar-actions"));
        return;
      }

      if (payload.type === "attributes") {
        setSelectionState(emptyMsg, container, document.getElementById("toolbar-actions"));
        clearDirtyState();
        if (!container) return;
        var exportableWrap = document.getElementById("exportable-wrap");
        var exportableFlag = document.getElementById("exportable-flag");
        if (exportableWrap) {
          exportableWrap.classList.remove("hidden");
          exportableWrap.setAttribute("aria-hidden", "false");
        }
        if (exportableFlag) exportableFlag.checked = payload.exportable !== false;
        window.currentComponentMaterials = payload.materials && Array.isArray(payload.materials) ? payload.materials : [];
        var schemaVersion = (payload.schema_version && typeof payload.schema_version === "string") ? payload.schema_version : "1.0";
        container.setAttribute("data-schema-version", schemaVersion);
        container.innerHTML = "";
        var rules = [];
        try {
          if (payload.bom_rules != null) {
            var raw = typeof payload.bom_rules === "string" ? payload.bom_rules : JSON.stringify(payload.bom_rules);
            if (raw) rules = JSON.parse(raw);
          }
        } catch (e) {
          console.warn("onSketchUpSelection: invalid bom_rules JSON", e);
        }
        if (!Array.isArray(rules)) rules = [];
        rules.forEach(function(rule) {
          addItem(ruleToFormValues(rule));
        });
        container.querySelectorAll(".attributes-block").forEach(function(block) {
          updateBlockSummary(block);
        });
        if (rules.length === 0) ensureEmptyRulesPlaceholder(container);
      }
    } catch (err) {
      console.error("onSketchUpSelection error:", err);
    }
  };

  function setNoSelectionState(emptyMsg, reason, container, toolbar) {
    if (emptyMsg) {
      emptyMsg.textContent = reason === "none_selected" ? "Nothing selected" :
        reason === "not_a_component" ? "Select a component (not a group, face, or edge)" :
        "Select a single entity";
      emptyMsg.classList.remove("hidden");
      emptyMsg.setAttribute("aria-hidden", "false");
    }
    if (container) container.innerHTML = "";
    if (toolbar) {
      toolbar.setAttribute("aria-hidden", "true");
      toolbar.classList.add("hidden");
    }
    var exportableWrap = document.getElementById("exportable-wrap");
    if (exportableWrap) {
      exportableWrap.classList.add("hidden");
      exportableWrap.setAttribute("aria-hidden", "true");
    }
  }

  function setSelectionState(emptyMsg, container, toolbar) {
    if (emptyMsg) {
      emptyMsg.classList.add("hidden");
      emptyMsg.setAttribute("aria-hidden", "true");
    }
    if (toolbar) {
      toolbar.removeAttribute("aria-hidden");
      toolbar.classList.remove("hidden");
    }
  }

  function formValuesToRule(form) {
    if (!form) return {};
    var rule = {};
    var bom = form.querySelector("[name='bom']");
    var bomLabel = form.querySelector("[name='bom_label']");
    var bomMeasure = form.querySelector("[name='bom_measure']");
    var bomUom = form.querySelector("[name='bom_uom']");
    var bomCategory = form.querySelector("[name='bom_category']");
    var bomRoundingMode = form.querySelector("[name='bom_rounding_mode']");
    var bomRoundingStep = form.querySelector("[name='bom_rounding_step']");
    var bomParamMaterial = form.querySelector("[name='bom_param_material']");
    if (bom && bom.value !== undefined) rule.code = bom.value;
    if (bomLabel && bomLabel.value !== undefined) rule.label = bomLabel.value;
    if (bomMeasure && bomMeasure.value !== undefined) rule.measure = bomMeasure.value;
    if (bomUom && bomUom.value !== undefined) rule.uom = normalizeUom(bomUom.value);
    if (bomCategory && bomCategory.value !== undefined && bomCategory.value !== "") rule.category = bomCategory.value;
    if (bomMeasure && bomMeasure.value === "material_area" && bomParamMaterial && bomParamMaterial.value) {
      rule.params = rule.params || {};
      rule.params.material = bomParamMaterial.value;
    }
    if (bomRoundingMode || bomRoundingStep) {
      rule.rounding = {};
      if (bomRoundingMode && bomRoundingMode.value !== undefined) rule.rounding.mode = bomRoundingMode.value;
      if (bomRoundingStep && bomRoundingStep.value !== undefined) rule.rounding.step = parseFloat(bomRoundingStep.value, 10) || 0.01;
    }
    return rule;
  }

  function collectAttributesFromUI() {
    var container = document.getElementById("attributes-container");
    if (!container) return { schema_version: "1.0", bom_rules: "[]" };
    var schemaVersion = container.getAttribute("data-schema-version") || "1.0";
    var forms = container.querySelectorAll("form");
    var rules = [];
    for (var i = 0; i < forms.length; i++) {
      rules.push(formValuesToRule(forms[i]));
    }
    return { schema_version: schemaVersion, bom_rules: JSON.stringify(rules) };
  }

  function setDirty(form) {
    if (form) form.classList.add("attributes-form--dirty");
    var btn = document.getElementById("btn-save");
    if (btn) btn.classList.remove("hidden");
  }

  function clearDirtyState() {
    var container = document.getElementById("attributes-container");
    if (container) {
      container.querySelectorAll("form.attributes-form--dirty").forEach(function(f) { f.classList.remove("attributes-form--dirty"); });
    }
    var btn = document.getElementById("btn-save");
    if (btn) btn.classList.add("hidden");
  }

  function scheduleAutoSave() {
    if (autoSaveTimer) clearTimeout(autoSaveTimer);
    autoSaveTimer = setTimeout(function() {
      autoSaveTimer = null;
      saveAttributes();
    }, AUTO_SAVE_DEBOUNCE_MS);
  }

  function saveAttributes() {
    if (autoSaveTimer) {
      clearTimeout(autoSaveTimer);
      autoSaveTimer = null;
    }
    var payload = collectAttributesFromUI();
    var rules = [];
    try {
      var raw = payload.bom_rules;
      if (typeof raw === "string" && raw) rules = JSON.parse(raw);
      else if (Array.isArray(raw)) rules = raw;
    } catch (e) { rules = []; }
    var missing = rules.some(function(r) {
      var m = (r && r.measure != null) ? r.measure : "";
      return (typeof m === "string" ? m.trim() : String(m)) === "";
    });
    if (missing) {
      return;
    }
    var missingMaterial = rules.some(function(r) {
      if (!r || (r.measure || "").toString().trim() !== "material_area") return false;
      var mat = (r.params && r.params.material != null) ? r.params.material : "";
      return (typeof mat === "string" ? mat.trim() : String(mat)) === "";
    });
    if (missingMaterial) {
      return;
    }
    var exportableFlag = document.getElementById("exportable-flag");
    payload.exportable = exportableFlag ? exportableFlag.checked : true;
    clearDirtyState();
    sketchup.save_attributes(JSON.stringify(payload));
  }

  var FORM_FIELDS = ["bom", "bom_label", "bom_measure", "bom_uom", "bom_category", "bom_rounding_mode", "bom_rounding_step", "bom_param_material"];

  // Schema once used "m"; FileMaker / UI use "mtr".
  function normalizeUom(uom) {
    var u = (uom == null ? "" : String(uom)).trim();
    if (u === "m") return "mtr";
    return u;
  }

  function ruleToFormValues(rule) {
    if (!rule || typeof rule !== "object") return {};
    var v = {};
    FORM_FIELDS.forEach(function(k) {
      if (rule[k] != null) v[k] = rule[k];
    });
    if (v.bom == null && rule.code != null) v.bom = rule.code;
    if (v.bom_label == null && rule.label != null) v.bom_label = rule.label;
    if (v.bom_measure == null && rule.measure != null) v.bom_measure = rule.measure;
    if (v.bom_uom == null && rule.uom != null) v.bom_uom = rule.uom;
    if (v.bom_uom != null) v.bom_uom = normalizeUom(v.bom_uom);
    if (v.bom_category == null && rule.category != null) v.bom_category = rule.category;
    if (rule.params && typeof rule.params === "object" && rule.params.material != null) {
      v.bom_param_material = rule.params.material;
    }
    if (rule.rounding && typeof rule.rounding === "object") {
      if (v.bom_rounding_mode == null && rule.rounding.mode != null) v.bom_rounding_mode = rule.rounding.mode;
      if (v.bom_rounding_step == null && rule.rounding.step != null) v.bom_rounding_step = rule.rounding.step;
    }
    return v;
  }

  function fillMaterialSelectForForm(form, materials) {
    var sel = form && form.querySelector("[name='bom_param_material']");
    if (!sel) return;
    materials = materials || (window.currentComponentMaterials || []);
    sel.innerHTML = "";
    var empty = document.createElement("option");
    empty.value = "";
    empty.textContent = "Select material";
    sel.appendChild(empty);
    materials.forEach(function(name) {
      var opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      sel.appendChild(opt);
    });
  }

  function toggleMaterialParamVisibility(form) {
    var measureSelect = form && form.querySelector("[name='bom_measure']");
    var materialRow = form && form.querySelector(".measure-param--material");
    if (!measureSelect || !materialRow) return;
    materialRow.style.display = (measureSelect.value === "material_area") ? "" : "none";
  }

  $(document).ready(function() {
    sketchup.ready();
    var exportableFlag = document.getElementById("exportable-flag");
    if (exportableFlag) {
      exportableFlag.addEventListener("change", function() {
        setDirty(null);
        scheduleAutoSave();
      });
    }
    var container = document.getElementById("attributes-container");
    if (container) {
      container.addEventListener("change", function(e) {
        var form = e.target && e.target.closest && e.target.closest("form");
        if (form) {
          setDirty(form);
          scheduleAutoSave();
          if (e.target && e.target.getAttribute("name") === "bom_measure") {
            toggleMaterialParamVisibility(form);
          }
          if (e.target && e.target.getAttribute("name") === "bom_uom") {
            refillMeasureOptionsForForm(form, { forceDefault: true });
          }
          var block = form.closest(".attributes-block");
          if (block) updateBlockSummary(block);
        }
      });
      container.addEventListener("input", function(e) {
        var form = e.target && e.target.closest && e.target.closest("form");
        if (form) {
          setDirty(form);
          scheduleAutoSave();
          var block = form.closest(".attributes-block");
          if (block) updateBlockSummary(block);
        }
      });
    }
  });