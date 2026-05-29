import joblib
import numpy as np
import re
import os
import logging
import urllib.parse
from rdkit import Chem, DataStructs
from rdkit.Chem import AllChem, MACCSkeys
from rdkit import RDLogger

RDLogger.DisableLog('rdApp.*')

try:
    import requests as _requests
    _REQUESTS_AVAILABLE = True
except ImportError:
    import urllib.request
    import urllib.parse
    import json as _json
    _REQUESTS_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("PhytoAI-Service")


class DrugClassificationService:
    """
    PhytoAI: DrugClassificationService v7.4

    Medicine detection strategy (layered, in order of precision):

      1. KNOWN_NATURAL_COMPOUNDS whitelist  — fast O(1), never flag these
      2. Brand-name exact match             — hardcoded trade names
      3. Formulation language in input      — dosage-form keywords / mg dosage
      4. PubChem MeSH / pharmacology check  — if PubChem marks it as a drug
         AND the Title looks like a brand (short, diverges from IUPAC name)
      5. Title-vs-IUPAC heuristic           — last resort brand detection

    Pure natural compounds (quercetin, morphine, taxol, penicillin G, caffeine)
    are NEVER flagged regardless of pharmacological activity.
    """

    FP_RADIUS = 2
    FP_NBITS  = 1024
    USE_MACCS = True
    FP_DIM    = FP_NBITS + (167 if USE_MACCS else 0)

    CLASS_NAMES = {
        0: "Animal-derived",
        1: "Bacteria-derived",
        2: "Chromista-derived",
        3: "Fungi-derived",
        4: "Plant-derived",
    }
    CLASS_SHORT = {
        0: "Animal", 1: "Bacteria", 2: "Chromista", 3: "Fungi", 4: "Plant"
    }

    MODEL_PATH     = "model/np_classifier_v7_2.pkl"
    THRESHOLD_PATH = "model/thresholds_v7_2.npy"

    _model      = None
    _thresholds = None

    PUBCHEM_BASE    = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"
    PUBCHEM_TIMEOUT = 12

    # ──────────────────────────────────────────────────────────────────────────
    # RULE 1 GUARD: Well-known natural compound common names
    # These are NEVER flagged as medicines even if PubChem has drug data for them.
    # ──────────────────────────────────────────────────────────────────────────
    _KNOWN_NATURAL_COMPOUNDS = {
        # Alkaloids
        "morphine", "codeine", "caffeine", "theobromine", "theophylline",
        "cocaine", "nicotine", "quinine", "quinidine", "berberine",
        "colchicine", "vinblastine", "vincristine", "camptothecin",
        "ephedrine", "ergotamine", "strychnine", "atropine", "scopolamine",
        "pilocarpine", "reserpine", "yohimbine", "piperine", "capsaicin",
        # Terpenoids / diterpenes
        "taxol", "paclitaxel", "docetaxel", "artemisinin", "artemisin",
        "andrographolide", "betulinic acid", "ursolic acid", "oleanolic acid",
        "boswellic acid", "triptolide", "ginkgolide", "bilobalide",
        "linalool", "geraniol", "limonene", "menthol", "camphor", "borneol",
        "terpineol", "farnesol", "squalene", "β-caryophyllene", "abietic acid",
        # Flavonoids / polyphenols
        "quercetin", "kaempferol", "luteolin", "apigenin", "fisetin",
        "myricetin", "naringenin", "naringin", "hesperidin", "hesperetin",
        "rutin", "catechin", "epicatechin", "epigallocatechin",
        "epigallocatechin gallate", "egcg", "resveratrol", "pterostilbene",
        "curcumin", "genistein", "daidzein", "biochanin a", "formononetin",
        "chlorogenic acid", "caffeic acid", "rosmarinic acid", "ellagic acid",
        "gallic acid", "tannic acid", "ferulic acid", "sinapic acid",
        # Antibiotics (pure compounds, classifiable)
        "penicillin", "penicillin g", "penicillin v", "ampicillin",
        "amoxicillin", "cephalosporin", "streptomycin", "tetracycline",
        "doxycycline", "chloramphenicol", "erythromycin", "azithromycin",
        "vancomycin", "rifampicin", "rifamycin", "gentamicin", "kanamycin",
        "neomycin", "tobramycin", "ciprofloxacin", "lincomycin", "clindamycin",
        "novobiocin", "bacitracin", "polymyxin", "colistin", "gramicidin",
        # Steroids / sterols
        "cholesterol", "ergosterol", "sitosterol", "stigmasterol",
        "diosgenin", "hecogenin", "solasodine",
        "cortisol", "cortisone", "hydrocortisone", "prednisone",
        "dexamethasone", "betamethasone", "aldosterone", "testosterone",
        "estradiol", "estrone", "estriol", "progesterone", "pregnenolone",
        # Glycosides / cardiac
        "digoxin", "digitoxin", "ouabain", "strophanthidin",
        "ginsenoside", "astragaloside", "saponin",
        "vincamine", "vinpocetine",
        # Fatty acids / lipids
        "arachidonic acid", "eicosapentaenoic acid", "docosahexaenoic acid",
        "linoleic acid", "alpha-linolenic acid", "oleic acid",
        # Amino acids / peptides / neurotransmitters
        "theanine", "glutathione", "carnitine", "creatine",
        "serotonin", "dopamine", "adrenaline", "epinephrine", "norepinephrine",
        "acetylcholine", "histamine", "melatonin",
        # Vitamins (natural forms)
        "ascorbic acid", "tocopherol", "retinol", "calciferol",
        "riboflavin", "thiamine", "niacin", "pantothenic acid",
        # Misc natural
        "heparin", "chondroitin", "hyaluronic acid", "coenzyme q10",
        "ubiquinone",
        "lycopene", "beta-carotene", "astaxanthin", "lutein", "zeaxanthin",
        "allicin", "sulforaphane", "indole-3-carbinol",
        "betulin", "podophyllotoxin", "etoposide",
        "lovastatin", "simvastatin", "pravastatin", "mevastatin", "compactin",
        "cyclosporin", "cyclosporine", "tacrolimus", "rapamycin", "sirolimus",
        "mitomycin", "bleomycin", "doxorubicin", "adriamycin",
        "actinomycin", "actinomycin d",
        "aspirin", "ibuprofen", "acetaminophen", "paracetamol",
    }

    # ──────────────────────────────────────────────────────────────────────────
    # RULE 2: Exact lowercase brand / trade names
    # Only FORMULATED PRODUCTS, never pure compounds.
    # ──────────────────────────────────────────────────────────────────────────
    _BRAND_NAMES_EXACT = {
        # Pain/fever
        "tylenol", "advil", "motrin", "aleve", "aspirin bayer", "excedrin",
        "nurofen", "panadol", "calpol", "disprin",
        # Antibiotics (formulated brands only)
        "augmentin", "amoxil", "zithromax", "cipro", "flagyl", "keflex",
        "bactrim", "septra",
        # Cardiovascular
        "lipitor", "crestor", "zocor", "norvasc", "lopressor", "tenormin",
        "lasix", "aldactone", "plavix", "coumadin", "warfarin sodium",
        # Diabetes
        "glucophage", "metformin hcl", "januvia", "jardiance", "ozempic",
        # Antidepressants/CNS
        "prozac", "zoloft", "lexapro", "paxil", "effexor", "wellbutrin",
        "abilify", "seroquel", "risperdal", "zyprexa", "xanax", "valium",
        "ativan", "klonopin",
        # Oncology brands
        "gleevec", "herceptin", "avastin", "keytruda", "opdivo",
        # Steroids/hormones (formulated brands)
        "prednisone tablets", "medrol", "solu-medrol", "decadron",
        # Proton pump inhibitors
        "nexium", "prilosec", "prevacid", "protonix",
        # Other common brands
        "viagra", "cialis", "levitra", "tamiflu", "remdesivir",
        "hydroxychloroquine sulfate", "plaquenil",
    }

    # ──────────────────────────────────────────────────────────────────────────
    # RULE 3: Formulation language patterns in the input string.
    # Fires ONLY when the user's raw input contains pharmaceutical dosage-form
    # terminology. Pure compound names never contain these words.
    # ──────────────────────────────────────────────────────────────────────────
    _FORMULATION_PATTERNS = [
        r'\b(tablet|capsule|injection|syrup|suspension|solution|cream|ointment'
        r'|patch|inhaler|suppository|drops|lozenge|gel|spray|sachet|vial|ampoule)\b',
        r'\b(extended[- ]release|immediate[- ]release|sustained[- ]release'
        r'|delayed[- ]release|modified[- ]release|controlled[- ]release)\b',
        r'\b(film[- ]coated|enteric[- ]coated|effervescent|chewable|dispersible)\b',
        r'\d+\s*mg\b',          # dosage marker: "500mg" or "500 mg"
        r'\d+\s*mcg\b',
        r'\d+\s*ml\b',
        r'\b\d+\s*%\s*(w/v|v/v|w/w)\b',   # concentration notation
    ]
    _FORMULATION_RE = re.compile(
        '|'.join(_FORMULATION_PATTERNS), re.IGNORECASE
    )

    # Words/tokens that are purely formulation descriptors — stripped to get the
    # base compound name when the user types e.g. "paracetamol tablet 500mg".
    _STRIP_TOKENS_RE = re.compile(
        r'\b(tablet|capsule|injection|syrup|suspension|solution|cream|ointment'
        r'|patch|inhaler|suppository|drops|lozenge|gel|spray|sachet|vial|ampoule'
        r'|extended[- ]?release|immediate[- ]?release|sustained[- ]?release'
        r'|delayed[- ]?release|modified[- ]?release|controlled[- ]?release'
        r'|film[- ]?coated|enteric[- ]?coated|effervescent|chewable|dispersible'
        r'|oral|topical|intravenous|intramuscular|subcutaneous|transdermal'
        r'|bp|usp|ip|nf|ep)\b'     # pharmacopoeia suffixes
        r'|\d+\s*(mg|mcg|ml|g|iu)\b'   # dosage numbers
        r'|\b\d+\s*%\s*(w/v|v/v|w/w)\b',
        re.IGNORECASE
    )

    @classmethod
    def _strip_formulation_words(cls, text: str) -> str:
        """
        Remove dosage-form and strength tokens from an input string to recover
        the base compound name.
        e.g. "Paracetamol 500mg Tablet" → "Paracetamol"
             "amoxicillin 250 mg capsule" → "amoxicillin"
        """
        cleaned = cls._STRIP_TOKENS_RE.sub(' ', text)
        # collapse whitespace and strip trailing punctuation/spaces
        cleaned = re.sub(r'\s+', ' ', cleaned).strip().strip(',-.')
        return cleaned

    # ──────────────────────────────────────────────────────────────────────────
    # RULE 4 helper: PubChem pharmacology / MeSH drug check.
    # Fetches the PubChem "Pharmacology and Biochemistry" section heading list.
    # If present AND the compound is not a known natural product → medicine.
    # We use the lightweight /section/headings endpoint (one extra HTTP call).
    # ──────────────────────────────────────────────────────────────────────────
    # Heading strings that indicate a formulated drug, not just a bioactive natural cpd.
    _DRUG_MESH_HEADINGS = {
        "drug and medication information",
        "clinical trials",
        "fda orange book",
        "who essential medicines",
        "ndc/package code",
        "drug labels",
        "daily med",
        "prescribing information",
        "approved drug products",
    }

    @classmethod
    def _fetch_pubchem_headings(cls, cid: int) -> set:
        """
        Returns a lowercased set of section heading strings for a CID from
        PubChem's full compound JSON (section titles only, not content).
        Uses the lightweight 'headings' view to avoid large payloads.
        Returns empty set on any failure.
        """
        url = (
            f"https://pubchem.ncbi.nlm.nih.gov/rest/pug_view/data/compound"
            f"/{cid}/JSON?heading=Drug+and+Medication+Information"
        )
        try:
            data = cls._pubchem_get(url)
            if not data:
                return set()
            # If the response has any content at all under this heading, it's
            # registered as a drug in PubChem's curated database.
            record = data.get("Record", {})
            sections = record.get("Section", [])
            headings = set()
            for sec in sections:
                h = sec.get("TOCHeading", "").lower()
                headings.add(h)
                for sub in sec.get("Section", []):
                    headings.add(sub.get("TOCHeading", "").lower())
            return headings
        except Exception:
            return set()

    @classmethod
    def _pubchem_has_drug_info(cls, cid: int) -> bool:
        """
        Returns True if PubChem's curated drug-and-medication-information
        section exists for this CID (i.e. it is a registered pharmaceutical).
        Pure natural compounds generally have no entry here.
        """
        headings = cls._fetch_pubchem_headings(cid)
        return bool(headings & cls._DRUG_MESH_HEADINGS)

    # ── Model Initialization ──────────────────────────────────────────────

    @classmethod
    def load_model(cls):
        if cls._model is None:
            if not os.path.exists(cls.MODEL_PATH) or not os.path.exists(cls.THRESHOLD_PATH):
                raise FileNotFoundError(
                    "Required model files (np_classifier_v7_2.pkl, thresholds_v7_2.npy) not found."
                )
            cls._model      = joblib.load(cls.MODEL_PATH)
            cls._thresholds = np.load(cls.THRESHOLD_PATH)
            logger.info(f"✅ Model v7.2 Loaded. Thresholds: {cls._thresholds.round(3)}")
        return cls._model, cls._thresholds

    # ── Input Type Detection ──────────────────────────────────────────────

    _CAS_RE    = re.compile(r'^\d{2,7}-\d{2}-\d$')
    _INCHI_RE  = re.compile(r'^[A-Z]{14}-[A-Z]{10}-[A-Z]$')
    _SMILES_CHR= set("CNOSPFBrIlcnospfbh()[]=@+-.#\\/0123456789%")

    @classmethod
    def detect_input_type(cls, text: str) -> str:
        t = text.strip()
        if not t: return "empty"
        if cls._CAS_RE.fullmatch(t):   return "cas"
        if cls._INCHI_RE.fullmatch(t): return "inchikey"
        if Chem.MolFromSmiles(t) is not None: return "smiles"
        s_count = sum(1 for c in t if c in cls._SMILES_CHR)
        if s_count / max(len(t), 1) > 0.65: return "smiles"
        return "text"

    # ── Fingerprint ───────────────────────────────────────────────────────

    @classmethod
    def smiles_to_fingerprint(cls, smiles: str):
        smiles   = smiles.strip()
        warning  = None
        mol      = None
        try:
            if '.' in smiles:
                frags = [Chem.MolFromSmiles(f) for f in smiles.split('.')]
                frags = [f for f in frags if f is not None]
                if not frags: return None, None, None
                mol = max(frags, key=lambda x: x.GetNumHeavyAtoms())
                warning = "Salt/mixture detected; analysed largest organic fragment."
            else:
                mol = Chem.MolFromSmiles(smiles)
            if mol is None: return None, None, None

            canonical = Chem.MolToSmiles(mol)
            arr = np.zeros((1, cls.FP_DIM), dtype=np.float32)

            ecfp = AllChem.GetMorganFingerprintAsBitVect(mol, cls.FP_RADIUS, nBits=cls.FP_NBITS)
            DataStructs.ConvertToNumpyArray(ecfp, arr[0, :cls.FP_NBITS])

            if cls.USE_MACCS:
                maccs = MACCSkeys.GenMACCSKeys(mol)
                m_arr = np.zeros(167, dtype=np.float32)
                DataStructs.ConvertToNumpyArray(maccs, m_arr)
                arr[0, cls.FP_NBITS:] = m_arr

            return arr, canonical, warning
        except Exception as e:
            logger.warning(f"Fingerprint generation failed: {e}")
            return None, None, None

    # ── PubChem HTTP ──────────────────────────────────────────────────────

    @classmethod
    def _pubchem_get(cls, url: str):
        headers = {"User-Agent": "PhytoAI/2.0 (Research)", "Accept": "application/json"}
        try:
            if _REQUESTS_AVAILABLE:
                r = _requests.get(url, headers=headers, timeout=cls.PUBCHEM_TIMEOUT)
                if r.status_code == 404: return None
                r.raise_for_status()
                data = r.json()
            else:
                import ssl, json as _json
                req = urllib.request.Request(url, headers=headers)
                ctx = ssl.create_default_context()
                with urllib.request.urlopen(req, timeout=cls.PUBCHEM_TIMEOUT, context=ctx) as resp:
                    data = _json.loads(resp.read().decode())
            return None if "Fault" in data else data
        except Exception:
            return None

    @classmethod
    def _resolve_name_to_cid(cls, name: str):
        clean = urllib.parse.quote(name.strip())
        url   = f"{cls.PUBCHEM_BASE}/compound/name/{clean}/cids/JSON"
        data  = cls._pubchem_get(url)
        try:
            return int(data["IdentifierList"]["CID"][0]) if data else None
        except (KeyError, IndexError, TypeError):
            return None

    @classmethod
    def _fetch_properties_by_cid(cls, cid: int):
        url  = f"{cls.PUBCHEM_BASE}/compound/cid/{cid}/property/IsomericSMILES,CanonicalSMILES,IUPACName,Title/JSON"
        data = cls._pubchem_get(url)
        if not data: return None
        try:
            props = data["PropertyTable"]["Properties"][0]
            if not (props.get("IsomericSMILES") or props.get("CanonicalSMILES")):
                fallback = cls._pubchem_get(
                    f"{cls.PUBCHEM_BASE}/compound/cid/{cid}/property/SMILES/JSON"
                )
                if fallback:
                    fb = fallback["PropertyTable"]["Properties"][0]
                    props["CanonicalSMILES"] = fb.get("SMILES", "")
            return props
        except Exception:
            return None

    # ──────────────────────────────────────────────────────────────────────────
    # CORE MEDICINE DETECTION  (layered, v7.4)
    # ──────────────────────────────────────────────────────────────────────────

    @classmethod
    def _is_medicine_input(
        cls,
        user_input: str,
        pubchem_title: str,
        iupac_name: str,
        cid: int | None = None,
    ) -> tuple[bool, str | None]:
        """
        Decide whether the user's input is a formulated pharmaceutical product.

        Layer 0  — KNOWN_NATURAL_COMPOUNDS whitelist (always pass-through)
        Layer 1  — Exact brand-name match
        Layer 2  — Formulation-language in the raw input string
        Layer 3  — PubChem "Drug and Medication Information" section present
                   AND PubChem Title looks like a trade name (short, diverges
                   from IUPAC) — this catches branded drugs not in our list
        Layer 4  — Title-vs-IUPAC heuristic (last resort)

        Returns (is_medicine: bool, indication_text: str | None)
        """
        inp   = user_input.strip().lower()
        title = (pubchem_title or "").strip().lower()

        # ── Layer 0: whitelist guard — never flag known natural compounds ──
        if inp in cls._KNOWN_NATURAL_COMPOUNDS:
            return False, None

        # ── Layer 1: exact brand name ──────────────────────────────────────
        if inp in cls._BRAND_NAMES_EXACT:
            return True, f"Brand name pharmaceutical: {pubchem_title}"

        # ── Layer 2: formulation language in the user's raw input ──────────
        # Only fires when the user explicitly typed dosage-form words or mg
        # amounts in the compound name — real compound names never do this.
        if cls._FORMULATION_RE.search(inp):
            return True, f"Formulated pharmaceutical product: {pubchem_title}"

        # ── Layer 3: PubChem drug-and-medication-information section check ──
        # Makes one extra HTTP call to PubChem's pug_view endpoint.
        # Only triggered when CID is available and title looks brand-like.
        if cid and title and iupac_name:
            iupac_l    = iupac_name.lower()
            title_words= set(title.replace('-', ' ').split())
            iupac_words= set(iupac_l.replace('-', ' ').split())
            overlap    = title_words & iupac_words
            similarity = len(overlap) / max(len(title_words), 1)

            # Title looks brand-like: short, doesn't look systematic, low overlap with IUPAC
            is_iupac_like = (
                any(c in title for c in ['(', ')', ','])
                or len(title) > 35
                or title.count('-') > 3
            )
            title_is_brand_like = (
                not is_iupac_like
                and similarity < 0.15
                and len(title) < 25
            )

            if title_is_brand_like:
                # Now pay the extra HTTP cost to verify via PubChem drug DB
                if cls._pubchem_has_drug_info(cid):
                    return True, f"Registered pharmaceutical (PubChem drug record): {pubchem_title}"

        # ── Layer 4: Title-vs-IUPAC heuristic (last resort, no HTTP call) ──
        # Only fires when the user typed exactly the PubChem trade-name title
        # AND it is very short AND very different from IUPAC.
        if title and iupac_name:
            iupac_l    = iupac_name.lower()
            title_words= set(title.replace('-', ' ').split())
            iupac_words= set(iupac_l.replace('-', ' ').split())
            overlap    = title_words & iupac_words
            similarity = len(overlap) / max(len(title_words), 1)
            is_iupac_like = any(c in title for c in ['(', ')', '-', ',']) or len(title) > 30

            if (
                not is_iupac_like
                and similarity < 0.15
                and len(title) < 20
                and inp == title
            ):
                return True, f"Trade-name pharmaceutical: {pubchem_title}"

        return False, None

    # ── Autocomplete ──────────────────────────────────────────────────────

    @classmethod
    def get_autocomplete_suggestions(cls, prefix: str, limit: int = 6) -> list:
        if len(prefix) < 3: return []
        encoded = urllib.parse.quote(prefix.strip())
        url  = f"https://pubchem.ncbi.nlm.nih.gov/rest/autocomplete/compound/{encoded}/JSON?limit={limit}"
        data = cls._pubchem_get(url)
        try:
            return data.get("dictionary_terms", {}).get("compound", []) if data else []
        except Exception:
            return []

    # ── Name → SMILES resolution ──────────────────────────────────────────

    @classmethod
    def resolve_name_to_smiles(cls, name: str) -> dict:
        """
        Orchestrates name → CID → SMILES resolution with layered medicine detection.

        PRE-PUBCHEM CHECK: If the input already contains formulation language
        (e.g. "paracetamol tablet", "amoxicillin 500mg capsule"), we strip the
        formulation words, resolve the base compound, and return is_medicine=True
        WITHOUT failing with not_found. This is the fix for the "paracetamol
        tablet → not found" bug.
        """
        inp = name.strip()
        inp_lower = inp.lower()

        # ── Pre-PubChem Layer 0+1+2 checks (no HTTP needed) ─────────────────
        # Layer 0: known natural compound — even with formulation words, if the
        # base name after stripping is a known natural compound, treat as medicine
        # (the natural compound IS the active ingredient of the formulation).
        # Layer 1: exact brand name
        if inp_lower in cls._BRAND_NAMES_EXACT:
            # Resolve the brand name directly for its SMILES
            cid = cls._resolve_name_to_cid(inp)
            if cid:
                props = cls._fetch_properties_by_cid(cid)
                if props:
                    smiles = (props.get("IsomericSMILES") or props.get("CanonicalSMILES") or "").strip()
                    pub_title  = props.get("Title", inp)
                    iupac_name = props.get("IUPACName", "")
                    if smiles:
                        return {
                            "found": True, "smiles": smiles, "cid": cid,
                            "canonical_name": pub_title, "iupac_name": iupac_name,
                            "is_medicine": True,
                            "drug_indication": f"Brand name pharmaceutical: {pub_title}",
                            "active_compound": iupac_name or pub_title or inp,
                        }
            # Brand name but PubChem couldn't give SMILES — still flag as medicine
            return {
                "found": True, "smiles": "", "cid": None,
                "canonical_name": inp, "iupac_name": "",
                "is_medicine": True,
                "drug_indication": f"Brand name pharmaceutical: {inp}",
                "active_compound": inp,
            }

        # Layer 2: formulation language detected in raw input
        # Strip formulation words → get base compound name → resolve that instead
        if cls._FORMULATION_RE.search(inp_lower):
            base_name = cls._strip_formulation_words(inp)
            if base_name and base_name.lower() != inp_lower:
                # Resolve the base compound (e.g. "paracetamol" from "paracetamol tablet")
                base_cid = cls._resolve_name_to_cid(base_name)
                if base_cid:
                    props = cls._fetch_properties_by_cid(base_cid)
                    if props:
                        smiles = (props.get("IsomericSMILES") or props.get("CanonicalSMILES") or "").strip()
                        pub_title  = props.get("Title", base_name)
                        iupac_name = props.get("IUPACName", "")
                        if smiles:
                            return {
                                "found": True, "smiles": smiles, "cid": base_cid,
                                "canonical_name": pub_title, "iupac_name": iupac_name,
                                "is_medicine": True,
                                "drug_indication": f"Formulated pharmaceutical product: {inp}",
                                "active_compound": iupac_name or pub_title or base_name,
                            }
            # Has formulation words but couldn't strip/resolve — still flag
            return {
                "found": False, "error": "not_found",
                "is_medicine_hint": True,   # hint for caller
                "suggestions": cls.get_autocomplete_suggestions(
                    cls._strip_formulation_words(inp) or inp
                ),
            }

        # ── Standard path: no pre-check triggered → resolve full name ────────
        cid = cls._resolve_name_to_cid(inp)
        if cid is None:
            return {
                "found": False, "error": "not_found",
                "suggestions": cls.get_autocomplete_suggestions(inp)
            }

        props = cls._fetch_properties_by_cid(cid)
        if not props:
            return {"found": False, "error": "props_missing"}

        smiles = (props.get("IsomericSMILES") or props.get("CanonicalSMILES") or "").strip()
        if not smiles:
            return {
                "found": False, "error": "no_smiles",
                "message": f"PubChem found '{name}' (CID {cid}) but has no SMILES. May be a mixture/polymer."
            }

        pub_title  = props.get("Title", name)
        iupac_name = props.get("IUPACName", "")

        # Pass CID into medicine detection so Layer 3 can use PubChem drug DB
        is_med, indication = cls._is_medicine_input(name, pub_title, iupac_name, cid=cid)

        return {
            "found"          : True,
            "smiles"         : smiles,
            "cid"            : cid,
            "canonical_name" : pub_title,
            "iupac_name"     : iupac_name,
            "is_medicine"    : is_med,
            "drug_indication": indication,
            "active_compound": iupac_name or pub_title or name,
        }

    # ── Prediction ────────────────────────────────────────────────────────

    @classmethod
    def _margin_predict(cls, probs: np.ndarray, thresholds: np.ndarray) -> tuple[int, bool]:
        margins = probs - thresholds
        if margins.max() >= 0:
            return int(margins.argmax()), True
        return int(probs.argmax()), False

    @classmethod
    def is_inorganic(cls, smiles: str) -> bool:
        try:
            mol = Chem.MolFromSmiles(smiles)
            if mol is None: return False
            return "C" not in [a.GetSymbol() for a in mol.GetAtoms()]
        except Exception:
            return False

    @classmethod
    def predict(cls, smiles: str) -> dict:
        fp, canonical, salt_warning = cls.smiles_to_fingerprint(smiles)
        if fp is None:
            return {"valid": False, "error": "parse_error", "message": "Invalid SMILES structure."}
        try:
            model, thresholds = cls.load_model()
            probs = model.predict_proba(fp)[0]
            idx, used_margin = cls._margin_predict(probs, thresholds)
            conf = float(probs[idx])
            return {
                "valid"                : True,
                "class_idx"            : idx,
                "class_name"           : cls.CLASS_NAMES[idx],
                "class_short"          : cls.CLASS_SHORT[idx],
                "confidence"           : conf,
                "confidence_percentage": round(conf * 100, 1),
                "probabilities"        : {cls.CLASS_NAMES[i]: float(probs[i]) for i in range(5)},
                "smiles"               : canonical or smiles,
                "margin_based"         : used_margin,
                "salt_warning"         : salt_warning,
            }
        except Exception as e:
            return {"valid": False, "error": "model_error", "message": str(e)}

    # ── Public Pipeline ───────────────────────────────────────────────────

    @classmethod
    def resolve_and_predict(cls, user_input: str) -> dict:
        """Unified entry point for all classification requests."""
        if not user_input or not user_input.strip():
            return {"status": "error", "message": "No input provided."}

        text  = user_input.strip()
        itype = cls.detect_input_type(text)

        # Heparin override (always animal — no SMILES parse needed)
        if "heparin" in text.lower():
            return {
                "status"               : "classified",
                "input_type"           : "override",
                "resolved_name"        : text,
                "class_name"           : "Animal-derived",
                "class_short"          : "Animal",
                "confidence"           : 0.92,
                "confidence_percentage": 92.0,
                "probabilities"        : {
                    "Animal-derived": 0.92, "Bacteria-derived": 0.03,
                    "Chromista-derived": 0.01, "Fungi-derived": 0.01, "Plant-derived": 0.03,
                },
                "message": "Rule-based: Heparin compounds are animal-derived.",
            }

        # Direct SMILES
        if itype == "smiles":
            res = cls.predict(text)
            res.update({"status": "classified" if res["valid"] else "error", "input_type": "smiles"})
            return res

        # Name / CAS / InChIKey → resolve
        resolved = cls.resolve_name_to_smiles(text)
        if not resolved["found"]:
            # Special case: formulation words were detected but base compound
            # couldn't be resolved either → still tell user it looks like a medicine
            if resolved.get("is_medicine_hint"):
                base = cls._strip_formulation_words(text)
                return {
                    "status"         : "medicine_detected",
                    "input_type"     : "medicine",
                    "medicine_name"  : text,
                    "active_compound": base or text,
                    "canonical_name" : base or text,
                    "smiles"         : "",
                    "drug_indication": f"Formulated pharmaceutical product: {text}",
                    "message"        : f"'{text}' appears to be a pharmaceutical formulation.",
                    "suggestions"    : resolved.get("suggestions", []),
                }
            return {
                "status"    : "not_found",
                "input_type": itype,
                "message"   : resolved.get("message", f"'{text}' not found in database."),
                "suggestions": resolved.get("suggestions", []),
            }

        # Medicine intercept
        if resolved.get("is_medicine"):
            return {
                "status"         : "medicine_detected",
                "input_type"     : "medicine",
                "medicine_name"  : text,
                "active_compound": resolved["active_compound"],
                "canonical_name" : resolved["canonical_name"],
                "smiles"         : resolved["smiles"],
                "drug_indication": resolved["drug_indication"],
                "message"        : f"'{text}' is a pharmaceutical product.",
            }

        # Inorganic check
        if cls.is_inorganic(resolved["smiles"]):
            return {
                "status"        : "inorganic",
                "input_type"    : "compound_name",
                "resolved_name" : resolved["canonical_name"],
                "smiles"        : resolved["smiles"],
                "message"       : "Inorganic compound (no carbon atoms).",
                "classification": "Inorganic",
            }

        # Classify
        res = cls.predict(resolved["smiles"])
        res.update({
            "status"       : "classified" if res["valid"] else "error",
            "input_type"   : "compound_name",
            "resolved_name": resolved["canonical_name"],
            "iupac_name"   : resolved["iupac_name"],
        })
        return res