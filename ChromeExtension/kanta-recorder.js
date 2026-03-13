const KANTA_RECORDER_STORAGE_KEY = 'kantaFlowRecorderSession';
const KANTA_RECORDER_PANEL_ID = 'kanta-flow-recorder-panel';
const KANTA_RECORDER_DB_NAME = 'eirKantaCapture';
const KANTA_RECORDER_DB_VERSION = 1;
const KANTA_RECORDER_ARTIFACTS_STORE = 'artifacts';
const KANTA_RECORDER_HOSTS = ['kanta.fi', 'suomi.fi'];
const KANTA_PROBE_SOURCE = 'eir-kanta-network-probe';
const KANTA_PANEL_REFRESH_MS = 250;
const KANTA_MAX_TEXT_BODY_CHARS = 2_000_000;
const KANTA_MAX_HTML_CHARS = 2_000_000;
const KANTA_PAGE_LABELS = {
  landing: 'Portal overview',
  prescriptions: 'Prescriptions',
  'health-records': 'Health records',
  visits: 'Visits',
  'imaging-index': 'Imaging',
  'imaging-detail': 'Imaging result',
  diagnoses: 'Diagnoses',
  'care-plan': 'Care plan',
  certificates: 'Certificates',
  'risk-information': 'Risk information',
  laboratory: 'Laboratory',
  'oral-health': 'Oral health',
  measurements: 'Measurements',
  referrals: 'Referrals',
  disclosures: 'Disclosures',
  vaccinations: 'Vaccinations',
  procedures: 'Procedures',
  unknown: 'Journal page'
};

let kantaRecorderPanel = null;
let kantaRecorderDbPromise = null;
let kantaRecorderWriteQueue = Promise.resolve();
let kantaRecorderRefreshTimer = null;

bootKantaRecorder();

function bootKantaRecorder() {
  if (!isSupportedKantaHost(window.location.hostname)) {
    return;
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeKantaRecorder, { once: true });
    return;
  }

  void initializeKantaRecorder();
}

async function initializeKantaRecorder() {
  createKantaRecorderPanel();
  installKantaRecorderListeners();
  installKantaNetworkProbe();
  await refreshKantaRecorderPanel();

  if (await isKantaRecorderActive()) {
    await appendKantaEvent('page-load', {
      url: sanitizeUrl(window.location.href),
      title: document.title || ''
    });
    await captureCurrentKantaPage('page-load');
  }
}

function isSupportedKantaHost(hostname) {
  const normalizedHostname = (hostname || '').toLowerCase();
  return KANTA_RECORDER_HOSTS.some(host => normalizedHostname === host || normalizedHostname.endsWith(`.${host}`));
}

function isSensitiveKantaPage() {
  const hostname = window.location.hostname.toLowerCase();
  const pathname = window.location.pathname.toLowerCase();

  return Boolean(
    hostname.endsWith('suomi.fi') ||
    hostname.startsWith('tunnistus.') ||
    pathname.includes('login') ||
    pathname.includes('auth') ||
    pathname.includes('tunnistus') ||
    document.querySelector('input[type="password"]') ||
    document.querySelector('input[autocomplete="current-password"]') ||
    document.querySelector('input[autocomplete="one-time-code"]')
  );
}

function isExtractableKantaPage() {
  const hostname = window.location.hostname.toLowerCase();
  return hostname === 'kansalainen.kanta.fi' && !isSensitiveKantaPage();
}

function isSensitiveUrl(rawUrl) {
  if (!rawUrl) {
    return false;
  }

  try {
    const url = new URL(rawUrl, window.location.href);
    const hostname = url.hostname.toLowerCase();
    const pathname = url.pathname.toLowerCase();
    const combined = `${hostname}${pathname}`;

    return (
      hostname.endsWith('suomi.fi') ||
      combined.includes('auth') ||
      combined.includes('login') ||
      combined.includes('token') ||
      combined.includes('oauth') ||
      combined.includes('saml') ||
      combined.includes('session') ||
      combined.includes('tunnistus')
    );
  } catch (error) {
    const normalized = String(rawUrl).toLowerCase();
    return ['auth', 'login', 'token', 'oauth', 'saml', 'session', 'tunnistus'].some(fragment => normalized.includes(fragment));
  }
}

function createKantaRecorderPanel() {
  if (document.getElementById(KANTA_RECORDER_PANEL_ID)) {
    kantaRecorderPanel = document.getElementById(KANTA_RECORDER_PANEL_ID);
    return;
  }

  const panel = document.createElement('aside');
  panel.id = KANTA_RECORDER_PANEL_ID;
  panel.className = 'kanta-recorder-panel';
  panel.innerHTML = `
    <div class="kanta-recorder-panel__header">
      <div>
        <div class="kanta-recorder-panel__eyebrow">Research Mode</div>
        <div class="kanta-recorder-panel__title">Kanta Capture Bundle</div>
      </div>
      <div id="kanta-recorder-status-badge" class="kanta-recorder-panel__badge kanta-recorder-panel__badge--idle">Idle</div>
    </div>
    <p class="kanta-recorder-panel__copy">
      Captures navigation, sanitized page snapshots, and fetch/XHR traffic so you can reconstruct the real data-delivery flow later.
    </p>
    <div class="kanta-recorder-panel__stats">
      <div class="kanta-recorder-panel__stat">
        <span class="kanta-recorder-panel__stat-label">Events</span>
        <strong id="kanta-recorder-events-count">0</strong>
      </div>
      <div class="kanta-recorder-panel__stat">
        <span class="kanta-recorder-panel__stat-label">Pages</span>
        <strong id="kanta-recorder-pages-count">0</strong>
      </div>
      <div class="kanta-recorder-panel__stat">
        <span class="kanta-recorder-panel__stat-label">Network</span>
        <strong id="kanta-recorder-network-count">0</strong>
      </div>
    </div>
    <div class="kanta-recorder-panel__actions">
      <button id="kanta-recorder-start" class="kanta-recorder-panel__button kanta-recorder-panel__button--primary" type="button">Start</button>
      <button id="kanta-recorder-stop" class="kanta-recorder-panel__button" type="button">Stop</button>
      <button id="kanta-recorder-capture" class="kanta-recorder-panel__button" type="button">Capture</button>
      <button id="kanta-recorder-download-page" class="kanta-recorder-panel__button kanta-recorder-panel__button--success" type="button">Download .eir</button>
      <button id="kanta-recorder-export" class="kanta-recorder-panel__button" type="button">Export</button>
      <button id="kanta-recorder-clear" class="kanta-recorder-panel__button kanta-recorder-panel__button--danger" type="button">Clear</button>
    </div>
    <div id="kanta-recorder-status-text" class="kanta-recorder-panel__footer">
      Not recording.
    </div>
  `;

  document.body.appendChild(panel);
  kantaRecorderPanel = panel;

  panel.querySelector('#kanta-recorder-start').addEventListener('click', () => void startKantaRecording());
  panel.querySelector('#kanta-recorder-stop').addEventListener('click', () => void stopKantaRecording());
  panel.querySelector('#kanta-recorder-capture').addEventListener('click', () => void captureCurrentKantaPage('manual-capture'));
  panel.querySelector('#kanta-recorder-download-page').addEventListener('click', () => void downloadCurrentKantaPageData());
  panel.querySelector('#kanta-recorder-export').addEventListener('click', () => void exportKantaRecording());
  panel.querySelector('#kanta-recorder-clear').addEventListener('click', () => void clearKantaRecording());
}

