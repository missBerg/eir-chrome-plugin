async function initializeUnlockAtlas() {
    const mapElement = document.getElementById("unlockAtlasMap");
    const detailElement = document.getElementById("unlockAtlasDetail");
    const listElement = document.getElementById("unlockCountryDirectory");
    const legendElement = document.getElementById("unlockAtlasLegend");
    const filterElement = document.getElementById("unlockAtlasFilters");

    if (!mapElement || !detailElement || !listElement || !legendElement || !filterElement) {
        return;
    }

    const [countries, issueData, worldMap] = await Promise.all([
        fetchJson("unlock-countries.json"),
        fetchJson("unlock-issues.json").catch(() => ({ countries: {} })),
        fetchJson("world-countries.geojson")
    ]);

    const issuesByCode = issueData.countries || {};
    const enrichedCountries = countries.map(country => ({
        ...country,
        issue: issuesByCode[country.code] || null
    }));
    const trackedCountriesByCode = new Map(enrichedCountries.map(country => [country.code, country]));
    const trackedCodesByName = new Map(enrichedCountries.map(country => [normalizeCountryName(country.name), country.code]));
    const geoFeaturesByCode = new Map();
    (worldMap.features || []).forEach(feature => {
        const code = resolveCountryCode(feature, trackedCodesByName);
        if (code && !geoFeaturesByCode.has(code)) {
            geoFeaturesByCode.set(code, feature);
        }
    });

    const statuses = [
        { key: "all", label: "All countries", count: enrichedCountries.length },
        { key: "unlocked", label: "Unlocked", count: countByStatus(enrichedCountries, "unlocked") },
        { key: "pilot", label: "Pilot", count: countByStatus(enrichedCountries, "pilot") },
        { key: "ready", label: "Ready next", count: countByStatus(enrichedCountries, "ready") },
        { key: "research", label: "Research", count: countByStatus(enrichedCountries, "research") },
        { key: "watch", label: "Watchlist", count: countByStatus(enrichedCountries, "watch") }
    ];

    let selectedCode = "SE";
    let activeFilter = "all";
    let atlasMap = null;
    let countryLayer = null;
    let markerLayer = null;
    let shouldFitMap = true;

    renderLegend();
    renderFilters();
    renderMap();
    renderDirectory();
    renderDetail();

    function renderFilters() {
        filterElement.innerHTML = statuses.map(status => `
            <button class="atlas-filter${activeFilter === status.key ? " atlas-filter--active" : ""}" type="button" data-filter="${status.key}">
                <span>${status.label}</span>
                <strong>${status.count}</strong>
            </button>
        `).join("");

        filterElement.querySelectorAll("[data-filter]").forEach(button => {
            button.addEventListener("click", () => {
                activeFilter = button.dataset.filter || "all";
                const visible = filteredCountries();
                if (!visible.some(country => country.code === selectedCode)) {
                    selectedCode = visible[0]?.code || selectedCode;
                }
                shouldFitMap = true;
                renderFilters();
                renderMap();
                renderDirectory();
                renderDetail();
            });
        });
    }

    function renderLegend() {
        legendElement.innerHTML = [
            ["unlocked", "Unlocked"],
            ["pilot", "Pilot"],
            ["ready", "Ready next"],
            ["research", "Research"],
            ["watch", "Watchlist"]
        ].map(([status, label]) => `
            <div class="atlas-legend__item">
                <span class="atlas-legend__dot atlas-legend__dot--${status}"></span>
                <span>${label}</span>
            </div>
        `).join("");
    }

    function renderMap() {
        if (!atlasMap) {
            atlasMap = L.map(mapElement, {
                zoomControl: false,
                scrollWheelZoom: false,
                worldCopyJump: false,
                attributionControl: false
            });

            L.control.zoom({ position: "bottomright" }).addTo(atlasMap);
            L.control.attribution({ position: "bottomleft", prefix: false })
                .addAttribution('Country outlines: <a href="https://www.naturalearthdata.com/" target="_blank" rel="noopener">Natural Earth</a>')
                .addTo(atlasMap);
        }

        if (countryLayer) {
            countryLayer.remove();
        }
        if (markerLayer) {
            markerLayer.remove();
        }

        const visibleCountries = filteredCountries();
        const visibleCodes = new Set(visibleCountries.map(country => country.code));
        const markerBounds = [];

        countryLayer = L.geoJSON(worldMap, {
            style: feature => buildCountryStyle(
                trackedCountriesByCode.get(resolveCountryCode(feature, trackedCodesByName)),
                visibleCodes,
                selectedCode
            ),
            onEachFeature: (feature, layer) => {
                const code = resolveCountryCode(feature, trackedCodesByName);
                const country = trackedCountriesByCode.get(code);
                if (!country || !visibleCodes.has(code)) {
                    return;
                }

                layer.on("click", () => {
                    selectedCode = code;
                    shouldFitMap = false;
                    renderMap();
                    renderDirectory();
                    renderDetail();
                });
            }
        }).addTo(atlasMap);

        markerLayer = L.layerGroup();
        visibleCountries.forEach(country => {
            const feature = geoFeaturesByCode.get(country.code);
            const center = getCountryMarkerPosition(country, feature);
            markerBounds.push(center);

            const marker = L.marker(center, {
                icon: buildCountryMarker(country, country.code === selectedCode),
                keyboard: false
            });
            marker.bindTooltip(`${flagEmoji(country.code)} ${country.name}`, {
                direction: "top",
                offset: [0, -16],
                opacity: 1,
                className: "atlas-tooltip"
            });
            marker.on("click", () => {
                selectedCode = country.code;
                shouldFitMap = false;
                renderMap();
                renderDirectory();
                renderDetail();
            });
            markerLayer.addLayer(marker);
        });
        markerLayer.addTo(atlasMap);

        if (shouldFitMap) {
            const bounds = markerBounds.length > 0
                ? L.latLngBounds(markerBounds)
                : L.latLngBounds([[35, -25], [66, 35]]);
            atlasMap.fitBounds(bounds.pad(0.5), {
                animate: false,
                maxZoom: 4
            });
            shouldFitMap = false;
        }

        mapElement.querySelector(".atlas-map__hint")?.remove();
        mapElement.insertAdjacentHTML(
            "beforeend",
            '<div class="atlas-map__hint">Click a country to see how patients access their data and who has claimed the integration mission.</div>'
        );
    }

    function renderDirectory() {
        listElement.innerHTML = filteredCountries().map(country => {
            const issue = country.issue;
            const claimLine = issue?.claimant
                ? `Claimed by <a href="${issue.claimUrl || issue.url}" target="_blank" rel="noopener">@${issue.claimant}</a>`
                : issue?.url
                    ? `<a href="${issue.url}" target="_blank" rel="noopener">Claim this country on GitHub</a>`
                    : `Issue provisioning pending`;

            return `
                <article class="country-directory-card${country.code === selectedCode ? " country-directory-card--selected" : ""}" data-country="${country.code}">
                    <div class="country-directory-card__top">
                        <div>
                            <div class="country-directory-card__name">${flagEmoji(country.code)} ${country.name}</div>
                            <div class="country-directory-card__portal">${country.portal}</div>
                        </div>
                        <span class="status-badge status-badge--${country.status}">${statusLabel(country.status)}</span>
                    </div>
                    <p>${country.summary}</p>
                    <div class="country-directory-card__meta">
                        <span>${country.login}</span>
                        <span>${country.scope}</span>
                    </div>
                    <div class="country-directory-card__claim">${claimLine}</div>
                </article>
            `;
        }).join("");

        listElement.querySelectorAll("[data-country]").forEach(card => {
            card.addEventListener("click", () => {
                selectedCode = card.dataset.country || selectedCode;
                renderMap();
                renderDirectory();
                renderDetail();
            });
        });
    }

    function renderDetail() {
        const country = enrichedCountries.find(item => item.code === selectedCode) || enrichedCountries[0];
        if (!country) {
            return;
        }

        const issue = country.issue;
        const isSweden = country.code === "SE";
        const claimState = issue?.claimant
            ? `<p class="atlas-detail__claim atlas-detail__claim--claimed">Claimed by <a href="${issue.claimUrl || issue.url}" target="_blank" rel="noopener">@${issue.claimant}</a></p>`
            : issue?.url
                ? `<p class="atlas-detail__claim">No active claimant yet. <a href="${issue.url}" target="_blank" rel="noopener">Comment <code>/claim</code> on the GitHub issue</a> to take it.</p>`
                : `<p class="atlas-detail__claim">Issue provisioning pending.</p>`;

        const accessText = isSweden
            ? `Download the Chrome plugin, open <a href="${country.portalUrl}" target="_blank" rel="noopener">${country.portal}</a>, sign in with the official Swedish flow, and use the floating downloader to save your healthcare data on your device.`
            : `Use <a href="${country.portalUrl}" target="_blank" rel="noopener">${country.portal}</a> and follow the official patient sign-in flow for ${country.name}.`;

        const pluginNote = isSweden && country.downloadUrl
            ? `
                <div class="atlas-detail__plugin-note">
                    <strong>Sweden is live now</strong>
                    <p>The Chrome plugin already lets Swedish patients download their healthcare data from 1177 into portable local files.</p>
                </div>
            `
            : "";

        const actionButtons = [];
        if (isSweden && country.downloadUrl) {
            actionButtons.push(`<a class="button button--primary" href="${country.downloadUrl}" target="_blank" rel="noopener">${country.downloadLabel || "Download Chrome plugin"}</a>`);
            actionButtons.push(`<a class="button button--secondary" href="${country.portalUrl}" target="_blank" rel="noopener">${country.accessLabel}</a>`);
        } else {
            actionButtons.push(`<a class="button button--primary" href="${country.portalUrl}" target="_blank" rel="noopener">${country.accessLabel}</a>`);
        }

        if (issue?.url) {
            actionButtons.push(`<a class="button button--secondary" href="${issue.url}" target="_blank" rel="noopener">Open GitHub issue</a>`);
        }

        detailElement.innerHTML = `
            <div class="atlas-detail__eyebrow">${country.group}</div>
            <div class="atlas-detail__header">
                <div>
                    <h3>${flagEmoji(country.code)} ${country.name}</h3>
                    <p class="atlas-detail__portal">${country.portal}</p>
                </div>
                <span class="status-badge status-badge--${country.status}">${statusLabel(country.status)}</span>
            </div>
            <p class="atlas-detail__summary">${country.summary}</p>
            <dl class="atlas-detail__facts">
                <div>
                    <dt>How patients log in</dt>
                    <dd>${country.login}</dd>
                </div>
                <div>
                    <dt>Integration shape</dt>
                    <dd>${country.scope}</dd>
                </div>
                <div>
                    <dt>How to access your data</dt>
                    <dd>${accessText}</dd>
                </div>
                <div>
                    <dt>Contribution mode</dt>
                    <dd>${contributionMode(country.status)}</dd>
                </div>
            </dl>
            ${pluginNote}
            ${claimState}
            <div class="atlas-detail__actions">
                ${actionButtons.join("")}
            </div>
        `;
    }

    function filteredCountries() {
        return enrichedCountries.filter(country => activeFilter === "all" || country.status === activeFilter);
    }
}

