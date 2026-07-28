(function () {
    const SIDEBAR_WIDTH = "300px";

    // Reserve space for the sidebar so main content is not covered
    const style = document.createElement("style");
    style.id = "su-dev-overlay-style";
    style.textContent = "#su-dev-overlay.visible ~ * { margin-right: 10px; } body.su-dev-visible { margin-right: " + SIDEBAR_WIDTH + "; }";
    document.head.appendChild(style);

    function setBodyMargin(visible) {
      document.body.classList.toggle("su-dev-visible", visible);
    }

    // --- UI (right sidebar) ---------------------------------------------------
    const wrap = document.createElement("div");
    wrap.id = "su-dev-overlay";
    wrap.className = "visible";
    wrap.style.cssText = [
      "position:fixed","top:0","right:0","bottom:0","width:" + SIDEBAR_WIDTH,
      "background:#111","color:#0f0","font:12px monospace","z-index:99999",
      "border-left:1px solid #333","display:flex","flex-direction:column",
      "box-sizing:border-box"
    ].join(";");
    wrap.style.display = "flex";

    const bar = document.createElement("div");
    bar.style.cssText = "display:flex;gap:8px;align-items:center;padding:6px;border-bottom:1px solid #222;flex-shrink:0;";

    const btnRun = document.createElement("button");
    btnRun.textContent = "Run";
    btnRun.style.cssText = "padding:2px 10px;";

    const btnClear = document.createElement("button");
    btnClear.textContent = "Clear";
    btnClear.style.cssText = "padding:2px 10px;";

    const hint = document.createElement("div");
    hint.style.cssText = "opacity:.75;font-size:11px;";
    hint.textContent = "Ctrl+Enter: Run | Esc: toggle | ↑/↓: history";

    bar.append(btnRun, btnClear, hint);

    const input = document.createElement("textarea");
    input.spellcheck = false;
    input.style.cssText = [
      "width:100%","box-sizing:border-box","padding:8px",
      "border:0","outline:0","resize:none","min-height:60px",
      "background:#0b0b0b","color:#d6ffd6","flex-shrink:0"
    ].join(";");

    const out = document.createElement("pre");
    out.style.cssText = "margin:0;padding:8px;overflow:auto;flex:1;min-height:0;white-space:pre-wrap;";

    wrap.append(bar, input, out);
    document.body.appendChild(wrap);
    setBodyMargin(true);
  
    // --- logger ---------------------------------------------------------------
    const write = (type, msg) => {
      const line = `[${type}] ${msg}\n`;
      out.textContent += line;
      out.scrollTop = out.scrollHeight;
    };
  
    const safe = (v) => {
      if (typeof v === "string") return v;
      try { return JSON.stringify(v, null, 2); } catch { return String(v); }
    };
  
    ["log","warn","error"].forEach(k => {
      const old = console[k];
      console[k] = function (...args) {
        write(k, args.map(safe).join(" "));
        if (old) old.apply(console, args);
      };
    });
  
    window.addEventListener("error", (e) => write("error", `${e.message} @ ${e.filename}:${e.lineno}`));
    window.addEventListener("unhandledrejection", (e) => write("promise", safe(e.reason)));
  
    // --- REPL runner (eval) ---------------------------------------------------
    const hist = [];
    let histIdx = -1;
  
    async function run(code) {
      const trimmed = (code || "").trim();
      if (!trimmed) return;
      hist.push(trimmed);
      histIdx = hist.length;
  
      write("js>", trimmed);
  
      try {
        // Rulează în contextul paginii. Suportă și "await" prin async wrapper.
        const fn = new Function(`return (async () => { ${trimmed} })();`);
        const res = await fn();
        if (res !== undefined) write("res", safe(res));
      } catch (err) {
        write("err", err && err.stack ? err.stack : String(err));
      }
    }
  
    btnRun.onclick = () => run(input.value);
    btnClear.onclick = () => { out.textContent = ""; };
  
    // Shortcuts: Ctrl+Enter = run, Esc = toggle, Up/Down = history
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") {
        const visible = wrap.style.display === "none";
        wrap.style.display = visible ? "flex" : "none";
        wrap.classList.toggle("visible", visible);
        setBodyMargin(visible);
        return;
      }
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        run(input.value);
        return;
      }
      if (e.key === "ArrowUp" && document.activeElement === input) {
        if (hist.length) {
          histIdx = Math.max(0, histIdx - 1);
          input.value = hist[histIdx] || "";
          e.preventDefault();
        }
        return;
      }
      if (e.key === "ArrowDown" && document.activeElement === input) {
        if (hist.length) {
          histIdx = Math.min(hist.length, histIdx + 1);
          input.value = hist[histIdx] || "";
          e.preventDefault();
        }
      }
    });
  
    write("info", "Dev overlay ready.");
  })();
  