function installKantaRecorderListeners() {
  document.addEventListener('click', event => {
    void handleKantaClick(event);
  }, true);

  document.addEventListener('submit', event => {
    void handleKantaSubmit(event);
  }, true);

  window.addEventListener('hashchange', () => {
    void handleKantaNavigation('hashchange');
  });

  window.addEventListener('popstate', () => {
    void handleKantaNavigation('popstate');
  });

  window.addEventListener('message', event => {
    void handleKantaProbeMessage(event);
  });

  window.addEventListener('beforeunload', () => {
    void appendKantaEvent('page-unload', {
      url: sanitizeUrl(window.location.href),
      title: document.title || ''
    });
  });

  const originalPushState = history.pushState;
  history.pushState = function pushStateWrapper(...args) {
    const result = originalPushState.apply(this, args);
    void handleKantaNavigation('pushState');
    return result;
  };

  const originalReplaceState = history.replaceState;
  history.replaceState = function replaceStateWrapper(...args) {
    const result = originalReplaceState.apply(this, args);
    void handleKantaNavigation('replaceState');
    return result;
  };
}

function installKantaNetworkProbe() {
  if (document.documentElement.dataset.eirKantaProbeInjected === 'true') {
    return;
  }

  const script = document.createElement('script');
  script.src = chrome.runtime.getURL('kanta-network-probe.js');
  script.async = false;
  script.onload = () => {
    script.remove();
  };
  (document.head || document.documentElement).appendChild(script);
  document.documentElement.dataset.eirKantaProbeInjected = 'true';
}

async function handleKantaNavigation(source) {
  if (!await isKantaRecorderActive()) {
    return;
  }

  await appendKantaEvent('navigation', {
    source,
    url: sanitizeUrl(window.location.href),
    title: document.title || ''
  });
  await captureCurrentKantaPage(source);
}

async function handleKantaClick(event) {
  if (!await isKantaRecorderActive()) {
    return;
  }

  const targetElement = toKantaElement(event.target);
  if (!targetElement) {
    return;
  }

  if (targetElement.closest(`#${KANTA_RECORDER_PANEL_ID}`)) {
    return;
  }

  const describedElement = describeKantaElement(targetElement);
  if (!describedElement) {
    return;
  }

  await appendKantaEvent('click', {
    url: sanitizeUrl(window.location.href),
    title: document.title || '',
    element: describedElement
  });
}

async function handleKantaSubmit(event) {
  if (!await isKantaRecorderActive()) {
    return;
  }

  if (event.target.closest(`#${KANTA_RECORDER_PANEL_ID}`)) {
    return;
  }

  await appendKantaEvent('submit', {
    url: sanitizeUrl(window.location.href),
    title: document.title || '',
    form: summarizeKantaForm(event.target)
  });
}

async function handleKantaProbeMessage(event) {
  if (event.source !== window || !event.data || event.data.source !== KANTA_PROBE_SOURCE) {
    return;
  }

  if (!await isKantaRecorderActive()) {
    return;
  }

  if (event.data.type !== 'network-record' || !event.data.payload) {
    return;
  }

  const record = sanitizeKantaNetworkRecord(event.data.payload);
  await queueKantaRecorderWrite(async () => {
    const session = await getKantaRecorderSession();
    if (!session || session.status !== 'recording') {
      return;
    }

    await addKantaArtifact({
      sessionId: session.id,
      artifactType: 'network',
      capturedAt: record.capturedAt,
      data: record
    });
    scheduleKantaRecorderPanelRefresh();
  });
}

async function startKantaRecording() {
  const confirmed = window.confirm(
    'Start a local Kanta reverse-engineering capture?\n\n' +
    'This stores navigation steps, sanitized page HTML, and fetch/XHR request-response records in the browser until you export them.\n' +
    'Passwords, OTP values, cookies, and auth token values are still redacted.'
  );

  if (!confirmed) {
    return;
  }

  const previousSession = await getKantaRecorderSession();
  if (previousSession?.id) {
    await deleteKantaArtifactsForSession(previousSession.id);
  }

  const session = {
    id: `kanta-${Date.now()}`,
    portal: 'mykanta',
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    status: 'recording',
    exportFormat: 'capture-bundle-v2',
    redaction: {
      authCookies: 'removed',
      authHeaders: 'removed',
      loginFieldValues: 'removed',
      queryParamValues: 'removed',
      sensitiveRequestBodies: 'redacted'
    },
    environment: {
      userAgent: navigator.userAgent,
      language: navigator.language,
      platform: navigator.platform || 'unknown'
    }
  };

  await saveKantaRecorderSession(session);
  await appendKantaEvent('recording-started', {
    url: sanitizeUrl(window.location.href),
    title: document.title || ''
  });
  await captureCurrentKantaPage('recording-started');
}

async function stopKantaRecording() {
  await queueKantaRecorderWrite(async () => {
    const session = await getKantaRecorderSession();
    if (!session) {
      return;
    }

    session.status = 'stopped';
    session.updatedAt = new Date().toISOString();
    await saveKantaRecorderSession(session);
    await addKantaArtifact({
      sessionId: session.id,
      artifactType: 'event',
      capturedAt: new Date().toISOString(),
      data: {
        type: 'recording-stopped',
        url: sanitizeUrl(window.location.href),
        title: document.title || ''
      }
    });
    scheduleKantaRecorderPanelRefresh();
  });
}

async function clearKantaRecording() {
  const session = await getKantaRecorderSession();
  if (!session) {
    updateKantaRecorderPanel(null, emptyKantaRecorderCounts());
    return;
  }

  const confirmed = window.confirm('Clear the saved Kanta capture bundle from the browser?');
  if (!confirmed) {
    return;
  }

  await deleteKantaArtifactsForSession(session.id);
  await storageRemove(KANTA_RECORDER_STORAGE_KEY);
  updateKantaRecorderPanel(null, emptyKantaRecorderCounts());
}

