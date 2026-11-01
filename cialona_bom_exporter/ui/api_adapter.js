(function (global) {
  "use strict";

  function clone(value) {
    return value == null ? value : JSON.parse(JSON.stringify(value));
  }

  function parse(spec, fallback) {
    if (!spec) return clone(fallback || {});
    if (typeof spec === "object") return clone(spec);
    try { return JSON.parse(spec); } catch (e) {
      throw new Error("Invalid API profile JSON: " + e.message);
    }
  }

  function parts(path) {
    if (!path) return [];
    return String(path).replace(/\[(\d+)\]/g, ".$1").split(".").filter(Boolean);
  }

  function get(source, path, fallback) {
    var current = source;
    var keys = parts(path);
    for (var i = 0; i < keys.length; i++) {
      if (current == null || !Object.prototype.hasOwnProperty.call(Object(current), keys[i])) return fallback;
      current = current[keys[i]];
    }
    return current == null ? fallback : current;
  }

  function set(target, path, value) {
    var keys = parts(path);
    if (!keys.length) return value;
    var current = target;
    for (var i = 0; i < keys.length - 1; i++) {
      if (!current[keys[i]] || typeof current[keys[i]] !== "object") current[keys[i]] = {};
      current = current[keys[i]];
    }
    current[keys[keys.length - 1]] = value;
    return target;
  }

  function mapFields(item, fields) {
    var result = {};
    Object.keys(fields || {}).forEach(function (name) {
      result[name] = get(item, fields[name], "");
    });
    return result;
  }

  function addQuery(url, name, value) {
    if (!name || value == null || value === "") return url;
    return url + (url.indexOf("?") >= 0 ? "&" : "?") + encodeURIComponent(name) + "=" + encodeURIComponent(value);
  }

  function interpolate(value, variables) {
    return String(value || "").replace(/\{\{\s*([\w.]+)\s*\}\}/g, function (_, path) {
      var found = get(variables, path, "");
      return path === "import_url" || path === "offer_lines_url" ? String(found || "") : encodeURIComponent(found == null ? "" : found);
    });
  }

  function request(url, spec, payload, credentials, variables) {
    var cfg = spec || {};
    var finalUrl = interpolate(url, variables || {});
    var headers = Object.assign({}, cfg.headers || {});
    var body = clone(payload || {});
    var auth = cfg.auth || {};
    var secret = credentials && credentials.api_key;
    if (secret && auth.location === "header") headers[auth.name || "Authorization"] = (auth.prefix || "") + secret;
    else if (secret && auth.location === "body") set(body, auth.name || "apiKey", secret);
    else if (secret && auth.location !== "none") finalUrl = addQuery(finalUrl, auth.name || "apiKey", (auth.prefix || "") + secret);

    var method = String(cfg.method || "POST").toUpperCase();
    var options = { method: method, headers: headers };
    if (method !== "GET" && method !== "HEAD") {
      if (!headers["Content-Type"]) headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    } else {
      Object.keys(body || {}).forEach(function (key) { finalUrl = addQuery(finalUrl, key, body[key]); });
    }

    return fetch(finalUrl, options).then(function (response) {
      return response.text().then(function (text) {
        var data = null;
        try { data = text ? JSON.parse(text) : {}; } catch (_) { data = null; }
        if (!response.ok) {
          var errorPaths = cfg.error_paths || ["message", "error", "statusMessage", "scriptResult.message"];
          var detail = "";
          for (var i = 0; i < errorPaths.length && !detail; i++) detail = get(data, errorPaths[i], "");
          if (!detail && text) detail = text.slice(0, 200);
          throw new Error("HTTP " + response.status + " " + (response.statusText || "") + (detail ? " — " + detail : ""));
        }
        return data != null ? data : text;
      });
    });
  }

  global.ApiAdapter = { parse: parse, get: get, set: set, mapFields: mapFields, request: request, interpolate: interpolate };
})(window);
