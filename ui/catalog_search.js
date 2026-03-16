let searchCatalogTimer = null;
    let catalogDropdownHideTimer = null;
    const SEARCH_DEBOUNCE_MS = 300;
    const MAX_RESULTS = 20;
    const DEFAULT_CATALOG_API_URL = "https://jt.cialona.nl/otto/receiver/CI_Project.fmp12/query_products";
    const DEFAULT_CATALOG_API_KEY = "dk_UAZdr9LKPS7lxEDwjbgYqeIfr0EAnPQ6";
    const CATALOG_API_RESULT_LIMIT = 10;
    let catalog = [];
    let catalogApiUrl = "";
    let catalogApiKey = "";

    let validateCodesAgainstCatalog = true;

    window.onCatalogSettings = function(data) {
      if (data) {
        catalogApiUrl = (data.catalog_api_url || "").trim();
        catalogApiKey = (data.catalog_api_key || "").trim();
        validateCodesAgainstCatalog = data.catalog_validate_codes !== false && data.catalog_validate_codes !== "false";
      }
    };

    function getCatalogApiUrl() {
      return catalogApiUrl || DEFAULT_CATALOG_API_URL;
    }
    function getCatalogApiKey() {
      return catalogApiKey || DEFAULT_CATALOG_API_KEY;
    }



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
        li.dataset.code = item.code || "";
        li.dataset.name = item.name || "";
        li.dataset.unit = item.unit || "";
        li.addEventListener("mousedown", (e) => {
          e.preventDefault();
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
     * Map API unit strings to the attributes form UOM values (pcs, m2, mtr, custom).
     * API uses e.g. "m2", "stuks", "mtr." (linear meter).
     */
    function normalizeApiUnitToFormUom(apiUnit) {
      if (!apiUnit || typeof apiUnit !== "string") return "";
      const u = apiUnit.trim().toLowerCase();
      if (u === "m2") return "m2";
      if (u === "stuks" || u === "stuk" || u === "pcs" || u === "pieces") return "pcs";
      if (u === "mtr." || u === "mtr" || u === "m" || u === "meter" || u === "meters" || u === "linear meter") return "mtr";
      return u || "";
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
      const measureSelect = rowOrFieldset.querySelector("select[name=bom_measure]");
      if (measureSelect) measureSelect.value = "";
      if (uomSelect && item.unit) {
        const formUom = normalizeApiUnitToFormUom(item.unit);
        if (formUom) {
          const opt = [...uomSelect.options].find((o) => o.value === formUom);
          if (opt) uomSelect.value = formUom;
        }
      }
      if (typeof window.refillMeasureOptionsForForm === "function") {
        window.refillMeasureOptionsForForm(rowOrFieldset);
      }
      if (typeof $ !== "undefined") {
        $(rowOrFieldset).find("input[name=bom]").val(item.code || "");
        $(rowOrFieldset).find("input[name=bom_label]").val(item.name || "");
        $(rowOrFieldset).find("input[name=bom_category]").val(item.category || "");
        var formUom = item.unit ? normalizeApiUnitToFormUom(item.unit) : "";
        $(rowOrFieldset).find("select[name=bom_uom]").val(formUom || "");
        if (measureSelect) $(measureSelect).val("");
      }
    }

    function hideCatalogDropdown() {
      if (catalogDropdownHideTimer) clearTimeout(catalogDropdownHideTimer);
      catalogDropdownHideTimer = setTimeout(() => {
        document.querySelectorAll(".catalog-dropdown").forEach((ul) => { ul.style.display = "none"; });
        catalogDropdownHideTimer = null;
      }, 150);
    }

    function searchCatalog(input) {
      if (searchCatalogTimer) clearTimeout(searchCatalogTimer);
      searchCatalogTimer = setTimeout(() => {
        searchCatalogTimer = null;
        const q = (input.value || "").trim().toLowerCase();
        const results = q === ""
          ? []
          : catalog.filter(
              (item) =>
                (item.code && item.code.toLowerCase().includes(q)) ||
                (item.name && item.name.toLowerCase().includes(q))
            );
        showCatalogResults(input, results);
      }, SEARCH_DEBOUNCE_MS);
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
      const mapItem = opts.mapItem || ((item) => ({
        code: item.code,
        name: item.name,
        unit: item.unit,
        category: item.category
      }));

      const q = (query || "").trim();
      if (!q) return Promise.resolve([]);

      const url = apiUrl + (apiUrl.indexOf("?") >= 0 ? "&" : "?") + "apiKey=" + encodeURIComponent(apiKey);
      const body = JSON.stringify({ query: q, resultLimit: resultLimit });

      return fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: body
      })
        .then((res) => {
          if (!res.ok) throw new Error("Catalog API error: " + res.status + " " + res.statusText);
          return res.json();
        })
        .then((data) => {
          const rawList = (data.scriptResult && data.scriptResult.result)
            ? data.scriptResult.result
            : (Array.isArray(data) ? data : (data.results != null ? data.results : (data.data != null ? data.data : [])));
          return rawList.map(mapItem);
        });
    }

    /**
     * Search catalog by calling the external API.
     * @param {HTMLInputElement} input - The search input element (used to show results in its dropdown).
     * @param {Object} [options] - Optional overrides.
     * @returns {Promise<Array>} Resolves with normalized results shown in dropdown; rejects on fetch/parse error.
     */
    function searchCatalogViaApi(input, options) {
      const query = (input.value || "").trim();
      if (!query) {
        showCatalogResults(input, []);
        return Promise.resolve([]);
      }
      return fetchCatalogQuery(query, options)
        .then((results) => {
          showCatalogResults(input, results);
          return results;
        })
        .catch((err) => {
          console.error("searchCatalogViaApi failed:", err);
          showCatalogResults(input, []);
          throw err;
        });
    }

    /**
     * Validate that the current code input value exists in the catalog API (exact match).
     * If not found: clear code, label, category and show message. If found: optionally sync label/category from API.
     */
    function validateCodeWithApi(input) {
      const query = (input.value || "").trim();
      if (!query) return Promise.resolve();

      return fetchCatalogQuery(query, { resultLimit: 50 })
        .then((results) => {
          const exact = results.find((r) => (r.code || "").trim() === query);
          if (exact) {
            selectCatalogItem(input, exact);
            return;
          }
          clearCodeAndRelated(input);
          alert("Product code not found. Please select a code from the list.");
        })
        .catch((err) => {
          console.error("validateCodeWithApi failed:", err);
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
     * Call from code input onblur: after a short delay (so dropdown click is processed), validate code with API.
     * Only codes returned by the catalog API are allowed. Skipped if setting "Validate product codes" is off.
     */
    function validateCodeOnBlur(input) {
      if (!validateCodesAgainstCatalog) return;
      if (validateCodeBlurTimer) clearTimeout(validateCodeBlurTimer);
      validateCodeBlurTimer = setTimeout(() => {
        validateCodeBlurTimer = null;
        validateCodeWithApi(input);
      }, VALIDATE_CODE_BLUR_DELAY_MS);
    }
    let validateCodeBlurTimer = null;

    window.validateCodeOnBlur = validateCodeOnBlur;

    (function requestCatalogSettings() {
      if (typeof sketchup !== "undefined" && sketchup.get_catalog_settings) sketchup.get_catalog_settings();
    })();

    CSV.parseFromUrl("../schema/catalog.csv", { headers: true }).then((data) => {
      catalog = data;
    });