async function exportKantaRecording() {
  const session = await getKantaRecorderSession();
  if (!session) {
    window.alert('No Kanta capture session found to export.');
    return;
  }

  const artifacts = await listKantaArtifactsForSession(session.id);
  if (artifacts.length === 0) {
    window.alert('The session has no captured artifacts yet.');
    return;
  }

  const counts = summarizeKantaArtifacts(artifacts);
  const manifest = {
    schemaVersion: '2.0',
    exportedAt: new Date().toISOString(),
    session,
    counts,
    currentPage: sanitizeUrl(window.location.href)
  };

  const eventLines = artifacts
    .filter(artifact => artifact.artifactType === 'event')
    .map(artifact => JSON.stringify({
      artifactId: artifact.id,
      capturedAt: artifact.capturedAt,
      ...artifact.data
    }));

  const networkLines = artifacts
    .filter(artifact => artifact.artifactType === 'network')
    .map(artifact => JSON.stringify({
      artifactId: artifact.id,
      capturedAt: artifact.capturedAt,
      ...artifact.data
    }));

  const files = [
    {
      filename: `${session.id}--manifest.json`,
      content: JSON.stringify(manifest, null, 2),
      mimeType: 'application/json;charset=utf-8'
    },
    {
      filename: `${session.id}--events.ndjson`,
      content: `${eventLines.join('\n')}${eventLines.length ? '\n' : ''}`,
      mimeType: 'application/x-ndjson;charset=utf-8'
    },
    {
      filename: `${session.id}--network.ndjson`,
      content: `${networkLines.join('\n')}${networkLines.length ? '\n' : ''}`,
      mimeType: 'application/x-ndjson;charset=utf-8'
    }
  ];

  const pageArtifacts = artifacts.filter(artifact => artifact.artifactType === 'page');
  pageArtifacts.forEach((artifact, index) => {
    const ordinal = String(index + 1).padStart(4, '0');
    const pageData = artifact.data;
    files.push({
      filename: `${session.id}--page-${ordinal}--meta.json`,
      content: JSON.stringify({
        artifactId: artifact.id,
        capturedAt: artifact.capturedAt,
        ...pageData,
        html: undefined
      }, null, 2),
      mimeType: 'application/json;charset=utf-8'
    });

    files.push({
      filename: `${session.id}--page-${ordinal}.html`,
      content: pageData.html || '<!-- empty -->',
      mimeType: 'text/html;charset=utf-8'
    });
  });

  if (files.length > 12) {
    const proceed = window.confirm(
      `Export ${files.length} files?\n\n` +
      'Chrome may ask you to allow multiple downloads for this site.'
    );
    if (!proceed) {
      return;
    }
  }

  for (let index = 0; index < files.length; index += 1) {
    const file = files[index];
    downloadKantaBlob(file.content, file.filename, file.mimeType);
    await delay(index < 3 ? 100 : 250);
  }

  session.updatedAt = new Date().toISOString();
  await saveKantaRecorderSession(session);
  scheduleKantaRecorderPanelRefresh();
}

async function downloadCurrentKantaPageData() {
  if (isSensitiveKantaPage()) {
    window.alert('The page extractor is only enabled on logged-in MyKanta data pages, not on authentication pages.');
    return;
  }

  const snapshot = buildKantaPageSnapshot('page-download');
  const extraction = extractStructuredKantaPage(snapshot);
  const eirData = buildKantaEirContent(snapshot, extraction);
  const eirYaml = convertKantaObjectToYAML(eirData);
  const filename = buildKantaPageDownloadFilename(extraction.pageType);
  downloadKantaBlob(eirYaml, filename, 'text/plain;charset=utf-8');

  const statusText = kantaRecorderPanel?.querySelector('#kanta-recorder-status-text');
  if (statusText) {
    statusText.textContent = `Downloaded ${extraction.pageType} as .eir.`;
  }
}

async function captureCurrentKantaPage(reason) {
  if (!await isKantaRecorderActive()) {
    return;
  }

  const snapshot = buildKantaPageSnapshot(reason);

  await queueKantaRecorderWrite(async () => {
    const session = await getKantaRecorderSession();
    if (!session || session.status !== 'recording') {
      return;
    }

    await addKantaArtifact({
      sessionId: session.id,
      artifactType: 'page',
      capturedAt: snapshot.capturedAt,
      data: snapshot
    });
    scheduleKantaRecorderPanelRefresh();
  });
}

function buildKantaPageSnapshot(reason) {
  const sensitive = isSensitiveKantaPage();

  return {
    reason,
    capturedAt: new Date().toISOString(),
    url: sanitizeUrl(window.location.href),
    title: document.title || '',
    referrer: sanitizeUrl(document.referrer || ''),
    hostname: window.location.hostname,
    pathname: window.location.pathname,
    sensitive,
    captureMode: sensitive ? 'sanitized-auth-html' : 'sanitized-html',
    documentLanguage: document.documentElement.lang || '',
    visibleText: limitText(document.body?.innerText || '', 40_000),
    forms: summarizeKantaForms(),
    links: summarizeKantaLinks(),
    resources: summarizeKantaResources(),
    storageSummary: summarizeKantaStorage(),
    pageOutline: buildKantaPageOutline(),
    html: sanitizeDocumentHtml()
  };
}

function extractStructuredKantaPage(snapshot) {
  const pageType = classifyKantaPage(snapshot.pathname, snapshot.title);
  const pageRoot = document.body;
  const navigation = extractKantaNavigation();
  const filters = extractKantaFilters();
  const tables = extractKantaTables();
  const detailFields = extractKantaDetailFields();
  const detailLinks = extractKantaDetailLinks();
  const headings = extractKantaHeadings();
  const summaryText = limitText(pageRoot?.innerText || '', 12000);

  return {
    pageType,
    title: snapshot.title,
    pathname: snapshot.pathname,
    breadcrumbs: extractKantaBreadcrumbs(),
    headings,
    navigation,
    filters,
    detailFields,
    tables,
    links: detailLinks,
    pageSummary: summaryText,
    extractedAt: new Date().toISOString()
  };
}

function classifyKantaPage(pathname, title) {
  const normalizedPath = String(pathname || '').toLowerCase();
  const normalizedTitle = String(title || '').toLowerCase();
  const combined = `${normalizedPath} ${normalizedTitle}`;

  const rules = [
    ['landing', ['palvelukuvaus']],
    ['prescriptions', ['yksilointiedothaku', 'recept']],
    ['health-records', ['terveystiedothaku', 'hälso- och sjukvårdsuppgifter']],
    ['visits', ['palvelutapahtumahaku', 'besök']],
    ['imaging-index', ['tutkimuksetkaikkirtghaku', 'bilddiagnostiska undersökningar']],
    ['imaging-detail', ['tutkimustuloksetrtghaku', 'resultat av bilddiagnostiska undersökningar']],
    ['diagnoses', ['diagnoositkoosteestahaku', 'diagnoser']],
    ['care-plan', ['terveysjahoitosuunnitelmahaku', 'hälso- och vårdplan']],
    ['certificates', ['laakarintodistuksethaku', 'intyg', 'utlåtanden']],
    ['risk-information', ['riskitiedothaku', 'kritisk riskinformation']],
    ['laboratory', ['tutkimuksetkaikkilabhaku', 'laboratorieundersökningar']],
    ['oral-health', ['suunterveydenhuollothaku', 'mun- och tandvård']],
    ['measurements', ['mittauksetkoosteestahaku', 'mätningar']],
    ['referrals', ['lahetteethaku', 'remisser']],
    ['disclosures', ['terveystietojenluovutuksethaku', 'utlämnande av hälso- och sjukvårdsuppgifter']],
    ['vaccinations', ['rokotuksetkoosteestahaku', 'vaccinationer']],
    ['procedures', ['toimenpiteetkoosteestahaku', 'åtgärder']]
  ];

  for (const [pageType, tokens] of rules) {
    if (tokens.some(token => combined.includes(token))) {
      return pageType;
    }
  }

  return 'unknown';
}

function extractKantaNavigation() {
  const navLinks = Array.from(document.querySelectorAll('form#naviForm a, #naviForm a'))
    .filter(link => (link.innerText || link.textContent || '').trim())
    .slice(0, 40);

  return navLinks.map(link => ({
    label: limitText(link.innerText || link.textContent || '', 120),
    href: sanitizeUrl(link.href),
    selector: buildCompactSelector(link)
  }));
}

function extractKantaBreadcrumbs() {
  return Array.from(document.querySelectorAll('form#trailForm a, #trailForm a, nav[aria-label*="breadcrumb" i] a'))
    .slice(0, 12)
    .map(link => ({
      label: limitText(link.innerText || link.textContent || '', 120),
      href: sanitizeUrl(link.href)
    }));
}