function buildCountryStyle(country, visibleCodes, selectedCode) {
    if (!country) {
        return {
            color: "rgba(122, 118, 111, 0.12)",
            weight: 0.7,
            fillColor: "rgba(255, 255, 255, 0.3)",
            fillOpacity: 0.45
        };
    }

    const hidden = !visibleCodes.has(country.code);
    const selected = country.code === selectedCode;

    return {
        color: selected ? "#1f2b24" : "rgba(61, 58, 54, 0.32)",
        weight: selected ? 1.8 : 1.1,
        fillColor: statusColor(country.status),
        fillOpacity: hidden ? 0.1 : selected ? 0.9 : 0.7
    };
}

function buildCountryMarker(country, selected) {
    const className = [
        "country-marker",
        `country-marker--${country.status}`,
        selected ? "country-marker--selected" : ""
    ].filter(Boolean).join(" ");

    return L.divIcon({
        className,
        html: `<span class="country-marker__code">${country.code}</span>`,
        iconSize: [42, 42],
        iconAnchor: [21, 21]
    });
}

function statusColor(status) {
    const colors = {
        unlocked: "#16a34a",
        pilot: "#d97706",
        ready: "#197a8e",
        research: "#4a8db4",
        watch: "#7a766f"
    };

    return colors[status] || colors.watch;
}

