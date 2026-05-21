// ============================================================================
// DRUG CLASSIFICATION FRONTEND (v3.2)
// Handles: compound names, SMILES, CAS, medicine detection, autocomplete,
// structure preview with confirm-flow, salt warnings, suggestions,
// Know More AI panel (via backend proxy), and all edge cases.
//
// FIX (v3.2): Know More payload no longer falls back to rawInput as
// compound_label. For SMILES/CAS inputs, compound_label is left empty
// so the backend's PubChem resolver can determine the real name.
// The smiles field is always populated so the backend has structural context.
// ============================================================================

document.addEventListener("DOMContentLoaded", () => {

  // ── Elements ──────────────────────────────────────────────────────────────
  const compoundInput        = document.getElementById("compoundInput");
  const classifyBtn          = document.getElementById("classifyBtn");
  const resetBtn             = document.getElementById("resetBtn");
  const loaderContainer      = document.getElementById("loaderContainer");
  const resultsLayout        = document.getElementById("resultsLayout");
  const inputTypeBadge       = document.getElementById("inputTypeBadge");
  const autocompleteDropdown = document.getElementById("autocompleteDropdown");
  const saltWarning          = document.getElementById("saltWarning");

  // Result elements
  const resultBox            = document.getElementById("resultBox");
  const resultClass          = document.getElementById("resultClass");
  const resultConfidenceText = document.getElementById("resultConfidenceText");
  const confidenceBar        = document.getElementById("confidenceBar");
  const resultResolvedName   = document.getElementById("resultResolvedName");
  const resultInputType      = document.getElementById("resultInputType");
  const probClasses          = document.getElementById("probClasses");
  const probabilitiesCard    = document.getElementById("probabilitiesCard");
  const classBadge           = document.getElementById("classBadge");
  const probabilitiesDesc    = document.getElementById("probabilitiesDesc");

  // Medicine card elements
  const medicineCard          = document.getElementById("medicineCard");
  const medicineCardSubtitle  = document.getElementById("medicineCardSubtitle");
  const medicineActiveCompound= document.getElementById("medicineActiveCompound");
  const medicineSmiles        = document.getElementById("medicineSmiles");
  const medicineStructureImg  = document.getElementById("medicineStructureImg");
  const medicineIndication    = document.getElementById("medicineIndication");
  const btnClassifyActive     = document.getElementById("btnClassifyActive");
  const btnDismissMedicine    = document.getElementById("btnDismissMedicine");

  // Not found card
  const notFoundCard   = document.getElementById("notFoundCard");
  const notFoundMsg    = document.getElementById("notFoundMsg");
  const suggestionsArea= document.getElementById("suggestionsArea");
  const suggestionsList= document.getElementById("suggestionsList");

  // Compound preview card
  const compoundPreviewCard   = document.getElementById("compoundPreviewCard");
  const previewCompoundName   = document.getElementById("previewCompoundName");
  const previewSmilesText     = document.getElementById("previewSmilesText");
  const previewStructureImg   = document.getElementById("previewStructureImg");
  const previewIupac          = document.getElementById("previewIupac");
  const btnProceedAnalysis    = document.getElementById("btnProceedAnalysis");
  const btnCancelPreview      = document.getElementById("btnCancelPreview");

  // Know More panel
  const knowMoreBtn    = document.getElementById("knowMoreBtn");
  const knowMorePanel  = document.getElementById("knowMorePanel");
  const knowMoreContent= document.getElementById("knowMoreContent");

  // ── Constants ─────────────────────────────────────────────────────────────
  const CLASS_NAMES = {
    0: "Animal-derived", 1: "Bacteria-derived", 2: "Chromista-derived",
    3: "Fungi-derived",  4: "Plant-derived",
  };
  const CLASS_ICONS = { 0:"🦁", 1:"🦠", 2:"🌊", 3:"🍄", 4:"🌿" };

  const SMILES_CHARS  = new Set("CNOSPFBrIlc()[]=@+-.#\\/0123456789%");
  const CAS_REGEX     = /^\d{2,7}-\d{2}-\d$/;
  const INCHIKEY_REGEX= /^[A-Z]{14}-[A-Z]{10}-[A-Z]$/;

  // ── State ─────────────────────────────────────────────────────────────────
  let autocompleteTimer     = null;
  let currentMedicineSmiles = null;
  let pendingSmiles         = null;
  let pendingResolvedName   = null;
  let pendingPreviewData    = null;   // stores full resolved data from preview step
  let lastClassifiedData    = null;

  // ── Input type detection ──────────────────────────────────────────────────
  function detectInputType(text) {
    text = text.trim();
    if (!text) return null;
    if (CAS_REGEX.test(text))      return "cas";
    if (INCHIKEY_REGEX.test(text)) return "inchikey";
    const ratio = [...text].filter(c => SMILES_CHARS.has(c)).length / text.length;
    if (ratio > 0.55)              return "smiles";
    return "name";
  }

  const BADGE_LABELS = {
    cas: "CAS number", inchikey: "InChIKey", smiles: "SMILES",
    name: "compound name", null: "type to begin"
  };

  // ── Live input handling ───────────────────────────────────────────────────
  compoundInput.addEventListener("input", () => {
    const text  = compoundInput.value.trim();
    const itype = detectInputType(text);
    inputTypeBadge.textContent = BADGE_LABELS[itype] || "type to begin";
    compoundInput.classList.toggle("smiles-mode", itype === "smiles");
    hideAllResults();
    clearTimeout(autocompleteTimer);
    if (itype === "name" && text.length >= 2) {
      autocompleteTimer = setTimeout(() => fetchAutocomplete(text), 300);
    } else {
      closeAutocomplete();
    }
  });

  compoundInput.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); classifyBtn.click(); }
    if (e.key === "Escape") closeAutocomplete();
  });

  document.addEventListener("click", (e) => {
    if (!compoundInput.contains(e.target) && !autocompleteDropdown.contains(e.target))
      closeAutocomplete();
  });

  // ── Autocomplete ──────────────────────────────────────────────────────────
  async function fetchAutocomplete(query) {
    try {
      const { data: { session } } = await supabaseClient.auth.getSession();
      if (!session) return;
      const res = await fetch(`/api/drug/autocomplete?q=${encodeURIComponent(query)}`, {
        headers: { "Authorization": `Bearer ${session.access_token}` }
      });
      if (!res.ok) return;
      const data = await res.json();
      renderAutocomplete(data.suggestions || []);
    } catch (e) { /* silent */ }
  }

  function renderAutocomplete(suggestions) {
    if (!suggestions.length) { closeAutocomplete(); return; }
    autocompleteDropdown.innerHTML = "";
    suggestions.forEach(name => {
      const item = document.createElement("div");
      item.className = "autocomplete-item";
      item.innerHTML = `<span class="autocomplete-item-icon">🔍</span>${name}`;
      item.addEventListener("click", () => {
        compoundInput.value = name;
        inputTypeBadge.textContent = "compound name";
        compoundInput.classList.remove("smiles-mode");
        closeAutocomplete();
        compoundInput.focus();
      });
      autocompleteDropdown.appendChild(item);
    });
    autocompleteDropdown.style.display = "block";
  }

  function closeAutocomplete() {
    autocompleteDropdown.style.display = "none";
    autocompleteDropdown.innerHTML = "";
  }

  // ── Classify button ───────────────────────────────────────────────────────
  classifyBtn.addEventListener("click", async () => {
    const input = compoundInput.value.trim();
    if (!input) { showInlineError("Please enter a compound name or SMILES."); return; }

    const { data: { session } } = await supabaseClient.auth.getSession();
    if (!session) { document.getElementById("authModal").style.display = "flex"; return; }

    const itype = detectInputType(input);

    if (itype === "smiles") {
      // SMILES → classify directly, no preview
      await runClassification(input, false, session.access_token);
    } else {
      // Name / CAS / InChIKey → resolve first, show preview card
      await resolveAndPreview(input, session.access_token);
    }
  });

  // ── Step 1 (non-SMILES): resolve name → show preview card ────────────────
  async function resolveAndPreview(input, token) {
    closeAutocomplete();
    hideAllResults();
    showLoader(true);
    classifyBtn.disabled = true;

    try {
      const res = await fetch("/api/drug/classify", {
        method : "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
        body   : JSON.stringify({ input, preview_only: true }),
      });

      const data = await res.json();
      showLoader(false);
      classifyBtn.disabled = false;

      if (res.status === 404 || data.status === "not_found") {
        showNotFound(data); return;
      }

      if (data.status === "medicine_detected") {
        showMedicineCard(data, token); return;
      }

      if (data.status === "error" || (!res.ok && !data.smiles)) {
        showInlineError(data.message || "Resolution failed. Please try again."); return;
      }

      showCompoundPreviewCard(data, token);

    } catch (err) {
      showLoader(false);
      classifyBtn.disabled = false;
      showInlineError("Network error. Please check your connection.");
    }
  }

  // ── Preview card ──────────────────────────────────────────────────────────
  function showCompoundPreviewCard(data, token) {
    const name   = data.resolved_name || data.canonical_name || data.iupac_name || "Unknown";
    const smiles = data.smiles || "";

    pendingSmiles       = smiles;
    pendingResolvedName = name;
    pendingPreviewData  = data;    // store full resolved data for Know More enrichment

    previewCompoundName.textContent = name;
    previewSmilesText.textContent   = smiles.length > 72 ? smiles.slice(0, 70) + "…" : smiles;
    previewIupac.textContent        = data.iupac_name ? `IUPAC: ${data.iupac_name}` : "";

    if (smiles) {
      const imgUrl = `/api/drug/depict?smiles=${encodeURIComponent(smiles)}`;
      previewStructureImg.src     = imgUrl;
      previewStructureImg.style.display = "block";
      previewStructureImg.onerror = () => { previewStructureImg.style.display = "none"; };
    } else {
      previewStructureImg.style.display = "none";
    }

    compoundPreviewCard.style.display = "block";

    btnProceedAnalysis.onclick = async () => {
      compoundPreviewCard.style.display = "none";
      const { data: { session } } = await supabaseClient.auth.getSession();
      if (!session) return;
      await runClassification(pendingSmiles, false, session.access_token, pendingResolvedName);
    };

    btnCancelPreview.onclick = () => {
      compoundPreviewCard.style.display = "none";
      compoundInput.focus();
    };

    setTimeout(() => compoundPreviewCard.scrollIntoView({ behavior: "smooth", block: "center" }), 80);
  }

  // ── Step 2: run classification ────────────────────────────────────────────
  async function runClassification(input, confirmMedicine, token, resolvedNameHint) {
    closeAutocomplete();
    hideAllResults();
    showLoader(true);
    classifyBtn.disabled = true;

    try {
      const body = confirmMedicine
        ? { input, confirm_medicine: true }
        : { input };

      const res = await fetch("/api/drug/classify", {
        method : "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${token}` },
        body   : JSON.stringify(body),
      });

      const data = await res.json();
      showLoader(false);

      if (res.status === 404 || data.status === "not_found") {
        showNotFound(data); return;
      }
      if (data.status === "medicine_detected") {
        showMedicineCard(data, token); return;
      }
      if (!res.ok || data.status === "error" || data.error) {
        showInlineError(data.message || "Classification failed. Please try again."); return;
      }

      // Merge resolved name hint if backend didn't echo it back
      if (resolvedNameHint && !data.resolved_name) {
        data.resolved_name = resolvedNameHint;
      }

      // Enrich with iupac_name and active_compound from the preview resolution step.
      // The classify endpoint only returns model outputs for a raw SMILES, so
      // resolved_name / iupac_name / active_compound are absent for CAS and name
      // inputs unless we carry them forward from the preview response.
      if (pendingPreviewData) {
        if (!data.iupac_name) {
          data.iupac_name = pendingPreviewData.iupac_name || "";
        }
        if (!data.active_compound) {
          data.active_compound = pendingPreviewData.resolved_name
                                 || pendingPreviewData.canonical_name
                                 || "";
        }
        pendingPreviewData = null;
      }

      displayResults(data);

    } catch (err) {
      showLoader(false);
      showInlineError("Network error. Please check your connection and try again.");
    } finally {
      classifyBtn.disabled = false;
    }
  }

  // ── Medicine card ─────────────────────────────────────────────────────────
  function showMedicineCard(data, token) {
    const compound = data.active_compound || data.canonical_name || "—";
    const smiles   = data.smiles || "";
    currentMedicineSmiles = smiles;

    medicineCardSubtitle.textContent =
      `"${data.medicine_name}" is a pharmaceutical product. ` +
      `Its active compound is shown below. ` +
      `Click "Classify active compound" to proceed.`;

    medicineActiveCompound.textContent = compound;
    medicineSmiles.textContent = smiles.length > 60 ? smiles.slice(0, 58) + "…" : smiles;

    if (data.drug_indication) {
      medicineIndication.textContent  = `📋 ${data.drug_indication}`;
      medicineIndication.style.display= "block";
    } else {
      medicineIndication.style.display= "none";
    }

    if (smiles) {
      const imgUrl = `/api/drug/depict?smiles=${encodeURIComponent(smiles)}`;
      medicineStructureImg.src   = imgUrl;
      medicineStructureImg.style.display = "block";
      medicineStructureImg.onerror = () => { medicineStructureImg.style.display = "none"; };
    } else {
      medicineStructureImg.style.display = "none";
    }

    medicineCard.style.display = "block";

    btnClassifyActive.onclick = async () => {
      const { data: { session } } = await supabaseClient.auth.getSession();
      if (!session) return;
      medicineCard.style.display = "none";
      await runClassification(currentMedicineSmiles, true, session.access_token);
    };

    btnDismissMedicine.onclick = () => {
      medicineCard.style.display = "none";
      compoundInput.value = "";
      compoundInput.focus();
      inputTypeBadge.textContent = "type to begin";
    };
  }

  // ── Not found card ────────────────────────────────────────────────────────
  function showNotFound(data) {
    notFoundMsg.textContent = data.message || "Compound not found.";
    const suggestions = data.suggestions || [];
    if (suggestions.length) {
      suggestionsList.innerHTML = "";
      suggestions.forEach(name => {
        const chip = document.createElement("button");
        chip.className   = "suggestion-chip";
        chip.textContent = name;
        chip.onclick = () => {
          compoundInput.value = name;
          inputTypeBadge.textContent = "compound name";
          notFoundCard.style.display = "none";
          classifyBtn.click();
        };
        suggestionsList.appendChild(chip);
      });
      suggestionsArea.style.display = "block";
    } else {
      suggestionsArea.style.display = "none";
    }
    notFoundCard.style.display = "block";
  }

  // ── Results display ───────────────────────────────────────────────────────
  function displayResults(data) {
    lastClassifiedData = data;

    const classIdx = data.class_idx;
    const className= data.class_name;
    const conf     = data.confidence;
    const confPct  = data.confidence_percentage;
    const probs    = data.probabilities;

    resultBox.style.display  = "block";
    resultClass.innerHTML    = `${CLASS_ICONS[classIdx] || ""} ${className}`;
    resultConfidenceText.textContent = `Confidence: ${confPct}%`;

    if (data.resolved_name || data.iupac_name) {
      resultResolvedName.textContent = `Resolved: ${data.resolved_name || data.iupac_name}`;
    } else {
      resultResolvedName.textContent = "";
    }

    const typeLabels = {
      smiles: "SMILES input", compound_name: "name resolved",
      cas: "CAS resolved", inchikey: "InChIKey resolved"
    };
    if (data.input_type && typeLabels[data.input_type]) {
      resultInputType.textContent    = typeLabels[data.input_type];
      resultInputType.style.display  = "inline-block";
    } else {
      resultInputType.style.display  = "none";
    }

    confidenceBar.style.width = "0%";
    setTimeout(() => { confidenceBar.style.width = `${conf * 100}%`; }, 50);

    if (data.salt_warning) {
      saltWarning.textContent      = `⚠️ ${data.salt_warning}`;
      saltWarning.style.display    = "block";
    } else {
      saltWarning.style.display    = "none";
    }

    probabilitiesCard.style.display = "block";
    classBadge.textContent          = (data.class_short || "").toUpperCase();
    probabilitiesDesc.textContent   =
      `Confidence scores across all five natural product origin classes.` +
      (data.margin_based === false ? " (argmax fallback — low overall confidence)" : "");

    probClasses.innerHTML = "";
    for (let i = 0; i < 5; i++) {
      const probName  = CLASS_NAMES[i];
      const probValue = probs[probName] || 0;
      const probPct   = (probValue * 100).toFixed(1);
      const item = document.createElement("div");
      item.className = "prob-item";
      item.innerHTML = `
        <div class="prob-label">
          <span>${CLASS_ICONS[i]} ${probName}</span>
          <span class="prob-value">${probPct}%</span>
        </div>
        <div class="prob-bar-bg">
          <div class="prob-bar-fill" style="width:0%"></div>
        </div>`;
      probClasses.appendChild(item);
      setTimeout(() => {
        item.querySelector(".prob-bar-fill").style.width = `${probValue * 100}%`;
      }, 80 + i * 70);
    }

    resultsLayout.style.display = "flex";
    knowMoreBtn.style.display   = "inline-flex";
    knowMorePanel.style.display = "none";
    knowMoreContent.innerHTML   = "";

    setTimeout(() => resultsLayout.scrollIntoView({ behavior: "smooth", block: "start" }), 100);
  }

  // ── Know More (backend proxy — no API key in browser) ─────────────────────
  knowMoreBtn.addEventListener("click", async () => {
    if (!lastClassifiedData) return;

    // Toggle off
    if (knowMorePanel.style.display === "block") {
      knowMorePanel.style.display = "none";
      knowMoreBtn.textContent = "🔬 Know More";
      return;
    }

    knowMorePanel.style.display = "block";
    knowMoreBtn.textContent     = "✕ Close";
    knowMoreContent.innerHTML   =
      `<div class="know-more-loading"><span class="km-spinner"></span> Fetching compound insights…</div>`;

    setTimeout(() => knowMorePanel.scrollIntoView({ behavior: "smooth", block: "start" }), 80);

    const d = lastClassifiedData;

    // The raw input the user originally typed.
    const rawInput = compoundInput.value.trim();
    const rawInputType = detectInputType(rawInput);

    // ── FIX (v3.2): Build the Know More payload correctly ──────────────────
    // For name inputs the classify response carries resolved_name / iupac_name
    // / active_compound so we send those. For SMILES / CAS / InChIKey inputs
    // the classify response has none of these — sending rawInput as
    // compound_label caused the LLM to hallucinate. Instead we leave
    // compound_label empty and send the SMILES so the backend's PubChem
    // resolver can determine the real compound name before building the prompt.
    const humanReadableLabel = d.resolved_name || d.active_compound || d.iupac_name || "";
    const smilesForPayload   = d.smiles
      || (rawInputType === "smiles" ? rawInput : "");

    const payload = {
      resolved_name  : humanReadableLabel,
      // Only fall back to rawInput if it is NOT a structural identifier —
      // raw SMILES / CAS strings sent as compound_label cause hallucinations.
      compound_label : humanReadableLabel
                       || (rawInputType === "name" ? rawInput : ""),
      smiles         : smilesForPayload,
    };

    console.log("[know-more] sending:", {
      resolved_name  : d.resolved_name,
      active_compound: d.active_compound,
      iupac_name     : d.iupac_name,
      rawInput,
      rawInputType,
      payload,
    });

    try {
      const { data: { session } } = await supabaseClient.auth.getSession();
      if (!session) {
        knowMoreContent.innerHTML = `<div class="km-error">⚠️ Please log in to use Know More.</div>`;
        return;
      }

      const res = await fetch("/api/drug/know-more", {
        method : "POST",
        headers: {
          "Content-Type" : "application/json",
          "Authorization": `Bearer ${session.access_token}`,
        },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        knowMoreContent.innerHTML =
          `<div class="km-error">⚠️ ${err.error || "Could not load compound info. Please try again."}</div>`;
        return;
      }

      const data = await res.json();
      renderKnowMore(data.text || "No information available.");

    } catch (err) {
      knowMoreContent.innerHTML =
        `<div class="km-error">⚠️ Network error. Please check your connection and try again.</div>`;
    }
  });

  function renderKnowMore(markdown) {
    let html = markdown
      .replace(/^### (.+)$/gm, '<h4>$1</h4>')
      .replace(/^## (.+)$/gm, '<h3>$1</h3>')
      .replace(/^# (.+)$/gm, '<h2>$1</h2>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`(.+?)`/g, '<code>$1</code>')
      .replace(/^\d+\.\s+\*\*(.+?)\*\*\s*[—–-]\s*/gm,
        '<div class="km-section-header"><strong>$1</strong></div><p>')
      .replace(/\n\n/g, '</p><p>')
      .replace(/\n/g, '<br>');

    knowMoreContent.innerHTML = `<div class="km-body">${html}</div>`;
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  resetBtn.addEventListener("click", () => {
    compoundInput.value = "";
    inputTypeBadge.textContent = "type to begin";
    compoundInput.classList.remove("smiles-mode");
    hideAllResults();
    closeAutocomplete();
    currentMedicineSmiles = null;
    pendingSmiles         = null;
    pendingResolvedName   = null;
    pendingPreviewData    = null;
    lastClassifiedData    = null;
    knowMoreBtn.style.display   = "none";
    knowMorePanel.style.display = "none";
    compoundInput.focus();
  });

  // ── Example buttons ───────────────────────────────────────────────────────
  document.querySelectorAll(".example-btn").forEach(btn => {
    btn.addEventListener("click", () => {
      const input = btn.getAttribute("data-input");
      const itype = btn.getAttribute("data-type");
      compoundInput.value = input;
      inputTypeBadge.textContent = itype === "smiles" ? "SMILES" : "compound name";
      compoundInput.classList.toggle("smiles-mode", itype === "smiles");
      hideAllResults();
      closeAutocomplete();
      classifyBtn.focus();
    });
  });

  // ── Helpers ───────────────────────────────────────────────────────────────
  function showLoader(show) {
    loaderContainer.style.display = show ? "flex" : "none";
  }

  function hideAllResults() {
    resultsLayout.style.display      = "none";
    resultBox.style.display          = "none";
    probabilitiesCard.style.display  = "none";
    medicineCard.style.display       = "none";
    notFoundCard.style.display       = "none";
    saltWarning.style.display        = "none";
    compoundPreviewCard.style.display= "none";
    knowMoreBtn.style.display        = "none";
    knowMorePanel.style.display      = "none";
    document.querySelectorAll(".error-message").forEach(e => e.remove());
  }

  function showInlineError(message) {
    document.querySelectorAll(".error-message").forEach(e => e.remove());
    const err = document.createElement("div");
    err.className   = "error-message";
    err.textContent = `❌ ${message}`;
    document.querySelector(".detect-container").appendChild(err);
    setTimeout(() => err.remove(), 6000);
  }

  // ── Auth state ────────────────────────────────────────────────────────────
  (async () => {
    const { data: { session } } = await supabaseClient.auth.getSession();
    const authBtn = document.getElementById("authBtn");
    if (!session) {
      authBtn.style.display        = "block";
      classifyBtn.disabled         = true;
      classifyBtn.textContent      = "🔐 Login to Classify";
      classifyBtn.style.opacity    = "0.6";
      classifyBtn.style.cursor     = "not-allowed";
      authBtn.addEventListener("click", () => {
        document.getElementById("authModal").style.display = "flex";
      });
    } else {
      authBtn.style.display        = "none";
      classifyBtn.disabled         = false;
      classifyBtn.textContent      = "Classify Compound";
      classifyBtn.style.opacity    = "1";
      classifyBtn.style.cursor     = "pointer";
    }
  })();

});