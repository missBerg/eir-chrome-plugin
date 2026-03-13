(function installEirKantaNetworkProbe() {
  if (window.__eirKantaNetworkProbeInstalled) {
    return;
  }
  window.__eirKantaNetworkProbeInstalled = true;

  const SOURCE = 'eir-kanta-network-probe';
  const MAX_BODY_CHARS = 2_000_000;
  let requestCounter = 0;

  function post(payload) {
    window.postMessage({
      source: SOURCE,
      type: 'network-record',
      payload
    }, '*');
  }

  function nextRequestId(prefix) {
    requestCounter += 1;
    return `${prefix}-${Date.now()}-${requestCounter}`;
  }

  function headersToArray(headers) {
    if (!headers) {
      return [];
    }

    if (headers instanceof Headers) {
      return Array.from(headers.entries()).map(([name, value]) => ({ name, value }));
    }

    if (Array.isArray(headers)) {
      return headers.map(([name, value]) => ({ name, value }));
    }

    return Object.entries(headers).map(([name, value]) => ({ name, value }));
  }

  async function readBody(body, contentType) {
    if (body === undefined || body === null || body === '') {
      return { body: '', truncated: false };
    }

    if (typeof body === 'string') {
      return trimBody(body);
    }

    if (typeof URLSearchParams !== 'undefined' && body instanceof URLSearchParams) {
      return trimBody(body.toString());
    }

    if (typeof FormData !== 'undefined' && body instanceof FormData) {
      const formEntries = [];
      for (const [name, value] of body.entries()) {
        formEntries.push([name, typeof value === 'string' ? value : `[binary:${value.name || 'blob'}]`]);
      }
      return trimBody(JSON.stringify(formEntries));
    }

    if (typeof Blob !== 'undefined' && body instanceof Blob) {
      if (!isTextualContentType(contentType || body.type || '')) {
        return { body: `<blob:${body.type || 'unknown'}:${body.size}>`, truncated: false };
      }
      return trimBody(await body.text());
    }

    if (typeof ArrayBuffer !== 'undefined' && body instanceof ArrayBuffer) {
      return { body: `<array-buffer:${body.byteLength}>`, truncated: false };
    }

    if (ArrayBuffer.isView(body)) {
      return { body: `<typed-array:${body.byteLength}>`, truncated: false };
    }

    try {
      return trimBody(JSON.stringify(body));
    } catch (error) {
      return { body: `<unreadable-body:${Object.prototype.toString.call(body)}>`, truncated: false };
    }
  }

  function trimBody(text) {
    const normalized = String(text);
    if (normalized.length <= MAX_BODY_CHARS) {
      return { body: normalized, truncated: false };
    }
    return {
      body: `${normalized.slice(0, MAX_BODY_CHARS)}\n/* truncated */`,
      truncated: true
    };
  }

  function isTextualContentType(contentType) {
    return !contentType || /(json|text|xml|html|javascript|graphql|form-urlencoded)/i.test(String(contentType));
  }

  async function readResponseBody(response) {
    const contentType = response.headers.get('content-type') || '';
    if (!isTextualContentType(contentType)) {
      return { body: `<non-text-response:${contentType || 'unknown'}>`, truncated: false };
    }

    try {
      return trimBody(await response.clone().text());
    } catch (error) {
      return { body: `<unreadable-response:${error.message}>`, truncated: false };
    }
  }

  const originalFetch = window.fetch;
  window.fetch = async function patchedFetch(input, init) {
    const requestId = nextRequestId('fetch');
    const startedAt = Date.now();
    const request = input instanceof Request ? input : null;
    const requestUrl = request ? request.url : String(input);
    const requestMethod = (init && init.method) || (request && request.method) || 'GET';
    const requestHeaders = headersToArray((init && init.headers) || (request && request.headers) || []);
    const requestContentType = requestHeaders.find(header => header.name.toLowerCase() === 'content-type')?.value || '';
    let requestBodyResult = { body: '', truncated: false };

    try {
      if (request && request.method && request.method.toUpperCase() !== 'GET' && request.method.toUpperCase() !== 'HEAD') {
        requestBodyResult = await readBody(await request.clone().text(), requestContentType);
      } else if (init && init.body) {
        requestBodyResult = await readBody(init.body, requestContentType);
      }
    } catch (error) {
      requestBodyResult = { body: `<request-body-read-failed:${error.message}>`, truncated: false };
    }

    try {
      const response = await originalFetch.apply(this, arguments);
      const responseBodyResult = await readResponseBody(response);
      post({
        requestId,
        transport: 'fetch',
        phase: 'complete',
        capturedAt: new Date().toISOString(),
        pageUrl: window.location.href,
        url: requestUrl,
        method: requestMethod,
        status: response.status,
        ok: response.ok,
        durationMs: Date.now() - startedAt,
        requestHeaders,
        responseHeaders: headersToArray(response.headers),
        requestBody: requestBodyResult.body,
        requestBodyTruncated: requestBodyResult.truncated,
        responseBody: responseBodyResult.body,
        responseBodyTruncated: responseBodyResult.truncated,
        requestContentType,
        responseContentType: response.headers.get('content-type') || '',
        initiator: 'window.fetch'
      });
      return response;
    } catch (error) {
      post({
        requestId,
        transport: 'fetch',
        phase: 'error',
        capturedAt: new Date().toISOString(),
        pageUrl: window.location.href,
        url: requestUrl,
        method: requestMethod,
        durationMs: Date.now() - startedAt,
        requestHeaders,
        requestBody: requestBodyResult.body,
        requestBodyTruncated: requestBodyResult.truncated,
        requestContentType,
        error: error && error.message ? error.message : String(error),
        initiator: 'window.fetch'
      });
      throw error;
    }
  };

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;
  const originalSetRequestHeader = XMLHttpRequest.prototype.setRequestHeader;

  XMLHttpRequest.prototype.open = function patchedOpen(method, url) {
    this.__eirKantaCapture = {
      requestId: nextRequestId('xhr'),
      startedAt: Date.now(),
      method: method || 'GET',
      url: url || '',
      headers: []
    };
    return originalOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.setRequestHeader = function patchedSetRequestHeader(name, value) {
    if (this.__eirKantaCapture) {
      this.__eirKantaCapture.headers.push({ name, value });
    }
    return originalSetRequestHeader.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function patchedSend(body) {
    const capture = this.__eirKantaCapture || {
      requestId: nextRequestId('xhr'),
      startedAt: Date.now(),
      method: 'GET',
      url: '',
      headers: []
    };

    const contentType = capture.headers.find(header => String(header.name).toLowerCase() === 'content-type')?.value || '';

    readBody(body, contentType).then(bodyResult => {
      capture.requestBody = bodyResult.body;
      capture.requestBodyTruncated = bodyResult.truncated;
    }).catch(error => {
      capture.requestBody = `<request-body-read-failed:${error.message}>`;
      capture.requestBodyTruncated = false;
    });

    this.addEventListener('loadend', () => {
      const responseHeadersRaw = this.getAllResponseHeaders();
      const responseHeaders = responseHeadersRaw
        .trim()
        .split(/[\r\n]+/)
        .filter(Boolean)
        .map(line => {
          const separator = line.indexOf(':');
          return {
            name: separator >= 0 ? line.slice(0, separator).trim() : line.trim(),
            value: separator >= 0 ? line.slice(separator + 1).trim() : ''
          };
        });

      let responseBody = '';
      let responseBodyTruncated = false;
      try {
        if (this.responseType === '' || this.responseType === 'text') {
          const trimmed = trimBody(this.responseText || '');
          responseBody = trimmed.body;
          responseBodyTruncated = trimmed.truncated;
        } else if (this.responseType === 'json') {
          const trimmed = trimBody(JSON.stringify(this.response));
          responseBody = trimmed.body;
          responseBodyTruncated = trimmed.truncated;
        } else {
          responseBody = `<xhr-response-type:${this.responseType || 'unknown'}>`;
        }
      } catch (error) {
        responseBody = `<response-read-failed:${error.message}>`;
      }

      post({
        requestId: capture.requestId,
        transport: 'xhr',
        phase: 'complete',
        capturedAt: new Date().toISOString(),
        pageUrl: window.location.href,
        url: capture.url,
        method: capture.method,
        status: this.status,
        ok: this.status >= 200 && this.status < 400,
        durationMs: Date.now() - capture.startedAt,
        requestHeaders: capture.headers,
        responseHeaders,
        requestBody: capture.requestBody || '',
        requestBodyTruncated: Boolean(capture.requestBodyTruncated),
        responseBody,
        responseBodyTruncated,
        requestContentType: contentType,
        responseContentType: responseHeaders.find(header => header.name.toLowerCase() === 'content-type')?.value || '',
        initiator: 'XMLHttpRequest'
      });
    }, { once: true });

    return originalSend.apply(this, arguments);
  };
})();