function resolveCountryCode(feature, trackedCodesByName) {
    const isoCode = String(feature?.properties?.ISO_A2 || "").toUpperCase();
    if (isoCode && isoCode !== "-99") {
        return isoCode;
    }

    const normalizedName = normalizeCountryName(feature?.properties?.NAME_EN || feature?.properties?.NAME);
    return COUNTRY_NAME_ALIASES[normalizedName] || trackedCodesByName.get(normalizedName) || null;
}

function normalizeCountryName(name) {
    return String(name || "")
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, " ")
        .trim();
}

function getCountryMarkerPosition(country, feature) {
    const labelLat = Number(feature?.properties?.LABEL_Y);
    const labelLng = Number(feature?.properties?.LABEL_X);
    if (Number.isFinite(labelLat) && Number.isFinite(labelLng)) {
        return L.latLng(labelLat, labelLng);
    }

    if (feature) {
        return L.geoJSON(feature).getBounds().getCenter();
    }

    const fallback = COUNTRY_MARKER_FALLBACKS[country.code];
    return L.latLng(fallback[0], fallback[1]);
}

const COUNTRY_NAME_ALIASES = {
    "france": "FR",
    "norway": "NO",
    "czech republic": "CZ"
};

const COUNTRY_MARKER_FALLBACKS = {
    MT: [35.8886, 14.4477]
};

function statusLabel(status) {
    const labels = {
        unlocked: "Unlocked",
        pilot: "Pilot",
        ready: "Ready next",
        research: "Research",
        watch: "Watchlist"
    };
    return labels[status] || status;
}

function contributionMode(status) {
    const labels = {
        unlocked: "Strengthen and maintain the existing country adapter.",
        pilot: "Run guided captures and help push the pilot into a working integration.",
        ready: "High-priority country. Good candidate for the next production adapter.",
        research: "Reconnaissance first: validate routes, endpoints, and data breadth.",
        watch: "Useful to map, but not yet a near-term production target."
    };
    return labels[status] || "";
}

function countByStatus(countries, status) {
    return countries.filter(country => country.status === status).length;
}

async function fetchJson(url) {
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) {
        throw new Error(`Failed to load ${url}`);
    }
    return response.json();
}

function flagEmoji(code) {
    return Array.from(code).map(character => String.fromCodePoint(127397 + character.charCodeAt(0))).join("");
}

window.addEventListener("DOMContentLoaded", () => {
    initializeUnlockAtlas().catch(error => {
        console.error("Unlock atlas failed to initialize", error);
    });
});
