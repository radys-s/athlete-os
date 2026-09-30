// Acquire exclusive storage ownership before loading any Flutter code.
(function () {
  function blocked(message) {
    var cover = document.createElement('div');
    cover.setAttribute('role', 'alert');
    cover.style.cssText = 'position:fixed;inset:0;background:#101510;color:#e8ece5;' +
      'font:17px sans-serif;display:flex;align-items:center;justify-content:center;' +
      'text-align:center;padding:24px';
    cover.textContent = message;
    document.body.appendChild(cover);
  }
  function start() {
    var script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    script.async = true;
    script.onerror = function () {
      blocked('Aplikaci se nepodařilo načíst. Obnov stránku po připojení k internetu.');
    };
    document.body.appendChild(script);
  }
  if (!navigator.locks) {
    blocked('Tento prohlížeč nepodporuje bezpečné sdílení úložiště. ' +
      'Použij aktuální prohlížeč přes HTTPS nebo Android aplikaci.');
    return;
  }
  navigator.locks.request('athlete-os-tab', { ifAvailable: true }, function (lock) {
    if (!lock) {
      blocked('Athlete OS je otevřený v jiném okně. Zavři ho a načti tuto stránku znovu.');
      return;
    }
    start();
    // The browser releases the lock when the owning document closes.
    return new Promise(function () {});
  }).catch(function () {
    blocked('Nepodařilo se získat bezpečný přístup k úložišti. Obnov stránku.');
  });
})();
