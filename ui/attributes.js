
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

  function addItem(content) {
    content = content || {};
    var template = document.getElementById("attributes-template");
    if (!template || !template.content) return;
    var clone = template.content.cloneNode(true);
    var container = document.getElementById("attributes-container");
    if (!container) return;
    container.appendChild(clone);
    removeEmptyRulesPlaceholder(container);
    var forms = container.querySelectorAll("form");
    var form = forms[forms.length - 1];
    if (form) {
      var idxInput = form.querySelector("input[name='ruleset_idx']");
      if (idxInput) idxInput.value = forms.length - 1;
      form.reset();
      if (idxInput) idxInput.value = forms.length - 1;
      applyValuesToForm(form, content);
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
    if (bom && bom.value !== undefined) rule.code = bom.value;
    if (bomLabel && bomLabel.value !== undefined) rule.label = bomLabel.value;
    if (bomMeasure && bomMeasure.value !== undefined) rule.measure = bomMeasure.value;
    if (bomUom && bomUom.value !== undefined) rule.uom = bomUom.value;
    if (bomCategory && bomCategory.value !== undefined && bomCategory.value !== "") rule.category = bomCategory.value;
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

  function saveAttributes() {
    clearDirtyState();
    var payload = collectAttributesFromUI();
    sketchup.save_attributes(JSON.stringify(payload));
  }

  var FORM_FIELDS = ["bom", "bom_label", "bom_measure", "bom_uom", "bom_category", "bom_rounding_mode", "bom_rounding_step"];

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
    if (v.bom_category == null && rule.category != null) v.bom_category = rule.category;
    if (rule.rounding && typeof rule.rounding === "object") {
      if (v.bom_rounding_mode == null && rule.rounding.mode != null) v.bom_rounding_mode = rule.rounding.mode;
      if (v.bom_rounding_step == null && rule.rounding.step != null) v.bom_rounding_step = rule.rounding.step;
    }
    return v;
  }

  $(document).ready(function() {
    sketchup.ready();
    var container = document.getElementById("attributes-container");
    if (container) {
      container.addEventListener("change", function(e) {
        var form = e.target && e.target.closest && e.target.closest("form");
        if (form) setDirty(form);
      });
      container.addEventListener("input", function(e) {
        var form = e.target && e.target.closest && e.target.closest("form");
        if (form) setDirty(form);
      });
    }
  });