let catalogDropdownHideTimer = null;
    const MAX_RESULTS = 20;
    const CATALOG_API_RESULT_LIMIT = 10;
    const SEARCH_DEBOUNCE_MS = 250;
    let catalogApiUrl = "";
    let catalogApiKey = "";
    let catalogApiProfile = {};
    let catalogSource = "api";
    let catalogCsvItems = [];
    let catalogCsvLoaded = false;
    let catalogCsvError = null;
    let catalogCsvPath = "";

    let validateCodesAgainstCatalog = true;
    let freeEditMode = false;
    let unitMap = null;

    window.onCatalogSettings = function(data) {
      if (data) {
        catalogApiUrl = (data.catalog_api_url || "").trim();
        catalogApiKey = (data.catalog_api_key || "").trim();
        catalogApiProfile = ApiAdapter.parse(data.catalog_api_profile, {});
        validateCodesAgainstCatalog = data.catalog_validate_codes !== false && data.catalog_validate_codes !== "false";
        freeEditMode = data.free_edit_mode === true || data.free_edit_mode === "true";
        catalogSource = ((data.catalog_source || "api") + "").toLowerCase() === "csv" ? "csv" : "api";
        unitMap = data.unit_map || null;
        catalogCsvItems = Array.isArray(data.csv_items) ? data.csv_items : [];
        catalogCsvLoaded = data.csv_loaded === true;
        catalogCsvError = data.csv_error || null;
        catalogCsvPath = data.csv_path || "";
      }
      updateCatalogStatusBanners();
      applyFreeEditMode();
      setCatalogDebugEnabled(!!(data && (data.dev_mode === true || data.dev_mode === "true")));
      renderCatalogDebugStatus();
      logCatalogDebug("settings loaded");
    };

    function applyFreeEditMode() {
      document.body.classList.toggle("free-edit-mode", freeEditMode);
      document.querySelectorAll(".free-edit-only").forEach((el) => {
        el.style.display = freeEditMode ? "" : "none";
      });
    }

    function getCatalogApiUrl() {
      return catalogApiUrl;
    }
    function getCatalogApiKey() {
      return catalogApiKey;
    }

    function isCatalogApiConfigured() {
      return !!(getCatalogApiUrl() && getCatalogApiKey());
    }

    function catalogSettingsMissingMessage() {
      return "Catalog API is not configured. Set URL/key in Plugin Settings.";
    }

    function isCsvSource() {
      return catalogSource === "csv";
    }

    function csvLoadMessage() {
      if (catalogCsvError === "unset" || !catalogCsvPath) return "Choose a catalog CSV in Plugin Settings.";
      if (catalogCsvError === "unmapped") return "Choose the CSV columns in Plugin Settings before searching products.";
      if (catalogCsvError === "invalid") return "Catalog CSV could not be read: " + catalogCsvPath;
      if (catalogCsvError === "empty") return "Catalog CSV has no products: " + catalogCsvPath;
      return "Catalog CSV was not found: " + catalogCsvPath;
    }

    function setCatalogBanner(elId, visible, message) {
      const el = document.getElementById(elId);
      if (!el) return;
      if (visible && message) {
        el.textContent = message;
        el.style.display = "block";
        el.setAttribute("aria-hidden", "false");
      } else {
        el.textContent = "";
        el.style.display = "none";
        el.setAttribute("aria-hidden", "true");
      }
    }

    function updateCatalogStatusBanners() {
      if (freeEditMode) {
        setCatalogBanner("catalog-source-warning", false, "");
        setCatalogBanner("catalog-api-error", false, "");
        return;
      }
      if (isCsvSource()) {
        setCatalogBanner("catalog-api-error", false, "");
        if (!catalogCsvLoaded) {
          setCatalogBanner(
            "catalog-source-warning",
            true,
            csvLoadMessage()
          );
        } else {
          setCatalogBanner("catalog-source-warning", false, "");
        }
        return;
      }

      if (!isCatalogApiConfigured()) {
        setCatalogBanner(
          "catalog-source-warning",
          true,
          catalogSettingsMissingMessage()
        );
      } else {
        setCatalogBanner("catalog-source-warning", false, "");
      }
    }

    function showCatalogApiError(message) {
      setCatalogBanner("catalog-api-error", true, message || "Catalog API request failed.");
    }

    function clearCatalogApiError() {
      setCatalogBanner("catalog-api-error", false, "");
    }

    let catalogDebugEnabled = false;

    function redactSecrets(value) {
      const text = typeof value === "string" ? value : JSON.stringify(value);
      return String(text == null ? "" : text)
        .replace(/([?&]apiKey=)[^&\s"]*/gi, "$1***")
        .replace(/("apiKey"\s*:\s*")[^"]*/gi, "$1***")
        .replace(/(Authorization"\s*:\s*")[^"]*/gi, "$1***");
    }

    function clipText(value, max) {
      const text = String(value == null ? "" : value);
      if (text.length <= max) return text;
      return text.slice(0, max) + "… (" + text.length + " chars)";
    }

    function summarizeResponse(data) {
      if (Array.isArray(data)) return "array len=" + data.length;
      if (!data || typeof data !== "object") return typeof data;
      let summary = "keys=" + Object.keys(data).slice(0, 12).join(",");
      const scriptResult = data.scriptResult;
      if (scriptResult && typeof scriptResult === "object") {
        summary += " scriptResult.keys=" + Object.keys(scriptResult).join(",");
        if (Array.isArray(scriptResult.result)) summary += " result.len=" + scriptResult.result.length;
      }
      return summary;
    }

    function syncCatalogDebugDock() {
      const root = document.getElementById("catalog-debug");
      if (!root || root.hidden) {
        document.body.style.paddingBottom = "";
        return;
      }
      document.body.style.paddingBottom = (root.offsetHeight + 8) + "px";
    }

    function renderCatalogDebugStatus() {
      const el = document.getElementById("catalog-debug-status");
      if (!el) return;
      el.textContent = [
        "source=" + catalogSource,
        "url=" + redactSecrets(catalogApiUrl || "(empty)"),
        "key=" + (catalogApiKey ? "set" : "missing"),
        "subgroup=same URL, payload subgroup:1",
        "freeEdit=" + (freeEditMode ? "on" : "off")
      ].join("\n");
      syncCatalogDebugDock();
    }

    function logCatalogDebug(message) {
      if (!catalogDebugEnabled) return;
      const line = new Date().toISOString().slice(11, 19) + "  " + message;
      console.log("[catalog]", message);
      const log = document.getElementById("catalog-debug-log");
      if (!log) return;
      log.textContent += (log.textContent ? "\n" : "") + line;
      log.scrollTop = log.scrollHeight;
      syncCatalogDebugDock();
    }

    function setCatalogDebugEnabled(on) {
      catalogDebugEnabled = !!on;
      const root = document.getElementById("catalog-debug");
      if (root) root.hidden = !catalogDebugEnabled;
      renderCatalogDebugStatus();
      syncCatalogDebugDock();
      if (catalogDebugEnabled) logCatalogDebug("debug on");
    }

    window.addEventListener("resize", syncCatalogDebugDock);

    function clearCatalogDebug() {
      const log = document.getElementById("catalog-debug-log");
      if (log) log.textContent = "";
    }

    window.clearCatalogDebug = clearCatalogDebug;

    function getDropdown(input) {
      const wrap = input.closest(".catalog-search-wrap");
      return wrap ? wrap.querySelector(".catalog-dropdown") : null;
    }

    function showCatalogResults(input, results) {
      const ul = getDropdown(input);
      if (!ul) return;
      ul.innerHTML = "";
      if (results.length === 0) {
        ul.style.display = "none";
        return;
      }
      const limit = results.slice(0, MAX_RESULTS);
      limit.forEach((item) => {
        const li = document.createElement("li");
        li.innerHTML = "<span class=\"item-code\">" + escapeHtml(item.code || "") + "</span>" +
          "<span class=\"item-name\">" + escapeHtml(item.name || "") + "</span>";
        if (String(item.source || "").toLowerCase() === "subgroup") {
          const badge = document.createElement("span");
          badge.className = "item-source";
          badge.textContent = "subgroup";
          li.appendChild(badge);
        }
        li.dataset.code = item.code || "";
        li.dataset.name = item.name || "";
        li.dataset.unit = item.unit || "";
        li.addEventListener("mousedown", (e) => {
          e.preventDefault();
          cancelCatalogSearch();
          selectCatalogItem(input, item);
          ul.style.display = "none";
        });
        ul.appendChild(li);
      });
      ul.style.display = "block";
    }

    function escapeHtml(s) {
      const div = document.createElement("div");
      div.textContent = s;
      return div.innerHTML;
    }

    /**
     * Map an external unit to a plugin UOM using the configured unit map.
     */
    function normalizeApiUnitToFormUom(apiUnit) {
      if (!apiUnit || typeof apiUnit !== "string") return "";
      if (typeof UnitMap === "undefined") return apiUnit.trim();
      return UnitMap.toPlugin(apiUnit, unitMap);
    }

    function selectCatalogItem(input, item) {
      const rowOrFieldset = input.closest("fieldset") || input.closest("tr");
      if (!rowOrFieldset) return;
      input.value = item.code || "";
      const labelInput = rowOrFieldset.querySelector("input[name=bom_label]");
      if (labelInput) labelInput.value = item.name || "";
      const categoryInput = rowOrFieldset.querySelector("input[name=bom_category]");
      if (categoryInput) categoryInput.value = item.category || "";
      const uomSelect = rowOrFieldset.querySelector("select[name=bom_uom]");
      let appliedUom = "";
      if (uomSelect && item.unit) {
        const formUom = normalizeApiUnitToFormUom(item.unit);
        if (formUom) {
          const opt = [...uomSelect.options].find((o) => o.value === formUom);
          if (opt) {
            uomSelect.value = formUom;
            appliedUom = formUom;
          }
        }
      }
      if (typeof window.refillMeasureOptionsForForm === "function") {
        window.refillMeasureOptionsForForm(rowOrFieldset, { forceDefault: !!appliedUom });
      }
      if (typeof $ !== "undefined") {
        $(rowOrFieldset).find("input[name=bom]").val(item.code || "");
        $(rowOrFieldset).find("input[name=bom_label]").val(item.name || "");
        $(rowOrFieldset).find("input[name=bom_category]").val(item.category || "");
        if (appliedUom) $(rowOrFieldset).find("select[name=bom_uom]").val(appliedUom);
      }
    }

    function hideCatalogDropdown() {
      if (catalogDropdownHideTimer) clearTimeout(catalogDropdownHideTimer);
      catalogDropdownHideTimer = setTimeout(() => {
        document.querySelectorAll(".catalog-dropdown").forEach((ul) => { ul.style.display = "none"; });
        catalogDropdownHideTimer = null;
      }, 150);
    }

    function searchCatalogLocal(query) {
      const q = (query || "").trim().toLowerCase();
      if (!q || !catalogCsvLoaded) return [];

      const scored = [];
      catalogCsvItems.forEach((item) => {
        const code = (item.code || "").toLowerCase();
        const name = (item.name || "").toLowerCase();
        let score = 0;
        if (code === q) score = 300;
        else if (code.indexOf(q) === 0) score = 200;
        else if (code.indexOf(q) >= 0) score = 150;
        else if (name.indexOf(q) >= 0) score = 100;
        if (score > 0) scored.push({ score: score, item: item });
      });
      scored.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        return (a.item.code || "").localeCompare(b.item.code || "");
      });
      return scored.slice(0, MAX_RESULTS).map(function (s) { return s.item; });
    }

    /**
     * Fetch catalog results from API for a query (no UI).
     * @param {string} query - Search query.
     * @param {Object} [options] - Optional overrides.
     * @returns {Promise<Array<{code, name, unit?, category?}>>} Normalized results.
     */
    function fetchCatalogQuery(query, options) {
      const opts = options || {};
      const apiUrl = opts.apiUrl != null ? opts.apiUrl : getCatalogApiUrl();
      const apiKey = opts.apiKey != null ? opts.apiKey : getCatalogApiKey();
      const resultLimit = opts.resultLimit != null ? opts.resultLimit : CATALOG_API_RESULT_LIMIT;
      const profile = catalogApiProfile || {};
      const responseSpec = profile.response || {};
      const mapItem = opts.mapItem || ((item) => ApiAdapter.mapFields(item, responseSpec.fields || {
        code: "code", name: "name", unit: "unit", category: "category"
      }));

      const q = (query || "").trim();
      if (!q) return Promise.resolve([]);

      const endpointSource = opts.source || "product";
      logCatalogDebug("request " + endpointSource + " " + String(profile.method || "POST").toUpperCase() + " " + redactSecrets(apiUrl || "(empty)") + " key=" + (apiKey ? "set" : "missing"));
      if (!apiUrl || !apiKey) {
        return Promise.reject(new Error(catalogSettingsMissingMessage()));
      }

      const requestSpec = profile.request || {};
      const payload = {};
      ApiAdapter.set(payload, requestSpec.query_path || "query", q);
      ApiAdapter.set(payload, requestSpec.limit_path || "resultLimit", resultLimit);
      if (endpointSource === "subgroup") {
        ApiAdapter.set(payload, requestSpec.subgroup_path || "subgroup", 1);
      }
      logCatalogDebug("  body " + clipText(redactSecrets(payload), 500));
      return ApiAdapter.request(apiUrl, profile, payload, { api_key: apiKey }, { query: q, limit: resultLimit })
        .then((data) => {
          let rawList = Array.isArray(data) ? data : ApiAdapter.get(data, responseSpec.items_path || "scriptResult.result", null);
          (responseSpec.fallback_items_paths || ["results", "data"]).some((path) => {
            if (Array.isArray(rawList)) return true;
            rawList = ApiAdapter.get(data, path, null);
            return Array.isArray(rawList);
          });
          if (!Array.isArray(rawList)) rawList = [];
          const mapped = rawList.map((rawItem) => {
            const item = mapItem(rawItem) || {};
            const fromResponse = rawItem && rawItem.source != null ? String(rawItem.source).trim() : "";
            const fromMapped = item.source != null ? String(item.source).trim() : "";
            item.source = fromResponse || fromMapped || endpointSource;
            return item;
          });
          logCatalogDebug("  ok " + endpointSource + " " + summarizeResponse(data) + " mapped=" + mapped.length);
          if (!mapped.length) logCatalogDebug("  raw " + clipText(redactSecrets(data), 1500));
          else logCatalogDebug("  items " + mapped.slice(0, 8).map((item) => (item.code || "?") + "/" + (item.source || "")).join(", "));
          return mapped;
        });
    }

    function catalogEndpointLabel(source) {
      return source === "subgroup" ? "Subgroup catalog" : "Product catalog";
    }

    function formatCatalogErrors(errors) {
      return (errors || []).map((entry) => {
        const detail = entry.error && entry.error.message ? entry.error.message : "request failed.";
        return catalogEndpointLabel(entry.source) + " request failed: " + detail;
      }).join(" ");
    }

    function mergeCatalogResults(products, subgroups, limit) {
      const seen = {};
      const merged = [];
      (products || []).forEach((item) => {
        const code = (item.code || "").trim();
        if (code) seen[code] = true;
        merged.push(item);
      });
      (subgroups || []).forEach((item) => {
        const code = (item.code || "").trim();
        if (code && seen[code]) return;
        if (code) seen[code] = true;
        merged.push(item);
      });
      return limit != null ? merged.slice(0, limit) : merged;
    }

    /**
     * Query the same catalog URL twice: products, then subgroups (payload subgroup: 1).
     * A failed request does not drop results from the other one.
     * @returns {Promise<{results: Array, errors: Array}>}
     */
    function fetchMergedCatalog(query, options) {
      const opts = options || {};
      const catalogUrl = getCatalogApiUrl();
      const tasks = [
        { source: "product", url: catalogUrl },
        { source: "subgroup", url: catalogUrl }
      ];
      return Promise.all(tasks.map((task) => {
        const taskOpts = Object.assign({}, opts, { apiUrl: task.url, source: task.source });
        return fetchCatalogQuery(query, taskOpts)
          .then((results) => ({ source: task.source, results: results, error: null }))
          .catch((error) => {
            logCatalogDebug("  error " + task.source + " " + (error && error.message ? error.message : error));
            return { source: task.source, results: [], error: error };
          });
      })).then((parts) => {
        let products = [];
        let subgroups = [];
        const errors = [];
        parts.forEach((part) => {
          if (part.error) {
            errors.push(part);
            return;
          }
          if (part.source === "subgroup") subgroups = part.results;
          else products = part.results;
        });
        const results = mergeCatalogResults(products, subgroups, opts.mergeLimit);
        logCatalogDebug("merged products=" + products.length + " subgroups=" + subgroups.length + " errors=" + errors.length + " kept=" + results.length);
        return {
          results: results,
          errors: errors
        };
      });
    }

    /**
     * Search catalog via active source (API or CSV).
     * Kept as searchCatalogViaApi for existing HTML onkeyup/onfocus handlers.
     */
    let catalogSearchTimer = null;
    let catalogSearchSeq = 0;

    function cancelCatalogSearch() {
      if (catalogSearchTimer) {
        clearTimeout(catalogSearchTimer);
        catalogSearchTimer = null;
      }
      catalogSearchSeq += 1;
    }

    function searchCatalogViaApi(input, options) {
      if (freeEditMode) return;
      if (catalogSearchTimer) {
        clearTimeout(catalogSearchTimer);
        catalogSearchTimer = null;
      }
      const query = (input.value || "").trim();
      if (!query) {
        catalogSearchSeq += 1;
        showCatalogResults(input, []);
        return Promise.resolve([]);
      }

      if (isCsvSource()) {
        const results = searchCatalogLocal(query);
        logCatalogDebug("search csv " + JSON.stringify(query) + " local=" + results.length);
        showCatalogResults(input, results);
        return Promise.resolve(results);
      }

      const seq = ++catalogSearchSeq;
      const searchOpts = Object.assign({}, options || {}, { mergeLimit: MAX_RESULTS });
      return new Promise((resolve, reject) => {
        catalogSearchTimer = setTimeout(() => {
          catalogSearchTimer = null;
          if (seq !== catalogSearchSeq || (input.value || "").trim() !== query) {
            logCatalogDebug("search ignored: a newer query replaced " + JSON.stringify(query));
            resolve([]);
            return;
          }
          logCatalogDebug("search " + JSON.stringify(query));
          fetchMergedCatalog(query, searchOpts)
            .then((outcome) => {
              if (seq !== catalogSearchSeq || (input.value || "").trim() !== query) {
                logCatalogDebug("results ignored: a newer query replaced " + JSON.stringify(query));
                resolve([]);
                return;
              }
              if (outcome.errors.length) {
                showCatalogApiError(formatCatalogErrors(outcome.errors));
              } else {
                clearCatalogApiError();
              }
              if (document.activeElement === input) {
                showCatalogResults(input, outcome.results);
              } else {
                logCatalogDebug("dropdown not shown: code field is not focused");
              }
              if (outcome.errors.length && outcome.results.length === 0) {
                const err = outcome.errors[0].error || new Error("Catalog API request failed.");
                console.error("searchCatalogViaApi failed:", err);
                reject(err);
                return;
              }
              resolve(outcome.results);
            })
            .catch((err) => {
              if (seq !== catalogSearchSeq) {
                resolve([]);
                return;
              }
              console.error("searchCatalogViaApi failed:", err);
              if (document.activeElement === input) showCatalogResults(input, []);
              showCatalogApiError(err && err.message ? err.message : "Catalog API request failed.");
              reject(err);
            });
        }, SEARCH_DEBOUNCE_MS);
      });
    }

    function findExactCatalogMatch(query, results) {
      return (results || []).find((r) => (r.code || "").trim() === query) || null;
    }

    /**
     * Validate that the current code input value exists in the active catalog (exact match).
     * If not found: clear code, label, category and show message. Network errors do not clear.
     */
    function validateCodeWithApi(input) {
      const query = (input.value || "").trim();
      if (!query) return Promise.resolve();

      if (isCsvSource()) {
        const exact = findExactCatalogMatch(query, catalogCsvItems);
        if (exact) {
          selectCatalogItem(input, exact);
          return Promise.resolve();
        }
        clearCodeAndRelated(input);
        alert("Product code not found. Please select a code from the list.");
        return Promise.resolve();
      }

      return fetchMergedCatalog(query, { resultLimit: 50 })
        .then((outcome) => {
          const exact = findExactCatalogMatch(query, outcome.results);
          if (outcome.errors.length) {
            console.error("validateCodeWithApi failed:", outcome.errors[0].error);
            showCatalogApiError(formatCatalogErrors(outcome.errors));
            if (exact) selectCatalogItem(input, exact);
            return;
          }
          clearCatalogApiError();
          if (exact) {
            selectCatalogItem(input, exact);
            return;
          }
          clearCodeAndRelated(input);
          alert("Product code not found. Please select a code from the list.");
        })
        .catch((err) => {
          console.error("validateCodeWithApi failed:", err);
          showCatalogApiError(err && err.message ? err.message : "Catalog API request failed.");
          // Do not clear on network error
        });
    }

    function clearCodeAndRelated(input) {
      const rowOrFieldset = input.closest("fieldset") || input.closest("tr");
      if (!rowOrFieldset) return;
      const codeInput = rowOrFieldset.querySelector("input[name=bom]");
      const labelInput = rowOrFieldset.querySelector("input[name=bom_label]");
      const categoryInput = rowOrFieldset.querySelector("input[name=bom_category]");
      if (codeInput) codeInput.value = "";
      if (labelInput) labelInput.value = "";
      if (categoryInput) categoryInput.value = "";
      const form = rowOrFieldset.closest("form");
      if (form && typeof setDirty === "function") setDirty(form);
      const block = rowOrFieldset.closest(".attributes-block");
      if (block && typeof updateBlockSummary === "function") updateBlockSummary(block);
    }

    const VALIDATE_CODE_BLUR_DELAY_MS = 220;

    /**
     * Call from code input onblur: after a short delay (so dropdown click is processed), validate code.
     * Skipped if setting "Validate product codes" is off.
     */
    function validateCodeOnBlur(input) {
      if (freeEditMode) return;
      if (!validateCodesAgainstCatalog) return;
      if (validateCodeBlurTimer) clearTimeout(validateCodeBlurTimer);
      validateCodeBlurTimer = setTimeout(() => {
        validateCodeBlurTimer = null;
        validateCodeWithApi(input);
      }, VALIDATE_CODE_BLUR_DELAY_MS);
    }
    let validateCodeBlurTimer = null;

    window.validateCodeOnBlur = validateCodeOnBlur;
    window.searchCatalogViaApi = searchCatalogViaApi;
    window.hideCatalogDropdown = hideCatalogDropdown;

    (function requestCatalogSettings() {
      if (typeof sketchup !== "undefined" && sketchup.get_catalog_settings) sketchup.get_catalog_settings();
    })();
