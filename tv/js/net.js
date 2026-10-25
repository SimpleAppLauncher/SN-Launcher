/* Small XHR wrapper. XHR, not fetch: Tizen web apps run on older Chromium
   builds where promise-based fetch exists but AbortController/timeout support
   is inconsistent. XHR.timeout has worked on every TV browser we care about. */
(function () {
  'use strict';

  function request(method, url, body, timeoutMs, done) {
    var xhr = new XMLHttpRequest();
    var finished = false;
    var timer = null;

    function finish(err, data, status) {
      if (finished) return;
      finished = true;
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      done(err, data, status);
    }

    try {
      xhr.open(method, url, true);
      xhr.timeout = timeoutMs || 9000;
      xhr.setRequestHeader('Accept', 'application/json');
      if (body !== null && body !== undefined) {
        xhr.setRequestHeader('Content-Type', 'application/json');
      }
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== 4) return;
        if (xhr.status === 0) {
          finish({ code: 'network', message: 'Network request failed' }, null, 0);
          return;
        }
        var text = xhr.responseText || '';
        var parsed = null;
        if (text) {
          try { parsed = JSON.parse(text); } catch (err) {
            // A non-2xx answer is an HTTP failure first, even when its body is
            // plain text. Reporting it as bad JSON would blame the wrong side.
            if (xhr.status < 200 || xhr.status >= 300) {
              finish({ code: 'http', message: 'Server answered ' + xhr.status, status: xhr.status }, null, xhr.status);
              return;
            }
            finish({ code: 'json', message: 'The server sent something that is not JSON' }, null, xhr.status);
            return;
          }
        }
        if (xhr.status < 200 || xhr.status >= 300) {
          finish({ code: 'http', message: 'Server answered ' + xhr.status, status: xhr.status }, parsed, xhr.status);
          return;
        }
        finish(null, parsed, xhr.status);
      };
      xhr.onerror = function () {
        finish({ code: 'network', message: 'Could not reach the server' }, null, 0);
      };
      xhr.ontimeout = function () {
        finish({ code: 'timeout', message: 'The server did not answer in time' }, null, 0);
      };
      xhr.onabort = function () {
        finish({ code: 'abort', message: 'Request cancelled' }, null, 0);
      };
      xhr.send(body === null || body === undefined ? null : JSON.stringify(body));

      // Belt and braces for engines that ignore XHR.timeout.
      timer = setTimeout(function () {
        try { xhr.abort(); } catch (err) { /* already closed */ }
        finish({ code: 'timeout', message: 'The server did not answer in time' }, null, 0);
      }, (timeoutMs || 9000) + 800);
    } catch (err) {
      finish({ code: 'exception', message: String(err && err.message ? err.message : err) }, null, 0);
    }
  }

  SN.net = {
    getJSON: function (url, timeoutMs, done) {
      request('GET', url, null, timeoutMs, done);
    },
    postJSON: function (url, body, timeoutMs, done) {
      request('POST', url, body, timeoutMs, done);
    }
  };
})();
