const $ = (sel, ctx = document) => {
    const els = typeof sel === "string"
      ? [...ctx.querySelectorAll(sel)]
      : sel instanceof Element || sel === window || sel === document
        ? [sel]
        : [...sel];

    const api = {
      els,
      on: (ev, fn) => (els.forEach(e => e.addEventListener(ev, fn)), api),
      off: (ev, fn) => (els.forEach(e => e.removeEventListener(ev, fn)), api),
      addClass: c => (els.forEach(e => e.classList.add(c)), api),
      removeClass: c => (els.forEach(e => e.classList.remove(c)), api),
      toggleClass: c => (els.forEach(e => e.classList.toggle(c)), api),
      attr: (k, v) => v === undefined
        ? els[0]?.getAttribute(k)
        : (els.forEach(e => e.setAttribute(k, v)), api),
      css: (k, v) => v === undefined
        ? getComputedStyle(els[0] || {}).getPropertyValue(k)
        : (els.forEach(e => e.style[k] = v), api),
      html: v => v === undefined
        ? els[0]?.innerHTML
        : (els.forEach(e => e.innerHTML = v), api),
      text: v => v === undefined
        ? els[0]?.textContent
        : (els.forEach(e => e.textContent = v), api),
      val: v => v === undefined
        ? els[0]?.value
        : (els.forEach(e => e.value = v), api),
      append: child => (els.forEach(e =>
        e.append(child instanceof Element ? child : document.createRange().createContextualFragment(child))
      ), api),
      parent: () => (els.forEach(e => e.parentElement), api),
      remove: () => (els.forEach(e => e.remove()), api),
      each: fn => (els.forEach((e,i) => fn.call(e,e,i)), api)
    };

    return api;
  };