function extractKantaHeadings() {
  return Array.from(document.querySelectorAll('h1, h2, h3'))
    .slice(0, 20)
    .map(node => limitText(node.innerText || node.textContent || '', 200))
    .filter(Boolean);
}

function extractKantaFilters() {
  const forms = Array.from(document.forms)
    .filter(form => /haku|formhaku|search|filter/i.test(form.id || form.name || buildCompactSelector(form)));

  const extracted = [];
  forms.slice(0, 8).forEach(form => {
    const controls = Array.from(form.querySelectorAll('input, select, textarea'))
      .filter(control => {
        const type = (control.getAttribute('type') || '').toLowerCase();
        return !['hidden', 'submit', 'button'].includes(type);
      })
      .slice(0, 24);

    controls.forEach(control => {
      const label = findControlLabel(control);
      const type = (control.getAttribute('type') || control.tagName.toLowerCase()).toLowerCase();
      let value = '';

      if (type === 'radio' || type === 'checkbox') {
        value = control.checked ? limitText(control.value || 'checked', 120) : '';
      } else if (control.tagName.toLowerCase() === 'select') {
        value = limitText(control.selectedOptions?.[0]?.textContent || '', 120);
      } else {
        value = limitText(control.value || '', 120);
      }

      if (!label && !control.name && !control.id) {
        return;
      }

      extracted.push({
        label,
        name: control.name || '',
        id: control.id || '',
        type,
        value
      });
    });
  });

  return extracted;
}

function extractKantaTables() {
  const forms = Array.from(document.forms);
  const tableContainers = [];

  forms.forEach(form => {
    const tables = form.querySelectorAll('table');
    tables.forEach(table => {
      if (table.querySelectorAll('tr').length > 1) {
        tableContainers.push(table);
      }
    });
  });

  return tableContainers.slice(0, 12).map(table => {
    const headers = extractKantaTableHeaders(table);
    const rows = Array.from(table.querySelectorAll('tbody tr, tr'))
      .filter(row => row.querySelectorAll('td').length > 0)
      .slice(0, 50)
      .map(row => {
        const cells = Array.from(row.querySelectorAll('td')).slice(0, 20);
        return cells.map((cell, index) => extractKantaCell(cell, headers[index] || `column_${index + 1}`));
      });

    return {
      selector: buildCompactSelector(table),
      headers,
      rows
    };
  });
}

function extractKantaTableHeaders(table) {
  const headerCells = Array.from(table.querySelectorAll('thead th')).slice(0, 20);
  if (headerCells.length > 0) {
    return headerCells.map(cell => limitText(cell.innerText || cell.textContent || '', 160));
  }

  const firstRowHeaders = Array.from(table.querySelectorAll('tr')).find(row => row.querySelectorAll('th').length > 0);
  if (firstRowHeaders) {
    return Array.from(firstRowHeaders.querySelectorAll('th'))
      .slice(0, 20)
      .map(cell => limitText(cell.innerText || cell.textContent || '', 160));
  }

  const sampleCells = table.querySelectorAll('tr td');
  const width = Math.min(sampleCells.length || 0, 10);
  return Array.from({ length: width }, (_, index) => `column_${index + 1}`);
}

function extractKantaCell(cell, header) {
  const text = limitText(cell.innerText || cell.textContent || '', 400);
  const links = Array.from(cell.querySelectorAll('a[href]')).slice(0, 4).map(link => ({
    label: limitText(link.innerText || link.textContent || '', 120),
    href: sanitizeUrl(link.href),
    selector: buildCompactSelector(link)
  }));

  return {
    header,
    text,
    links
  };
}

function extractKantaDetailFields() {
  const fields = [];
  const selectors = [
    'dl div',
    'dl dt',
    '.ui-panelgrid tr',
    '.ui-datatable-data tr',
    '.kansa-asiakirja dt',
    '.kansa-asiakirja dd'
  ];

  const rootNodes = Array.from(new Set(selectors.flatMap(selector => Array.from(document.querySelectorAll(selector)).slice(0, 60))));

  rootNodes.forEach(node => {
    if (node.matches('dl div')) {
      const dt = node.querySelector('dt');
      const dd = node.querySelector('dd');
      if (dt && dd) {
        fields.push({
          label: limitText(dt.innerText || dt.textContent || '', 180),
          value: limitText(dd.innerText || dd.textContent || '', 500)
        });
      }
      return;
    }

    if (node.matches('.ui-panelgrid tr, .ui-datatable-data tr')) {
      const cells = Array.from(node.querySelectorAll('td')).slice(0, 2);
      if (cells.length === 2) {
        const label = limitText(cells[0].innerText || cells[0].textContent || '', 180);
        const value = limitText(cells[1].innerText || cells[1].textContent || '', 500);
        if (label && value) {
          fields.push({ label, value });
        }
      }
    }
  });

  return fields.slice(0, 80);
}

function extractKantaDetailLinks() {
  return Array.from(document.querySelectorAll('a[href]'))
    .filter(link => {
      const text = (link.innerText || link.textContent || '').trim();
      return text && text.length < 160;
    })
    .slice(0, 80)
    .map(link => ({
      label: limitText(link.innerText || link.textContent || '', 160),
      href: sanitizeUrl(link.href),
      selector: buildCompactSelector(link)
    }));
}

