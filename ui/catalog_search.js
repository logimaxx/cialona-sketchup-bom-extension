let searchCatalogTimer = null;
    let catalogDropdownHideTimer = null;
    const SEARCH_DEBOUNCE_MS = 300;
    const MAX_RESULTS = 20;
    let catalog = [];



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

    function selectCatalogItem(input, item) {
      const $fieldSet = $(input).parents("fieldset");
      $fieldSet.find("input[name=bom]").val(item.code || "");
      $fieldSet.find("input[name=bom_label]").val(item.name || "");
      $fieldSet.find("input[name=bom_category]").val(item.category || "");
      $fieldSet.find("select[name=bom_uom]").val(item.unit || "");

      const fieldset = input.closest("fieldset");
      input.value = item.code || "";
      const labelInput = fieldset.querySelector("input[name=bom_label]");
      if (labelInput) labelInput.value = item.name || "";
      const categoryInput = fieldset.querySelector("input[name=bom_category]");
      if (categoryInput) categoryInput.value = item.category || "";
      const uomSelect = fieldset.querySelector("select[name=bom_uom]");
      if (uomSelect && item.unit) {
        const opt = [...uomSelect.options].find((o) => o.value === item.unit);
        if (opt) uomSelect.value = item.unit;
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

    CSV.parseFromUrl("../schema/catalog.csv", { headers: true }).then((data) => {
      catalog = data;
    });