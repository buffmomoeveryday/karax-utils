## Small QoL for wrapping CDN / browser JS libraries.
##
##   loadCss("https://…/leaflet.css")
##   loadScript("https://…/leaflet.js").then(proc() = …)
##
## Prefer typed wrappers (`karax_utils/leaflet`) over raw `JsObject` in app code.

type
  JsPromise* = ref object

proc then*(p: JsPromise; cb: proc()) {.importjs: "#.then(#)".}

proc loadCss*(href: cstring) {.importjs: """
  (function(href) {
    if (document.querySelector('link[data-ku-href="'+href+'"]')) return;
    var l = document.createElement('link');
    l.rel = 'stylesheet';
    l.href = href;
    l.setAttribute('data-ku-href', href);
    document.head.appendChild(l);
  })(#)
""".}

proc loadScript*(src: cstring): JsPromise {.importjs: """
  (function(src) {
    return new Promise(function(resolve, reject) {
      var existing = document.querySelector('script[data-ku-src="'+src+'"]');
      if (existing) {
        if (existing.getAttribute('data-ku-loaded') === '1') resolve();
        else existing.addEventListener('load', function() { resolve(); });
        return;
      }
      var s = document.createElement('script');
      s.src = src;
      s.async = true;
      s.setAttribute('data-ku-src', src);
      s.onload = function() {
        s.setAttribute('data-ku-loaded', '1');
        resolve();
      };
      s.onerror = function(e) { reject(e); };
      document.head.appendChild(s);
    });
  })(#)
""".}