function buildKantaPageDownloadFilename(pageType) {
  const pathSegment = (window.location.pathname.split('/').pop() || 'page')
    .replace(/\.faces$/i, '')
    .replace(/[^a-z0-9_-]+/gi, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase();

  return `mykanta-${pageType}-${pathSegment || 'page'}-${Date.now()}.eir`;
}

function buildKantaEirContent(snapshot, extraction) {
  const entries = collectKantaEirEntries(extraction);
  const patient = extractKantaPatientIdentity(extraction, snapshot);
  const validDates = entries
    .map(entry => entry.date)
    .filter(date => /^\d{4}-\d{2}-\d{2}$/.test(date))
    .sort();
  const providers = Array.from(new Set(entries
    .map(entry => entry.provider?.name)
    .filter(provider => provider && provider !== 'Unknown')));

  return {
    metadata: {
      format_version: '1.0',
      created_at: new Date().toISOString(),
      source: 'MyKanta Journal',
      patient,
      export_info: {
        total_entries: entries.length,
        date_range: {
          start: validDates[0] || 'Unknown',
          end: validDates[validDates.length - 1] || 'Unknown'
        },
        healthcare_providers: providers.length > 0 ? providers : ['MyKanta'],
        page: {
          type: extraction.pageType,
          title: snapshot.title,
          url: snapshot.url
        }
      }
    },
    entries
  };
}

function collectKantaEirEntries(extraction) {
  const entries = [];
  let counter = 1;
  const category = getKantaCategoryLabel(extraction.pageType);

  extraction.tables.forEach(table => {
    table.rows.forEach(row => {
      const rowText = row.map(cell => cell.text).filter(Boolean).join(' | ');
      if (!rowText) {
        return;
      }

      const rowDate = extractKantaDate(rowText);
      const rowNotes = row
        .map(cell => cell.header && cell.text ? `${cell.header}: ${cell.text}` : cell.text)
        .filter(Boolean)
        .slice(0, 12);
      const attachments = row.flatMap(cell => cell.links || []).map(link => ({
        title: link.label || 'Link',
        url: link.href
      }));
      const providerName = extractKantaProviderName(rowNotes, extraction);
      const responsiblePerson = extractKantaResponsiblePerson(rowText, rowNotes);
      const entryType = extractKantaEntryType(rowNotes, extraction);

      entries.push({
        id: `entry_${String(counter).padStart(3, '0')}`,
        date: rowDate,
        time: extractKantaTime(rowText),
        category,
        type: entryType,
        provider: {
          name: providerName,
          region: extractKantaRegion(providerName),
          location: 'Finland'
        },
        status: extractKantaStatus(rowText),
        responsible_person: responsiblePerson,
        content: {
          summary: buildKantaSummary(category, entryType, rowNotes, rowText),
          details: rowText,
          notes: rowNotes
        },
        attachments,
        tags: buildKantaTags(extraction.pageType, rowText)
      });
      counter += 1;
    });
  });

  if (entries.length > 0) {
    return entries;
  }

  const fieldNotes = extraction.detailFields
    .map(field => field.label && field.value ? `${field.label}: ${field.value}` : '')
    .filter(Boolean)
    .slice(0, 20);
  const detailText = [extraction.title, extraction.pageSummary, ...fieldNotes].filter(Boolean).join(' | ');
  const providerName = extractKantaProviderName(fieldNotes, extraction);
  const entryType = extractKantaEntryType(fieldNotes, extraction);
  const responsiblePerson = extractKantaResponsiblePerson(detailText, fieldNotes);

  return [{
    id: 'entry_001',
    date: extractKantaDate(detailText),
    time: extractKantaTime(extraction.pageSummary),
    category,
    type: entryType,
    provider: {
      name: providerName,
      region: extractKantaRegion(providerName),
      location: 'Finland'
    },
    status: extractKantaStatus(detailText),
    responsible_person: responsiblePerson,
    content: {
      summary: buildKantaSummary(category, entryType, fieldNotes, extraction.pageSummary),
      details: extraction.pageSummary.slice(0, 800),
      notes: fieldNotes.length > 0 ? fieldNotes : [extraction.pageSummary.slice(0, 240)]
    },
    attachments: extraction.links.slice(0, 10).map(link => ({
      title: link.label || 'Link',
      url: link.href
    })),
    tags: buildKantaTags(extraction.pageType, extraction.pageSummary)
  }];
}

function getKantaCategoryLabel(pageType) {
  return KANTA_PAGE_LABELS[pageType] || KANTA_PAGE_LABELS.unknown;
}

function extractKantaPatientIdentity(extraction, snapshot) {
  const pageText = [
    snapshot?.title,
    extraction?.pageSummary,
    ...(extraction?.detailFields || []).flatMap(field => [field.label, field.value])
  ].filter(Boolean).join(' ');
  const personalNumberMatch = pageText.match(/\b(\d{2}\.\d{2}\.\d{4}|\d{6}[-+A]\d{3}[0-9A-Y]|\d{11})\b/i);
  const birthDate = normalizeKantaBirthDate(personalNumberMatch?.[1] || '');

  return {
    name: extractKantaPatientName(pageText),
    birth_date: birthDate,
    personal_number: personalNumberMatch?.[1] || 'Unknown'
  };
}

function extractKantaPatientName(pageText = '') {
  const selectors = [
    '.header_henkilo',
    '#textHeader31',
    '.header_nimi',
    '[class*="header"][class*="nimi"]'
  ];

  for (const selector of selectors) {
    const element = document.querySelector(selector);
    const value = limitText(element?.innerText || element?.textContent || '', 120);
    if (value) {
      return value;
    }
  }

  const textValue = String(pageText || '');
  const textMatch = textValue.match(/\b(?:Namn|Name|Patient)\s*[:\-]\s*([A-ZÅÄÖ][^\n|]{2,80})/i);
  if (textMatch) {
    return limitText(textMatch[1], 120);
  }

  return 'Unknown';
}

function normalizeKantaBirthDate(value) {
  if (!value) {
    return 'Unknown';
  }

  const dottedMatch = value.match(/\b(\d{2})\.(\d{2})\.(\d{4})\b/);
  if (dottedMatch) {
    const [, day, month, year] = dottedMatch;
    return `${year}-${month}-${day}`;
  }

  const finnishIdMatch = value.match(/\b(\d{2})(\d{2})(\d{2})[-+A]\d{3}[0-9A-Y]\b/i);
  if (finnishIdMatch) {
    const [, day, month, year] = finnishIdMatch;
    const centuryMarker = value.charAt(6).toUpperCase();
    const century = centuryMarker === '+' ? '18' : centuryMarker === 'A' ? '20' : '19';
    return `${century}${year}-${month}-${day}`;
  }

  return 'Unknown';
}

function extractKantaDate(text) {
  const value = String(text || '');
  const isoMatch = value.match(/\b(\d{4}-\d{2}-\d{2})\b/);
  if (isoMatch) {
    return isoMatch[1];
  }

  const dottedYearMatch = value.match(/\b(\d{1,2})\.(\d{1,2})\.(\d{4})\b/);
  if (dottedYearMatch) {
    const [, day, month, year] = dottedYearMatch;
    return `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
  }

  const dottedShortMatch = value.match(/\b(\d{1,2})\.(\d{1,2})\.(\d{2})\b/);
  if (dottedShortMatch) {
    const [, day, month, year] = dottedShortMatch;
    const fullYear = Number(year) > 70 ? `19${year}` : `20${year}`;
    return `${fullYear}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
  }

  return 'Unknown';
}

function extractKantaTime(text) {
  const value = String(text || '');
  const match = value.match(/\b(\d{1,2}:\d{2})\b/);
  return match ? match[1] : 'Unknown';
}

function buildKantaTags(pageType, text) {
  const tags = new Set();
  if (pageType) {
    tags.add(pageType);
  }

  const normalized = String(text || '').toLowerCase();
  const tokenMap = [
    ['vaccination', ['rokot', 'vaccin']],
    ['laboratory', ['labor', 'lab']],
    ['diagnosis', ['diagno']],
    ['prescription', ['recept', 'lääk', 'resept']],
    ['imaging', ['rtg', 'bilddiagnost']],
    ['referral', ['remiss', 'lähete']],
    ['visit', ['besök', 'käynti']]
  ];

  tokenMap.forEach(([tag, fragments]) => {
    if (fragments.some(fragment => normalized.includes(fragment))) {
      tags.add(tag);
    }
  });

  return Array.from(tags);
}

function extractKantaProviderName(textParts, extraction) {
  const candidates = Array.isArray(textParts) ? textParts : [String(textParts || '')];
  const hints = ['provider', 'care unit', 'organization', 'unit', 'clinic', 'hospital', 'service point', 'yksikk', 'organisaatio', 'toimipaikka'];

  for (const candidate of candidates) {
    const value = String(candidate || '');
    const matchedHint = hints.find(hint => value.toLowerCase().includes(hint));
    if (!matchedHint) {
      continue;
    }

    const parts = value.split(':');
    if (parts.length > 1 && parts[1].trim()) {
      return limitText(parts.slice(1).join(':').trim(), 160);
    }
  }

  return limitText(extraction.title || getKantaCategoryLabel(extraction.pageType) || 'MyKanta', 160);
}

function extractKantaRegion(providerName) {
  const value = String(providerName || '');
  const regionMatch = value.match(/\b(?:Region|Wellbeing services county|Hospital district)\s+([A-ZÅÄÖa-zåäö -]{2,80})/);
  if (regionMatch) {
    return limitText(regionMatch[0], 120);
  }

  return 'Unknown';
}

function extractKantaStatus(text) {
  const value = String(text || '').toLowerCase();
  if (!value) {
    return 'Unknown';
  }

  if (/(signed|signerad|allekirjoitettu)/.test(value)) {
    return 'Signed';
  }
  if (/(unsigned|osignerad|luonnos|draft|preliminary|prelimin)/.test(value)) {
    return 'Unsigned';
  }
  if (/(completed|ready|valmis|slutförd)/.test(value)) {
    return 'Completed';
  }

  return 'Unknown';
}

function extractKantaResponsiblePerson(text, notes) {
  const combined = [text, ...(notes || [])].filter(Boolean).join(' | ');
  const roleMatch = combined.match(/\b(?:doctor|physician|läkare|nurse|sjuksköterska|specialist|dentist|tandläkare|terveydenhoitaja)\b/i);
  const nameMatch = combined.match(/\b(?:by|signed by|author|recorded by|kirjannut|laatija|tekijä)\s+([A-ZÅÄÖ][A-Za-zÅÄÖåäö.' -]{2,80})/i);

  return {
    name: nameMatch ? limitText(nameMatch[1], 120) : 'Unknown',
    role: roleMatch ? limitText(roleMatch[0], 80) : 'Unknown'
  };
}

function extractKantaEntryType(notes, extraction) {
  const firstNote = (notes || []).find(note => String(note || '').trim());
  if (firstNote) {
    const normalized = firstNote.includes(':')
      ? firstNote.split(':')[0].trim()
      : firstNote.trim().slice(0, 80);
    if (normalized) {
      return limitText(normalized, 120);
    }
  }

  return extraction.headings[0] || extraction.title || getKantaCategoryLabel(extraction.pageType);
}

function buildKantaSummary(category, type, notes, fallbackText) {
  const note = (notes || []).find(item => String(item || '').trim());
  if (note) {
    return `${category} - ${limitText(note.replace(/^[^:]+:\s*/, ''), 120)}`;
  }

  if (type && type !== category) {
    return `${category} - ${type}`;
  }

  return limitText(fallbackText || category || 'Journal entry', 160);
}

function convertKantaObjectToYAML(obj) {
  function escapeYaml(value) {
    return `"${String(value ?? '').replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')}"`;
  }

  function formatValue(value, indent) {
    if (Array.isArray(value)) {
      if (value.length === 0) {
        return '[]';
      }
      return `\n${yamlify(value, indent)}`;
    }

    if (typeof value === 'object' && value !== null) {
      const keys = Object.keys(value);
      if (keys.length === 0) {
        return '{}';
      }
      return `\n${yamlify(value, indent)}`;
    }

    if (typeof value === 'number' || typeof value === 'boolean') {
      return String(value);
    }

    return escapeYaml(value);
  }

  function yamlify(value, indent = 0) {
    const spaces = '  '.repeat(indent);

    if (Array.isArray(value)) {
      return value.map(item => {
        if (typeof item === 'object' && item !== null && !Array.isArray(item)) {
          const entries = Object.entries(item);
          if (entries.length === 0) {
            return `${spaces}- {}`;
          }
          const [firstKey, firstValue] = entries[0];
          let output = `${spaces}- ${firstKey}: ${formatValue(firstValue, indent + 1)}`;
          for (let index = 1; index < entries.length; index += 1) {
            const [key, nestedValue] = entries[index];
            output += `\n${spaces}  ${key}: ${formatValue(nestedValue, indent + 1)}`;
          }
          return output;
        }
        return `${spaces}- ${formatValue(item, indent + 1)}`;
      }).join('\n');
    }

    return Object.entries(value).map(([key, nestedValue]) => (
      `${spaces}${key}: ${formatValue(nestedValue, indent + 1)}`
    )).join('\n');
  }

  return `${yamlify(obj)}\n`;
}

function buildKantaPageOutline() {
  const elements = Array.from(
    document.querySelectorAll('h1, h2, h3, button, a, label, legend, summary, [role="button"], [role="tab"], input, select, textarea')
  ).slice(0, 300);

  return elements.map(element => ({
    tag: element.tagName.toLowerCase(),
    text: limitText(element.innerText || element.textContent || '', 160),
    ariaLabel: limitText(element.getAttribute('aria-label') || '', 120),
    type: element.getAttribute('type') || '',
    name: element.getAttribute('name') || '',
    href: element.hasAttribute('href') ? sanitizeUrl(element.getAttribute('href')) : '',
    selector: buildCompactSelector(element)
  }));
}

function summarizeKantaForms() {
  return Array.from(document.forms).slice(0, 30).map(form => summarizeKantaForm(form));
}

function summarizeKantaForm(form) {
  const controls = Array.from(form.querySelectorAll('input, select, textarea, button')).slice(0, 80);
  return {
    action: sanitizeUrl(form.getAttribute('action') || ''),
    method: (form.getAttribute('method') || 'get').toLowerCase(),
    selector: buildCompactSelector(form),
    controls: controls.map(control => ({
      tag: control.tagName.toLowerCase(),
      type: control.getAttribute('type') || '',
      name: control.getAttribute('name') || '',
      id: control.id || '',
      autocomplete: control.getAttribute('autocomplete') || '',
      label: findControlLabel(control)
    }))
  };
}

function summarizeKantaLinks() {
  return Array.from(document.querySelectorAll('a[href]')).slice(0, 150).map(link => ({
    text: limitText(link.innerText || link.textContent || '', 140),
    href: sanitizeUrl(link.href),
    selector: buildCompactSelector(link)
  }));
}

function summarizeKantaResources() {
  return performance.getEntriesByType('resource')
    .filter(entry => ['fetch', 'xmlhttprequest', 'iframe', 'document'].includes(entry.initiatorType))
    .slice(-200)
    .map(entry => ({
      name: sanitizeUrl(entry.name),
      initiatorType: entry.initiatorType,
      durationMs: Math.round(entry.duration),
      transferSize: entry.transferSize || 0
    }));
}

function summarizeKantaStorage() {
  return {
    localStorageKeys: safeStorageKeys(window.localStorage),
    sessionStorageKeys: safeStorageKeys(window.sessionStorage),
    metaNames: Array.from(document.querySelectorAll('meta[name], meta[property]')).slice(0, 60).map(meta => ({
      name: meta.getAttribute('name') || meta.getAttribute('property') || '',
      contentPreview: limitText(meta.getAttribute('content') || '', 120)
    }))
  };
}

function safeStorageKeys(storage) {
  try {
    return Object.keys(storage || {}).slice(0, 100);
  } catch (error) {
    return [];
  }
}

function sanitizeDocumentHtml() {
  const clone = document.documentElement.cloneNode(true);

  clone.querySelectorAll('iframe, canvas, video, audio').forEach(node => node.remove());

  clone.querySelectorAll('input, textarea, select').forEach(field => {
    field.removeAttribute('value');
    field.setAttribute('value', '');
    if (field.tagName.toLowerCase() === 'textarea') {
      field.textContent = '';
    }
  });

  clone.querySelectorAll('[contenteditable="true"]').forEach(element => {
    element.textContent = '';
  });

  clone.querySelectorAll('script').forEach(script => {
    if (script.src) {
      script.setAttribute('src', sanitizeUrl(script.getAttribute('src')));
    } else {
      script.textContent = '';
    }
  });

  clone.querySelectorAll('[href]').forEach(element => {
    element.setAttribute('href', sanitizeUrl(element.getAttribute('href')));
  });

  clone.querySelectorAll('[src]').forEach(element => {
    element.setAttribute('src', sanitizeUrl(element.getAttribute('src')));
  });

  clone.querySelectorAll('[action]').forEach(element => {
    element.setAttribute('action', sanitizeUrl(element.getAttribute('action')));
  });

  const html = clone.outerHTML.replace(/\s{2,}/g, ' ').trim();
  return html.length > KANTA_MAX_HTML_CHARS
    ? `${html.slice(0, KANTA_MAX_HTML_CHARS)}\n<!-- truncated -->`
    : html;
}

function sanitizeKantaNetworkRecord(record) {
  const rawUrl = record.url || '';
  const sensitive = isSensitiveUrl(rawUrl) || isSensitiveKantaPage();

  return {
    requestId: record.requestId || '',
    transport: record.transport || 'unknown',
    phase: record.phase || 'complete',
    capturedAt: record.capturedAt || new Date().toISOString(),
    pageUrl: sanitizeUrl(record.pageUrl || window.location.href),
    url: sanitizeUrl(rawUrl),
    method: (record.method || 'GET').toUpperCase(),
    status: typeof record.status === 'number' ? record.status : null,
    ok: typeof record.ok === 'boolean' ? record.ok : null,
    durationMs: typeof record.durationMs === 'number' ? Math.round(record.durationMs) : null,
    requestHeaders: sanitizeHeaders(record.requestHeaders, sensitive),
    responseHeaders: sanitizeHeaders(record.responseHeaders, sensitive),
    requestBody: sanitizeNetworkBody(record.requestBody, {
      sensitive,
      contentType: record.requestContentType || findHeaderValue(record.requestHeaders, 'content-type') || ''
    }),
    responseBody: sanitizeNetworkBody(record.responseBody, {
      sensitive,
      contentType: record.responseContentType || findHeaderValue(record.responseHeaders, 'content-type') || ''
    }),
    requestContentType: record.requestContentType || findHeaderValue(record.requestHeaders, 'content-type') || '',
    responseContentType: record.responseContentType || findHeaderValue(record.responseHeaders, 'content-type') || '',
    requestBodyTruncated: Boolean(record.requestBodyTruncated),
    responseBodyTruncated: Boolean(record.responseBodyTruncated),
    initiator: limitText(record.initiator || '', 240),
    error: record.error ? limitText(String(record.error), 500) : ''
  };
}

function sanitizeHeaders(headers, forceRedaction) {
  return normalizeHeaders(headers).map(header => {
    const sensitiveHeader = /authorization|cookie|token|secret|session|csrf/i.test(header.name);
    return {
      name: header.name,
      value: forceRedaction || sensitiveHeader ? '<redacted>' : limitText(header.value, 500)
    };
  });
}

function normalizeHeaders(headers) {
  if (!headers) {
    return [];
  }

  if (Array.isArray(headers)) {
    return headers
      .filter(entry => entry && entry.name)
      .map(entry => ({
        name: String(entry.name),
        value: String(entry.value ?? '')
      }));
  }

  return Object.entries(headers).map(([name, value]) => ({
    name: String(name),
    value: String(value ?? '')
  }));
}

function findHeaderValue(headers, name) {
  const normalized = normalizeHeaders(headers);
  const match = normalized.find(header => header.name.toLowerCase() === name.toLowerCase());
  return match ? match.value : '';
}

function sanitizeNetworkBody(body, options = {}) {
  if (body === null || body === undefined || body === '') {
    return '';
  }

  if (options.sensitive) {
    return '<redacted-sensitive-endpoint>';
  }

  const contentType = String(options.contentType || '').toLowerCase();
  const textual = !contentType || /(json|text|xml|html|javascript|graphql|x-www-form-urlencoded)/i.test(contentType);
  if (!textual) {
    return `<non-text-body:${contentType || 'unknown'}>`;
  }

  const stringBody = typeof body === 'string' ? body : JSON.stringify(body);
  return stringBody.length > KANTA_MAX_TEXT_BODY_CHARS
    ? `${stringBody.slice(0, KANTA_MAX_TEXT_BODY_CHARS)}\n/* truncated */`
    : stringBody;
}

function describeKantaElement(startElement) {
  const baseElement = toKantaElement(startElement);
  if (!baseElement) {
    return null;
  }

  const element = baseElement.closest('a, button, input, select, textarea, label, summary, [role="button"], [role="tab"]');
  if (!element) {
    return null;
  }

  return {
    tag: element.tagName.toLowerCase(),
    text: limitText(element.innerText || element.textContent || '', 160),
    ariaLabel: limitText(element.getAttribute('aria-label') || '', 120),
    href: element.hasAttribute('href') ? sanitizeUrl(element.getAttribute('href')) : '',
    name: element.getAttribute('name') || '',
    type: element.getAttribute('type') || '',
    selector: buildCompactSelector(element)
  };
}

function toKantaElement(target) {
  if (!target) {
    return null;
  }

  if (target instanceof Element) {
    return target;
  }

  if (target.parentElement instanceof Element) {
    return target.parentElement;
  }

  return null;
}

function buildCompactSelector(element) {
  if (!element || !element.tagName) {
    return '';
  }

  if (element.id) {
    return `${element.tagName.toLowerCase()}#${element.id}`;
  }

  const parts = [];
  let current = element;
  let depth = 0;

  while (current && current.tagName && depth < 5) {
    let part = current.tagName.toLowerCase();
    const classes = Array.from(current.classList || []).slice(0, 2);
    if (classes.length > 0) {
      part += `.${classes.join('.')}`;
    }

    if (current.parentElement) {
      const siblings = Array.from(current.parentElement.children).filter(sibling => sibling.tagName === current.tagName);
      if (siblings.length > 1) {
        part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
      }
    }

    parts.unshift(part);
    current = current.parentElement;
    depth += 1;
  }

  return parts.join(' > ');
}

function findControlLabel(control) {
  if (control.id) {
    const explicitLabel = document.querySelector(`label[for="${CSS.escape(control.id)}"]`);
    if (explicitLabel) {
      return limitText(explicitLabel.innerText || explicitLabel.textContent || '', 120);
    }
  }

  const wrappingLabel = control.closest('label');
  if (wrappingLabel) {
    return limitText(wrappingLabel.innerText || wrappingLabel.textContent || '', 120);
  }

  return limitText(control.getAttribute('aria-label') || control.getAttribute('placeholder') || '', 120);
}

function sanitizeUrl(rawUrl) {
  if (!rawUrl) {
    return '';
  }

  try {
    const url = new URL(rawUrl, window.location.href);
    const parameterNames = Array.from(url.searchParams.keys());
    url.hash = '';
    url.search = '';

    if (parameterNames.length === 0) {
      return `${url.origin}${url.pathname}`;
    }

    const redactedQuery = parameterNames
      .map(name => `${encodeURIComponent(name)}=<redacted>`)
      .join('&');

    return `${url.origin}${url.pathname}?${redactedQuery}`;
  } catch (error) {
    return String(rawUrl).split('#')[0].split('?')[0];
  }
}

function limitText(value, maxLength) {
  const normalized = String(value || '').replace(/\s+/g, ' ').trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }

  return `${normalized.slice(0, maxLength - 1)}…`;
}

async function appendKantaEvent(type, payload) {
  await queueKantaRecorderWrite(async () => {
    const session = await getKantaRecorderSession();
    if (!session || session.status !== 'recording') {
      return;
    }

    session.updatedAt = new Date().toISOString();
    await saveKantaRecorderSession(session);
    await addKantaArtifact({
      sessionId: session.id,
      artifactType: 'event',
      capturedAt: new Date().toISOString(),
      data: {
        type,
        ...payload
      }
    });
    scheduleKantaRecorderPanelRefresh();
  });
}

function queueKantaRecorderWrite(callback) {
  kantaRecorderWriteQueue = kantaRecorderWriteQueue
    .then(callback)
    .catch(error => console.error('Kanta recorder write failed:', error));

  return kantaRecorderWriteQueue;
}

function scheduleKantaRecorderPanelRefresh() {
  window.clearTimeout(kantaRecorderRefreshTimer);
  kantaRecorderRefreshTimer = window.setTimeout(() => {
    void refreshKantaRecorderPanel();
  }, KANTA_PANEL_REFRESH_MS);
}

async function refreshKantaRecorderPanel() {
  const session = await getKantaRecorderSession();
  if (!session) {
    updateKantaRecorderPanel(null, emptyKantaRecorderCounts());
    return;
  }

  const artifacts = await listKantaArtifactsForSession(session.id);
  updateKantaRecorderPanel(session, summarizeKantaArtifacts(artifacts));
}

function updateKantaRecorderPanel(session, counts) {
  if (!kantaRecorderPanel) {
    return;
  }

  const badge = kantaRecorderPanel.querySelector('#kanta-recorder-status-badge');
  const statusText = kantaRecorderPanel.querySelector('#kanta-recorder-status-text');
  const eventsCount = kantaRecorderPanel.querySelector('#kanta-recorder-events-count');
  const pagesCount = kantaRecorderPanel.querySelector('#kanta-recorder-pages-count');
  const networkCount = kantaRecorderPanel.querySelector('#kanta-recorder-network-count');
  const startButton = kantaRecorderPanel.querySelector('#kanta-recorder-start');
  const stopButton = kantaRecorderPanel.querySelector('#kanta-recorder-stop');
  const exportButton = kantaRecorderPanel.querySelector('#kanta-recorder-export');
  const downloadPageButton = kantaRecorderPanel.querySelector('#kanta-recorder-download-page');
  const clearButton = kantaRecorderPanel.querySelector('#kanta-recorder-clear');

  const isRecording = Boolean(session && session.status === 'recording');
  const isStopped = Boolean(session && session.status === 'stopped');

  badge.textContent = isRecording ? 'Recording' : isStopped ? 'Stopped' : 'Idle';
  badge.className = `kanta-recorder-panel__badge ${isRecording ? 'kanta-recorder-panel__badge--recording' : 'kanta-recorder-panel__badge--idle'}`;
  statusText.textContent = isRecording
    ? `Recording ${counts.events} events, ${counts.pages} pages, and ${counts.network} network records.`
    : isStopped
      ? `Stopped. ${counts.total} artifacts are ready to export.`
      : 'Not recording.';
  eventsCount.textContent = String(counts.events);
  pagesCount.textContent = String(counts.pages);
  networkCount.textContent = String(counts.network);
  startButton.disabled = isRecording;
  stopButton.disabled = !isRecording;
  exportButton.disabled = !session;
  downloadPageButton.disabled = !isExtractableKantaPage();
  clearButton.disabled = !session;
}

function emptyKantaRecorderCounts() {
  return {
    total: 0,
    events: 0,
    pages: 0,
    network: 0
  };
}

function summarizeKantaArtifacts(artifacts) {
  return artifacts.reduce((summary, artifact) => {
    summary.total += 1;
    if (artifact.artifactType === 'event') {
      summary.events += 1;
    } else if (artifact.artifactType === 'page') {
      summary.pages += 1;
    } else if (artifact.artifactType === 'network') {
      summary.network += 1;
    }
    return summary;
  }, emptyKantaRecorderCounts());
}

function delay(ms) {
  return new Promise(resolve => {
    window.setTimeout(resolve, ms);
  });
}

function downloadKantaBlob(content, filename, mimeType) {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function getKantaRecorderDb() {
  if (!kantaRecorderDbPromise) {
    kantaRecorderDbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(KANTA_RECORDER_DB_NAME, KANTA_RECORDER_DB_VERSION);

      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(KANTA_RECORDER_ARTIFACTS_STORE)) {
          const store = db.createObjectStore(KANTA_RECORDER_ARTIFACTS_STORE, {
            keyPath: 'id',
            autoIncrement: true
          });
          store.createIndex('sessionId', 'sessionId', { unique: false });
        }
      };

      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  }

  return kantaRecorderDbPromise;
}

async function addKantaArtifact(record) {
  const db = await getKantaRecorderDb();
  await new Promise((resolve, reject) => {
    const transaction = db.transaction(KANTA_RECORDER_ARTIFACTS_STORE, 'readwrite');
    transaction.objectStore(KANTA_RECORDER_ARTIFACTS_STORE).add(record);
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
  });
}

async function listKantaArtifactsForSession(sessionId) {
  const db = await getKantaRecorderDb();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(KANTA_RECORDER_ARTIFACTS_STORE, 'readonly');
    const store = transaction.objectStore(KANTA_RECORDER_ARTIFACTS_STORE);
    const index = store.index('sessionId');
    const request = index.getAll(IDBKeyRange.only(sessionId));

    request.onsuccess = () => {
      const results = Array.isArray(request.result) ? request.result : [];
      results.sort((left, right) => left.id - right.id);
      resolve(results);
    };
    request.onerror = () => reject(request.error);
  });
}

