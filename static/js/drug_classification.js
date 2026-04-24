// ============================================================================
// DRUG CLASSIFICATION FRONTEND (v2.0)
// Handles: compound names, SMILES, CAS, medicine detection, autocomplete,
// structure preview, salt warnings, suggestions, and all edge cases.
// ============================================================================

document.addEventListener("DOMContentLoaded", () => {

  // ── Elements ──────────────────────────────────────────────────────────────
  const compoundInput       = document.getElementById("compoundInput");
  const classifyBtn         = document.getElementById("classifyBtn");
  const resetBtn            = document.getElementById("resetBtn");
  const loaderContainer     = document.getElementById("loaderContainer");
  const resultsLayout       = document.getElementById("resultsLayout");
  const inputTypeBadge      = document.getElementById("inputTypeBadge");
  const autocompleteDropdown= document.getElementById("autocompleteDropdown");
  const structurePreview    = document.getElementById("structurePreview");
  const structureImg        = document.getElementById("structureImg");
  const structurePreviewName= document.getElementById("structurePreviewName");
  const structurePreviewInfo= document.getElementById("structurePreviewInfo");
  const saltWarning         = document.getElementById("saltWarning");

  // Result elements
  const resultBox           = document.getElementById("resultBox");
  const resultClass         = document.getElementById("resultClass");
  const resultConfidenceText= document.getElementById("resultConfidenceText");
  const confidenceBar       = document.getElementById("confidenceBar");
  const resultResolvedName  = document.getElementById("resultResolvedName");
  const resultInputType     = document.getElementById("resultInputType");
  const probClasses         = document.getElementById("probClasses");
  const probabilitiesCard   = document.getElementById("probabilitiesCard");
  const classBadge          = document.getElementById("classBadge");
  const probabilitiesDesc   = document.getElementById("probabilitiesDesc");

  // Medicine card elements
  const medicineCard        = document.getElementById("medicineCard");
  const medicineCardSubtitle= document.getElementById("medicineCardSubtitle");
  const medicineActiveCompound= document.getElementById("medicineActiveCompound");
  const medicineSmiles      = document.getElementById("medicineSmiles");
  const medicineStructureImg= document.getElementById("medicineStructureImg");
  const medicineIndication  = document.getElementById("medicineIndication");
  const btnClassifyActive   = document.getElementById("btnClassifyActive");
  const btnDismissMedicine  = document.getElementById("btnDismissMedicine");

  // Not found card
  const notFoundCard        = document.getElementById("notFoundCard");
  const notFoundMsg         = document.getElementById("notFoundMsg");
  const suggestionsArea     = document.getElementById("suggestionsArea");
  const suggestionsList     = document.getElementById("suggestionsList");

  // ── Constants ─────────────────────────────────────────────────────────────
  const CLASS_NAMES = {
    0: "Animal-derived", 1: "Bacteria-derived", 2: "Chromista-derived",
    3: "Fungi-derived",  4: "Plant-derived",
  };
  const CLASS_ICONS = { 0:"🦁", 1:"🦠", 2:"🌊", 3:"🍄", 4:"🌿" };

  // SMILES heuristic (mirrors backend)
  const SMILES_CHARS = new Set("CNOSPFBrIlc()[]=@+-.#\\/0123456789%");
  const CAS_REGEX    = /^\d{2,7}-\d{2}-\d$/;
  const INCHIKEY_REGEX = /^[A-Z]{14}-[A-Z]{10}-[A-Z]$/;

  // State
  let autocompleteTimer = null;
  let currentMedicineSmiles = null;  // stored when medicine card is shown

  // ── Input type detection (live, frontend) ─────────────────────────────────
  function detectInputType(text) {
    text = text.trim();
    if (!text) return null;
    if (CAS_REGEX.test(text))     return "cas";
    if (INCHIKEY_REGEX.test(text)) return "inchikey";
    const ratio = [...text].filter(c => SMILES_CHARS.has(c)).length / text.length;
    if (ratio > 0.55)             return "smiles";
    return "name";
  }

  const BADGE_LABELS = {
    cas: "CAS number", inchikey: "InChIKey", smiles: "SMILES", name: "compound name", null: "type to begin"
  };

  // ── Live input handling ───────────────────────────────────────────────────
  compoundInput.addEventListener("input", () => {
    const text = compoundInput.value.trim();

    // Update type badge
    const itype = detectInputType(text);
    inputTypeBadge.textContent = BADGE_LABELS[itype] || "type to begin";

    // Toggle monospace for SMILES
    compoundInput.classList.toggle("smiles-mode", itype === "smiles");

    // Hide previous results and cards when user starts re-typing
    hideAllResults();

    // Autocomplete only for name type
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

  // Close autocomplete on outside click
  document.addEventListener("click", (e) => {
    if (!compoundInput.contains(e.target) && !autocompleteDropdown.contains(e.target)) {
      closeAutocomplete();
    }
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
    } catch (e) { /* silently fail */ }
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

    await runClassification(input, false, session.access_token);
  });

  // ── Main classification function ──────────────────────────────────────────
  async function runClassification(input, confirmMedicine, token) {
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
        showNotFound(data);
        return;
      }

      if (data.status === "medicine_detected") {
        showMedicineCard(data, token);
        return;
      }

      if (!res.ok || data.status === "error" || data.error) {
        showInlineError(data.message || "Classification failed. Please try again.");
        return;
      }

      // Success
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

    // Drug indication
    if (data.drug_indication) {
      medicineIndication.textContent = `📋 ${data.drug_indication}`;
      medicineIndication.style.display = "block";
    } else {
      medicineIndication.style.display = "none";
    }

    // Structure preview image
    if (smiles) {
      const imgUrl = `/api/drug/depict?smiles=${encodeURIComponent(smiles)}`;
      medicineStructureImg.src   = imgUrl;
      medicineStructureImg.style.display = "block";
      medicineStructureImg.onerror = () => { medicineStructureImg.style.display = "none"; };
    } else {
      medicineStructureImg.style.display = "none";
    }

    medicineCard.style.display = "block";

    // "Classify active compound" button
    btnClassifyActive.onclick = async () => {
      const { data: { session } } = await supabaseClient.auth.getSession();
      if (!session) return;
      medicineCard.style.display = "none";
      await runClassification(currentMedicineSmiles, true, session.access_token);
    };

    // "Enter manually" button
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
        chip.className = "suggestion-chip";
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
    const classIdx  = data.class_idx;
    const className = data.class_name;
    const conf      = data.confidence;
    const confPct   = data.confidence_percentage;
    const probs     = data.probabilities;

    // Left: result box
    resultBox.style.display = "block";
    resultClass.innerHTML   = `${CLASS_ICONS[classIdx] || ""} ${className}`;
    resultConfidenceText.textContent = `Confidence: ${confPct}%`;

    // Resolved name
    if (data.resolved_name || data.iupac_name) {
      resultResolvedName.textContent =
        `Resolved: ${data.resolved_name || data.iupac_name}`;
    } else {
      resultResolvedName.textContent = "";
    }

    // Input type badge
    const typeLabels = {
      smiles: "SMILES input", compound_name: "name resolved", cas: "CAS resolved",
      inchikey: "InChIKey resolved"
    };
    if (data.input_type && typeLabels[data.input_type]) {
      resultInputType.textContent = typeLabels[data.input_type];
      resultInputType.style.display = "inline-block";
    } else {
      resultInputType.style.display = "none";
    }

    // Animate confidence bar
    confidenceBar.style.width = "0%";
    setTimeout(() => { confidenceBar.style.width = `${conf * 100}%`; }, 50);

    // Salt warning
    if (data.salt_warning) {
      saltWarning.textContent = `⚠️ ${data.salt_warning}`;
      saltWarning.style.display = "block";
    } else {
      saltWarning.style.display = "none";
    }

    // Right: probabilities
    probabilitiesCard.style.display = "block";
    classBadge.textContent = (data.class_short || "").toUpperCase();
    probabilitiesDesc.textContent =
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

    // Scroll to results
    setTimeout(() => resultsLayout.scrollIntoView({ behavior: "smooth", block: "start" }), 100);
  }

  // ── Reset ─────────────────────────────────────────────────────────────────
  resetBtn.addEventListener("click", () => {
    compoundInput.value = "";
    inputTypeBadge.textContent = "type to begin";
    compoundInput.classList.remove("smiles-mode");
    hideAllResults();
    closeAutocomplete();
    currentMedicineSmiles = null;
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
    resultsLayout.style.display    = "none";
    resultBox.style.display        = "none";
    probabilitiesCard.style.display= "none";
    medicineCard.style.display     = "none";
    notFoundCard.style.display     = "none";
    saltWarning.style.display      = "none";
    structurePreview.style.display = "none";
    // Remove inline errors
    document.querySelectorAll(".error-message").forEach(e => e.remove());
  }

  function showInlineError(message) {
    document.querySelectorAll(".error-message").forEach(e => e.remove());
    const err = document.createElement("div");
    err.className = "error-message";
    err.textContent = `❌ ${message}`;
    document.querySelector(".detect-container").appendChild(err);
    setTimeout(() => err.remove(), 6000);
  }

  // ── Auth state ────────────────────────────────────────────────────────────
  (async () => {
    const { data: { session } } = await supabaseClient.auth.getSession();
    const authBtn = document.getElementById("authBtn");

    if (!session) {
      authBtn.style.display = "block";
      classifyBtn.disabled  = true;
      classifyBtn.textContent = "🔐 Login to Classify";
      classifyBtn.style.opacity = "0.6";
      classifyBtn.style.cursor  = "not-allowed";
      authBtn.addEventListener("click", () => {
        document.getElementById("authModal").style.display = "flex";
      });
    } else {
      authBtn.style.display   = "none";
      classifyBtn.disabled    = false;
      classifyBtn.textContent = "Classify Compound";
      classifyBtn.style.opacity = "1";
      classifyBtn.style.cursor  = "pointer";
    }
  })();

});