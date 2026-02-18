/**
 * Lightweight CSV parser — no dependencies.
 * Handles quoted fields, doubled quotes, and optional UTF-8 BOM.
 */

(function (global) {
  "use strict";

  function parseLine(line) {
    const row = [];
    let cell = "";
    let inQuotes = false;
    for (let i = 0; i < line.length; i++) {
      const c = line[i];
      if (inQuotes) {
        if (c === '"') {
          if (line[i + 1] === '"') {
            cell += '"';
            i += 1;
          } else {
            inQuotes = false;
          }
        } else {
          cell += c;
        }
      } else if (c === '"') {
        inQuotes = true;
      } else if (c === ",") {
        row.push(cell);
        cell = "";
      } else {
        cell += c;
      }
    }
    row.push(cell);
    return row;
  }

  /**
   * Parse CSV string into array of arrays (rows of cells).
   * @param {string} text - Raw CSV string (can include BOM).
   * @returns {string[][]}
   */
  function parse(text) {
    if (typeof text !== "string") return [];
    const s = text.replace(/^\uFEFF/, "");
    const lines = s.split(/\r\n|\r|\n/).map(function (l) { return l.trim(); });
    return lines.filter(Boolean).map(parseLine);
  }

  /**
   * Parse CSV string into array of objects using first row as keys.
   * @param {string} text - Raw CSV string.
   * @returns {{ [key: string]: string }[]}
   */
  function parseWithHeaders(text) {
    const rows = parse(text);
    if (rows.length === 0) return [];
    const headers = rows[0];
    return rows.slice(1).map(function (row) {
      const obj = {};
      headers.forEach(function (h, i) {
        obj[h] = row[i] !== undefined ? row[i] : "";
      });
      return obj;
    });
  }

  /**
   * Fetch CSV from URL and parse. Uses fetch(); works in browser only.
   * @param {string} url - URL to fetch (same-origin or CORS-enabled).
   * @param {{ headers?: boolean }} [opts] - If opts.headers === true, return array of objects (first row = keys).
   * @returns {Promise<string[][]|Object[]>}
   */
  function parseFromUrl(url, opts) {
    const withHeaders = opts && opts.headers === true;
    return fetch(url)
      .then(function (res) {
        if (!res.ok) throw new Error("CSV fetch failed: " + res.status + " " + res.statusText);
        return res.text();
      })
      .then(function (text) {
        return withHeaders ? parseWithHeaders(text) : parse(text);
      });
  }

  if (typeof module !== "undefined" && module.exports) {
    module.exports = { parse, parseWithHeaders, parseFromUrl };
  } else {
    global.CSV = { parse, parseWithHeaders, parseFromUrl };
  }
})(typeof window !== "undefined" ? window : this);
