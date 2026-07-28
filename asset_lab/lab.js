// Read-only Asset Lab viewer. The manifest is supplied by manifest.js.
(function () {
  "use strict";

  const state = {
    manifest: window.ASSET_LAB_MANIFEST || { assets: [], orphans: [] },
    audioCatalog: window.ASSET_LAB_AUDIO_CATALOG || { candidates: [] },
    selectedAssetId: null,
    selectedMediaKey: null,
    filterQuery: "",
    treeOpen: true
  };
  const LAST_ASSET_STORAGE_KEY = "asset-lab:last-asset";

  const elements = {
    status: document.getElementById("manifest-status"),
    audioButton: document.getElementById("audio-button"),
    reload: document.getElementById("reload-button"),
    count: document.getElementById("asset-count"),
    search: document.getElementById("asset-search"),
    collapse: document.getElementById("collapse-assets"),
    expand: document.getElementById("expand-assets"),
    tree: document.getElementById("asset-tree"),
    warnings: document.getElementById("asset-warnings"),
    previewTitle: document.getElementById("preview-title"),
    previewKind: document.getElementById("preview-kind"),
    previewStage: document.getElementById("preview-stage"),
    previewCaption: document.getElementById("preview-caption"),
    inspectorEmpty: document.getElementById("inspector-empty"),
    inspectorContent: document.getElementById("inspector-content"),
    audioCount: document.getElementById("audio-count"),
    audioList: document.getElementById("audio-library-list")
  };

  const groupOrder = [
    ["character", "Characters"],
    ["prop", "Props"],
    ["background", "Backgrounds"],
    ["effect", "Effects"]
  ];

  function text(value) {
    return value === undefined || value === null || value === "" ? "-" : String(value);
  }

  function create(tag, className, content) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (content !== undefined) node.textContent = content;
    return node;
  }

  function getAsset() {
    return state.manifest.assets.find((asset) => asset.id === state.selectedAssetId) || null;
  }

  function statusClass(asset) {
    const values = [];
    [...(asset.images || []), ...(asset.animations || [])].forEach((item) => values.push(item.status));
    if (values.includes("missing_on_disk")) return "is-danger";
    if (values.some((value) => value && value !== "created_on_disk")) return "is-warning";
    return "";
  }

  function taxonomyLabel(asset) {
    if (Array.isArray(asset.groups) && asset.groups.length) return asset.groups.join(" / ");
    const parts = [asset.domain, asset.subcategory, asset.size_class].filter(Boolean);
    return parts.length ? parts.join(" / ") : "General";
  }

  function taxonomyPaths(asset) {
    if (Array.isArray(asset.groups) && asset.groups.length) return asset.groups;
    return [taxonomyLabel(asset).toLowerCase().replace(/\s*\/\s*/g, "/")];
  }

  function addToTaxonomy(root, path, asset) {
    let node = root;
    path.split("/").filter(Boolean).forEach((segment) => {
      if (!node.children.has(segment)) node.children.set(segment, { children: new Map(), assets: [] });
      node = node.children.get(segment);
    });
    node.assets.push(asset);
  }

  function taxonomyAssetCount(node) {
    return node.assets.length + [...node.children.values()].reduce((total, child) => total + taxonomyAssetCount(child), 0);
  }

  function renderTaxonomyNode(parent, node) {
    [...node.children.entries()].sort(([left], [right]) => left.localeCompare(right)).forEach(([segment, child]) => {
      const subgroup = document.createElement("details");
      subgroup.className = "asset-subgroup";
      subgroup.open = state.treeOpen || Boolean(state.filterQuery);
      const summary = document.createElement("summary");
      summary.textContent = `${segment} (${taxonomyAssetCount(child)})`;
      subgroup.append(summary);
      renderTaxonomyNode(subgroup, child);
      if (child.assets.length) renderAssetList(subgroup, child.assets);
      parent.append(subgroup);
    });
  }

  function renderAssetList(parent, assets) {
    const list = create("div", "asset-list");
    assets.sort((left, right) => left.id.localeCompare(right.id)).forEach((asset) => {
      const button = create("button", `asset-button${asset.id === state.selectedAssetId ? " is-selected" : ""}`);
      button.type = "button";
      button.addEventListener("click", () => selectAsset(asset.id));
      const row = create("span", "asset-row");
      row.append(create("span", "asset-name", asset.id));
      const dot = create("span", `asset-status-dot ${statusClass(asset)}`);
      dot.title = statusClass(asset) === "is-danger" ? "Missing file" : "Asset status";
      row.append(dot);
      button.append(row);
      list.append(button);
    });
    parent.append(list);
  }

  function renderTree() {
    elements.tree.replaceChildren();
    const assetsToShow = state.manifest.assets.filter((asset) => assetMatches(asset, state.filterQuery));
    elements.count.textContent = state.filterQuery ? `${assetsToShow.length}/${state.manifest.assets.length}` : state.manifest.assets.length;
    const grouped = new Map(groupOrder.map(([type]) => [type, []]));
    assetsToShow.forEach((asset) => {
      if (!grouped.has(asset.type)) grouped.set(asset.type, []);
      grouped.get(asset.type).push(asset);
    });

    groupOrder.concat([...grouped.keys()].filter((type) => !groupOrder.some(([known]) => known === type)).map((type) => [type, type])).forEach(([type, label]) => {
      const assets = grouped.get(type) || [];
      const group = document.createElement("details");
      group.className = "asset-group";
      group.open = Boolean(state.filterQuery) || state.treeOpen;
      const summary = document.createElement("summary");
      summary.textContent = `${label} (${assets.length})`;
      group.append(summary);
      const taxonomy = { children: new Map(), assets: [] };
      assets.forEach((asset) => taxonomyPaths(asset).forEach((path) => addToTaxonomy(taxonomy, path, asset)));
      renderTaxonomyNode(group, taxonomy);
      if (!assets.length) group.append(create("p", "muted", "Empty"));
      elements.tree.append(group);
    });

    renderWarnings();
  }

  function assetMatches(asset, query) {
    if (!query) return true;
    const haystack = [
      asset.id, asset.type, asset.domain, asset.subcategory, asset.size_class,
      ...(asset.groups || []), ...(asset.source_paths || []),
      ...(asset.images || []).flatMap((image) => [image.path, image.source_path]),
      ...(asset.animations || []).flatMap((animation) => [animation.name, animation.sheet_path, animation.gif_path, ...(animation.source_paths || [])])
    ].filter(Boolean).join(" ").toLowerCase();
    return haystack.includes(query);
  }

  function setAssetGroupsOpen(open) {
    state.treeOpen = open;
    elements.tree.querySelectorAll("details").forEach((details) => { details.open = open; });
  }

  function renderWarnings() {
    elements.warnings.replaceChildren();
    const orphans = state.manifest.orphans || [];
    const missing = state.manifest.assets.flatMap((asset) => [...(asset.images || []), ...(asset.animations || [])].filter((item) => item.status === "missing_on_disk"));
    if (!orphans.length && !missing.length) return;
    if (orphans.length) elements.warnings.append(create("p", "warning-line", `${orphans.length} orphan file${orphans.length === 1 ? "" : "s"}`));
    if (missing.length) elements.warnings.append(create("p", "warning-line is-danger", `${missing.length} missing file${missing.length === 1 ? "" : "s"}`));
  }

  function selectAsset(assetId) {
    state.selectedAssetId = assetId;
    try {
      window.localStorage.setItem(LAST_ASSET_STORAGE_KEY, assetId);
    } catch (error) {
      // Local file storage can be unavailable in some browser settings.
    }
    const asset = getAsset();
    if (asset && asset.animations && asset.animations.length) {
      const animation = asset.animations[0];
      state.selectedMediaKey = `animation:${animation.id}:${animation.gif_path ? "gif" : "sheet"}`;
    } else if (asset && asset.images && asset.images.length) {
      state.selectedMediaKey = `image:${asset.images[0].id}`;
    } else {
      state.selectedMediaKey = null;
    }
    renderTree();
    renderInspector();
    renderPreview();
  }

  function preferredInitialAssetId() {
    const datedAssets = state.manifest.assets
      .map((asset) => ({ asset, timestamp: Date.parse(asset.updated_at || asset.created_at || "") }))
      .filter((entry) => !Number.isNaN(entry.timestamp))
      .sort((left, right) => right.timestamp - left.timestamp);
    if (datedAssets.length) return datedAssets[0].asset.id;
    try {
      const remembered = window.localStorage.getItem(LAST_ASSET_STORAGE_KEY);
      if (remembered && state.manifest.assets.some((asset) => asset.id === remembered)) return remembered;
    } catch (error) {
      // Local file storage can be unavailable in some browser settings.
    }
    return state.manifest.assets.length ? state.manifest.assets[state.manifest.assets.length - 1].id : null;
  }

  function metadataRow(label, value, isPath) {
    const row = create("div", "metadata-row");
    row.append(create("span", "metadata-label", label));
    row.append(isPath ? create("code", "metadata-value", text(value)) : create("span", "metadata-value", text(value)));
    return row;
  }

  function chooseMedia(key) {
    state.selectedMediaKey = key;
    renderInspector();
    renderPreview();
  }

  function choiceCard(title, meta, selected, actions) {
    const card = create("div", `choice-card${selected ? " is-selected" : ""}`);
    card.append(create("div", "choice-card-title", title));
    card.append(create("div", "choice-card-meta", meta));
    const actionRow = create("div", "animation-actions");
    actions.forEach((action) => {
      const button = create("button", `choice-button${action.active ? " is-active" : ""}`, action.label);
      button.type = "button";
      button.addEventListener("click", () => chooseMedia(action.key));
      actionRow.append(button);
    });
    card.append(actionRow);
    return card;
  }

  function collapsibleSection(title, open) {
    const section = create("details", "asset-section inspector-section");
    section.open = open;
    const summary = create("summary", "asset-section-title", title);
    section.append(summary);
    return section;
  }

  function renderInspector() {
    const asset = getAsset();
    if (!asset) {
      elements.inspectorEmpty.hidden = false;
      elements.inspectorContent.hidden = true;
      return;
    }
    elements.inspectorEmpty.hidden = true;
    elements.inspectorContent.hidden = false;
    elements.inspectorContent.replaceChildren();

    const header = create("div", "inspector-header");
    header.append(create("h2", null, asset.id));
    header.append(create("p", "muted", `${text(asset.type)} · ${text(asset.folder)}`));
    elements.inspectorContent.append(header);

    const imagesSection = collapsibleSection("Images", true);
    const imageList = create("div", "choice-list");
    (asset.images || []).forEach((image) => imageList.append(choiceCard(`Version ${text(image.version)}`, `${text(image.provider)} · ${text(image.width)} x ${text(image.height)}`, state.selectedMediaKey === `image:${image.id}`, [{ label: "Open image", key: `image:${image.id}`, active: state.selectedMediaKey === `image:${image.id}` }])));
    if (!asset.images || !asset.images.length) imageList.append(create("p", "muted", "No images recorded."));
    imagesSection.append(imageList);
    elements.inspectorContent.append(imagesSection);

    const animationsSection = collapsibleSection("Animations", true);
    const animationList = create("div", "choice-list");
    (asset.animations || []).forEach((animation) => {
      const baseKey = `animation:${animation.id}`;
      const actions = [];
      if (animation.gif_path) actions.push({ label: "GIF", key: `${baseKey}:gif`, active: state.selectedMediaKey === `${baseKey}:gif` });
      if (animation.sheet_path) actions.push({ label: "Sprite sheet", key: `${baseKey}:sheet`, active: state.selectedMediaKey === `${baseKey}:sheet` });
      animationList.append(choiceCard(`${text(animation.name)} · v${text(animation.version)}`, `${text(animation.provider)} · ${text(animation.frame_count)} frames · ${text(animation.fps)} FPS`, actions.some((action) => action.active), actions));
    });
    if (!asset.animations || !asset.animations.length) animationList.append(create("p", "muted", "No animations recorded."));
    animationsSection.append(animationList);
    elements.inspectorContent.append(animationsSection);

    const selected = selectedRecord(asset);
    const metadataSection = collapsibleSection("Metadata", false);
    const metadata = create("div", "metadata");
    if (selected) {
      metadata.append(metadataRow("Provider", selected.provider));
      metadata.append(metadataRow("Status", selected.status || "created_on_disk"));
      metadata.append(metadataRow("Prompt", selected.prompt));
      metadata.append(metadataRow("Source image", selected.source_image_path || selected.source_image_version));
      metadata.append(metadataRow("Dimensions", selected.width ? `${selected.width} x ${selected.height}` : `${selected.frame_width || "-"} x ${selected.frame_height || "-"}`));
      metadata.append(metadataRow("Frame count", selected.frame_count));
      metadata.append(metadataRow("FPS", selected.fps));
      metadata.append(metadataRow("Path", selected.path || selected.gif_path || selected.sheet_path, true));
    }
    metadataSection.append(metadata);
    elements.inspectorContent.append(metadataSection);
  }

  function selectedRecord(asset) {
    if (!state.selectedMediaKey) return null;
    const parts = state.selectedMediaKey.split(":");
    if (parts[0] === "image") return (asset.images || []).find((image) => image.id === parts[1]) || null;
    return (asset.animations || []).find((animation) => animation.id === parts[1]) || null;
  }

  function renderPreview() {
    const asset = getAsset();
    const record = selectedRecord(asset || { images: [], animations: [] });
    elements.previewStage.replaceChildren();
    if (!asset || !record) {
      elements.previewTitle.textContent = "Select an asset";
      elements.previewKind.textContent = "NONE";
      elements.previewCaption.textContent = "The selected file will appear here.";
      elements.previewStage.append(createEmptyPreview());
      return;
    }

    const keyParts = state.selectedMediaKey.split(":");
    const isImage = keyParts[0] === "image";
    const useGif = !isImage && keyParts[2] === "gif";
    const path = isImage ? record.path : (useGif ? record.gif_path : record.sheet_path);
    elements.previewTitle.textContent = asset.id;
    elements.previewKind.textContent = isImage ? "IMAGE" : (useGif ? "GIF" : "SPRITE SHEET");
    elements.previewCaption.textContent = path || "No preview path recorded.";
    if (!path) {
      elements.previewStage.append(create("p", "muted", "No file path recorded for this entry."));
      return;
    }
    const image = create("img", "preview-image");
    image.alt = `${asset.id} ${isImage ? "image" : text(record.name)}`;
    image.src = path;
    image.addEventListener("error", () => {
      elements.previewStage.replaceChildren(create("p", "warning-line is-danger", "File could not be loaded. Check the manifest and disk."));
    }, { once: true });
    elements.previewStage.append(image);
  }

  function createEmptyPreview() {
    const empty = create("div", "empty-state");
    empty.append(create("span", "empty-icon", "+"));
    empty.append(create("p", null, "Select an image or animation to inspect it."));
    return empty;
  }

  function setStatus(message, isError) {
    elements.status.textContent = message;
    elements.status.classList.toggle("is-error", Boolean(isError));
  }

  function renderAudioLibrary() {
    const candidates = state.audioCatalog.candidates || [];
    elements.audioCount.textContent = candidates.length;
    elements.audioList.replaceChildren();
    if (!candidates.length) {
      elements.audioList.append(create("p", "muted", "No audio candidates staged yet."));
      return;
    }
    const groups = new Map([["sound", "Sounds"], ["music", "Music"]]);
    groups.forEach((label, kind) => {
      const items = candidates.filter((candidate) => candidate.kind === kind);
      const section = document.createElement("details");
      section.className = "audio-group";
      section.open = true;
      const summary = create("summary", "asset-section-title", `${label} (${items.length})`);
      section.append(summary);
      const list = create("div", "audio-candidate-list");
      items.forEach((candidate) => {
        const card = create("article", "audio-candidate");
        const heading = create("div", "audio-candidate-heading");
        heading.append(create("strong", null, text(candidate.title)));
        const license = create("span", `license-badge${candidate.license && candidate.license.toLowerCase().includes("cc0") ? " is-cc0" : ""}`, text(candidate.license));
        heading.append(license);
        card.append(heading);
        card.append(create("code", "audio-candidate-id", text(candidate.candidate_id)));
        card.append(create("p", "choice-card-meta", `${text(candidate.source)} · ${text(candidate.author)} · ${text(candidate.duration)}s`));
        if (candidate.local_preview || candidate.preview_url) {
          const audio = document.createElement("audio");
          audio.controls = true;
          audio.preload = "none";
          audio.src = candidate.local_preview || candidate.preview_url;
          card.append(audio);
        } else {
          card.append(create("p", "warning-line is-danger", "Local preview missing."));
        }
        const footer = create("div", "audio-candidate-footer");
        const link = create("a", "source-link", "Open source");
        link.href = candidate.source_url || "#";
        link.target = "_blank";
        link.rel = "noreferrer";
        footer.append(link);
        footer.append(create("span", "muted", candidate.license && candidate.license.toLowerCase().includes("cc0") ? "No attribution required" : "Attribution recorded on import"));
        card.append(footer);
        list.append(card);
      });
      if (!items.length) list.append(create("p", "muted", "Empty"));
      section.append(list);
      elements.audioList.append(section);
    });
  }

  function start() {
    if (!window.ASSET_LAB_MANIFEST) {
      setStatus("manifest.js missing", true);
    } else {
      setStatus(`${state.manifest.assets.length} assets loaded`);
    }
    elements.reload.addEventListener("click", () => window.location.reload());
    elements.search.addEventListener("input", (event) => {
      state.filterQuery = event.target.value.trim().toLowerCase();
      renderTree();
    });
    elements.collapse.addEventListener("click", () => setAssetGroupsOpen(false));
    elements.expand.addEventListener("click", () => setAssetGroupsOpen(true));
    elements.audioButton.addEventListener("click", () => {
      document.querySelector(".audio-library").scrollIntoView({ behavior: "smooth", block: "start" });
    });
    renderTree();
    renderAudioLibrary();
    const initialAssetId = preferredInitialAssetId();
    if (initialAssetId) selectAsset(initialAssetId);
  }

  start();
}());