async function deleteKantaArtifactsForSession(sessionId) {
  const db = await getKantaRecorderDb();
  await new Promise((resolve, reject) => {
    const transaction = db.transaction(KANTA_RECORDER_ARTIFACTS_STORE, 'readwrite');
    const store = transaction.objectStore(KANTA_RECORDER_ARTIFACTS_STORE);
    const index = store.index('sessionId');
    const request = index.openCursor(IDBKeyRange.only(sessionId));

    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) {
        return;
      }
      store.delete(cursor.primaryKey);
      cursor.continue();
    };

    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(transaction.error);
    transaction.onabort = () => reject(transaction.error);
  });
}

async function getKantaRecorderSession() {
  return storageGet(KANTA_RECORDER_STORAGE_KEY);
}

async function saveKantaRecorderSession(session) {
  await storageSet({ [KANTA_RECORDER_STORAGE_KEY]: session });
}

async function isKantaRecorderActive() {
  const session = await getKantaRecorderSession();
  return Boolean(session && session.status === 'recording');
}

function storageGet(key) {
  return new Promise(resolve => {
    chrome.storage.local.get([key], result => resolve(result[key]));
  });
}

function storageSet(value) {
  return new Promise(resolve => {
    chrome.storage.local.set(value, resolve);
  });
}

function storageRemove(key) {
  return new Promise(resolve => {
    chrome.storage.local.remove(key, resolve);
  });
}
