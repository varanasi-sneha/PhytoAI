import joblib
import numpy as np
import re
import os
import logging
import urllib.parse
from rdkit import Chem, DataStructs
from rdkit.Chem import AllChem, MACCSkeys
from rdkit import RDLogger

# Disable RDKit warnings for clean production logs
RDLogger.DisableLog('rdApp.*')

# --- HTTP Backend Selection ---
try:
    import requests as _requests
    _REQUESTS_AVAILABLE = True
except ImportError:
    import urllib.request
    import urllib.request
    import urllib.parse
    import json as _json
    _REQUESTS_AVAILABLE = False

# --- Logging Configuration ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("PhytoAI-Service")

class DrugClassificationService:
    """
    PhytoAI: DrugClassificationService v7.2
    
    A high-performance pipeline for classifying natural drug compounds 
    into biological domains (Plant, Fungi, Bacteria, etc.) using 
    LightGBM and hybrid Morgan/MACCS fingerprints.
    
    Integrated Fixes:
    - 2-Step PubChem CID-to-SMILES Resolution (Solves missing SMILES bug)
    - Pharmaceutical Detection (MeSH/ATC/FDA scan)
    - Salt & Mixture Fragment Isolation
    - Margin-based calibrated thresholding
    """

    # --- Feature Constants ---
    FP_RADIUS = 2
    FP_NBITS  = 1024
    USE_MACCS = True
    FP_DIM    = FP_NBITS + (167 if USE_MACCS else 0)  # Total 1191

    # --- Classification Mappings ---
    CLASS_NAMES = {
        0: "Animal-derived",
        1: "Bacteria-derived",
        2: "Chromista-derived",
        3: "Fungi-derived",
        4: "Plant-derived",
    }
    
    CLASS_SHORT = {
        0: "Animal",
        1: "Bacteria",
        2: "Chromista",
        3: "Fungi",
        4: "Plant"
    }

    # --- Resource Paths ---
    MODEL_PATH     = "model/np_classifier_v7_2.pkl"
    THRESHOLD_PATH = "model/thresholds_v7_2.npy"

    # --- State Management ---
    _model      = None
    _thresholds = None

    # --- API Config ---
    PUBCHEM_BASE    = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"
    PUBCHEM_TIMEOUT = 12 

    # ── Model Initialization ──────────────────────────────────────────────
    
    @classmethod
    def load_model(cls):
        """Lazy loader for the LightGBM model and calibrated thresholds."""
        if cls._model is None:
            if not os.path.exists(cls.MODEL_PATH) or not os.path.exists(cls.THRESHOLD_PATH):
                logger.error("Model files missing in /model directory.")
                raise FileNotFoundError(
                    "Required model files (np_classifier_v7_2.pkl, thresholds_v7_2.npy) not found."
                )
            
            try:
                cls._model      = joblib.load(cls.MODEL_PATH)
                cls._thresholds = np.load(cls.THRESHOLD_PATH)
                logger.info(f"✅ Model v7.2 Loaded. Thresholds: {cls._thresholds.round(3)}")
            except Exception as e:
                logger.error(f"Failed to load model: {e}")
                raise
        return cls._model, cls._thresholds

    # ── Chemical Input Detection ──────────────────────────────────────────

    _CAS_RE   = re.compile(r'^\d{2,7}-\d{2}-\d$')
    _INCHI_RE = re.compile(r'^[A-Z]{14}-[A-Z]{10}-[A-Z]$')
    _SMILES_CHR = set("CNOSPFBrIlc()[]=@+-.#\\/0123456789%")

    @classmethod
    def detect_input_type(cls, text: str) -> str:
        """Determines if the input is SMILES, CAS, InChIKey, or a common name."""
        t = text.strip()
        if not t: return "empty"
        
        if cls._CAS_RE.fullmatch(t):   return "cas"
        if cls._INCHI_RE.fullmatch(t): return "inchikey"
        
        # Validation via RDKit
        if Chem.MolFromSmiles(t) is not None:
            return "smiles"
            
        # Character density check for partial/broken SMILES
        s_count = sum(1 for c in t if c in cls._SMILES_CHR)
        if s_count / max(len(t), 1) > 0.65:
            return "smiles"
            
        return "text"

    # ── Fingerprint Processing ────────────────────────────────────────────

    @classmethod
    def smiles_to_fingerprint(cls, smiles: str):
        """Converts raw SMILES into 1191-dimensional feature vector."""
        smiles = smiles.strip()
        warning = None
        mol = None

        try:
            if '.' in smiles:
                # Isolate largest fragment (Salt stripping)
                frags = [Chem.MolFromSmiles(f) for f in smiles.split('.')]
                frags = [f for f in frags if f is not None]
                if not frags: return None, None, None
                mol = max(frags, key=lambda x: x[0].GetNumHeavyAtoms())
                warning = "Salt/mixture detected; analyzed largest organic fragment."
            else:
                mol = Chem.MolFromSmiles(smiles)

            if mol is None: return None, None, None

            # Generate Canonical form
            canonical = Chem.MolToSmiles(mol)
            
            # Hybrid Fingerprint Construction
            arr = np.zeros((1, cls.FP_DIM), dtype=np.float32)
            
            # 1. Morgan (ECFP4)
            ecfp = AllChem.GetMorganFingerprintAsBitVect(mol, cls.FP_RADIUS, nBits=cls.FP_NBITS)
            DataStructs.ConvertToNumpyArray(ecfp, arr[0, :cls.FP_NBITS])
            
            # 2. MACCS Keys
            if cls.USE_MACCS:
                maccs = MACCSkeys.GenMACCSKeys(mol)
                m_arr = np.zeros(167, dtype=np.float32)
                DataStructs.ConvertToNumpyArray(maccs, m_arr)
                arr[0, cls.FP_NBITS:] = m_arr
                
            return arr, canonical, warning
        except Exception as e:
            logger.warning(f"Fingerprint generation failed: {e}")
            return None, None, None

    # ── PubChem 2-Step Resolution Pipeline ────────────────────────────────

    @classmethod
    def _pubchem_get(cls, url: str) -> dict | None:
        """Unified HTTP getter with error handling for both Requests and Urllib."""
        headers = {"User-Agent": "PhytoAI/2.0 (Research)", "Accept": "application/json"}
        try:
            if _REQUESTS_AVAILABLE:
                r = _requests.get(url, headers=headers, timeout=cls.PUBCHEM_TIMEOUT)
                if r.status_code == 404: return None
                r.raise_for_status()
                data = r.json()
            else:
                import ssl
                req = urllib.request.Request(url, headers=headers)
                ctx = ssl.create_default_context()
                with urllib.request.urlopen(req, timeout=cls.PUBCHEM_TIMEOUT, context=ctx) as resp:
                    data = _json.loads(resp.read().decode())
            
            return None if "Fault" in data else data
        except Exception:
            return None

    @classmethod
    def _resolve_name_to_cid(cls, name: str) -> int | None:
        """Step 1: Convert name to stable PubChem Compound ID (CID)."""
        clean_name = urllib.parse.quote(name.strip())
        url = f"{cls.PUBCHEM_BASE}/compound/name/{clean_name}/cids/JSON"
        data = cls._pubchem_get(url)
        try:
            return int(data["IdentifierList"]["CID"][0]) if data else None
        except (KeyError, IndexError, TypeError):
            return None

    @classmethod
    def _fetch_properties_by_cid(cls, cid: int) -> dict | None:
        """Step 2: Fetch structural properties with multi-key SMILES fallback."""
        url = f"{cls.PUBCHEM_BASE}/compound/cid/{cid}/property/IsomericSMILES,CanonicalSMILES,IUPACName,Title/JSON"
        data = cls._pubchem_get(url)
        if not data: return None
        
        try:
            props = data["PropertyTable"]["Properties"][0]
            
            # --- Robust SMILES Fallback Logic ---
            # If the bulk fetch returns empty SMILES, target the specific SMILES endpoint.
            if not (props.get("IsomericSMILES") or props.get("CanonicalSMILES")):
                fallback = cls._pubchem_get(f"{cls.PUBCHEM_BASE}/compound/cid/{cid}/property/SMILES/JSON")
                if fallback:
                    fallback_props = fallback["PropertyTable"]["Properties"][0]
                    props["CanonicalSMILES"] = fallback_props.get("SMILES", "")
            return props
        except:
            return None

    @classmethod
    def resolve_name_to_smiles(cls, name: str) -> dict:
        """Orchestrates the resolution of names to chemical structures."""
        cid = cls._resolve_name_to_cid(name)
        if cid is None:
            return {"found": False, "error": "not_found", "suggestions": cls.get_autocomplete_suggestions(name)}

        props = cls._fetch_properties_by_cid(cid)
        if not props:
            return {"found": False, "error": "props_missing"}

        smiles = (props.get("IsomericSMILES") or props.get("CanonicalSMILES") or "").strip()
        
        if not smiles:
             return {
                "found": False, "error": "no_smiles",
                "message": f"PubChem found '{name}' (CID {cid}) but has no SMILES structure. Mixture/Polymer detected."
            }

        # Medicine Detection Check
        is_med = False
        indication = None
        class_data = cls._pubchem_get(f"{cls.PUBCHEM_BASE}/compound/cid/{cid}/classification/JSON")
        if class_data:
            is_med, indication = cls._check_medicine_from_classification(class_data)

        return {
            "found": True,
            "smiles": smiles,
            "cid": cid,
            "canonical_name": props.get("Title", name),
            "iupac_name": props.get("IUPACName", ""),
            "is_medicine": is_med,
            "drug_indication": indication,
            "active_compound": props.get("IUPACName") or props.get("Title") or name
        }

    # ── Medicine Classification Logic ─────────────────────────────────────

    @classmethod
    def _check_medicine_from_classification(cls, data: dict) -> tuple[bool, str | None]:
        """Scans source hierarchies (FDA, WHO, ATC, MeSH) for medical usage."""
        KEYWORDS = {"drug", "pharmaceutical", "therapeutic", "analgesic", "antipyretic", "antiviral", "antibiotic"}
        try:
            hierarchies = data.get("Hierarchies", {}).get("Hierarchy", [])
            for h in hierarchies:
                src = h.get("SourceName", "").lower()
                if any(s in src for s in ["mesh", "atc", "fda", "who", "drugbank"]):
                    # Extended scan depth to 30 nodes for reliability
                    for node in h.get("Node", [])[:30]:
                        val = str(node.get("Information", {}).get("Name", "")).lower()
                        if any(kw in val for kw in KEYWORDS):
                            return True, val.title()
        except: pass
        return False, None

    @classmethod
    def get_autocomplete_suggestions(cls, prefix: str, limit: int = 6) -> list:
        """Fetches compound name suggestions from PubChem."""
        if len(prefix) < 3: return []
        encoded = urllib.parse.quote(prefix.strip())
        url = f"https://pubchem.ncbi.nlm.nih.gov/rest/autocomplete/compound/{encoded}/JSON?limit={limit}"
        data = cls._pubchem_get(url)
        try:
            return data.get("dictionary_terms", {}).get("compound", []) if data else []
        except: return []

    # ── Core Prediction Engine ────────────────────────────────────────────

    @classmethod
    def _margin_predict(cls, probs: np.ndarray, thresholds: np.ndarray) -> tuple[int, bool]:
        """Applies calibration thresholds to multi-class probabilities."""
        margins = probs - thresholds
        if margins.max() >= 0:
            return int(margins.argmax()), True
        return int(probs.argmax()), False

    @classmethod
    def predict(cls, smiles: str) -> dict:
        """Main classification logic for structural inputs."""
        fp, canonical, salt_warning = cls.smiles_to_fingerprint(smiles)
        if fp is None:
            return {"valid": False, "error": "parse_error", "message": "Invalid SMILES structure."}

        try:
            model, thresholds = cls.load_model()
            probs = model.predict_proba(fp)[0]
            
            idx, used_margin = cls._margin_predict(probs, thresholds)
            conf = float(probs[idx])

            return {
                "valid": True,
                "class_idx": idx,
                "class_name": cls.CLASS_NAMES[idx],
                "class_short": cls.CLASS_SHORT[idx],
                "confidence": conf,
                "confidence_percentage": round(conf * 100, 1),
                "probabilities": {cls.CLASS_NAMES[i]: float(probs[i]) for i in range(5)},
                "smiles": canonical or smiles,
                "margin_based": used_margin,
                "salt_warning": salt_warning
            }
        except Exception as e:
            return {"valid": False, "error": "model_error", "message": str(e)}

    # ── Public Pipeline Interface ─────────────────────────────────────────

    @classmethod
    def resolve_and_predict(cls, user_input: str) -> dict:
        """Unified entry point for mobile and web frontends."""
        if not user_input or not user_input.strip():
            return {"status": "error", "message": "No input provided."}

        text = user_input.strip()
        itype = cls.detect_input_type(text)

        # 1. Handle Direct SMILES
        if itype == "smiles":
            res = cls.predict(text)
            res.update({"status": "classified" if res["valid"] else "error", "input_type": "smiles"})
            return res

        # 2. Handle Name/CAS/InChI resolution
        resolved = cls.resolve_name_to_smiles(text)
        if not resolved["found"]:
            return {
                "status": "not_found",
                "input_type": itype,
                "message": resolved.get("message", f"'{text}' not found in database."),
                "suggestions": resolved.get("suggestions", [])
            }

        # 3. Handle Pharmaceutical Intercept
        if resolved["is_medicine"]:
            return {
                "status": "medicine_detected",
                "input_type": "medicine",
                "medicine_name": text,
                "active_compound": resolved["active_compound"],
                "smiles": resolved["smiles"],
                "drug_indication": resolved["drug_indication"],
                "message": f"'{text}' is a pharmaceutical compound (Base: {resolved['active_compound']})."
            }

        # 4. Classified Result for Resolved Names
        res = cls.predict(resolved["smiles"])
        res.update({
            "status": "classified" if res["valid"] else "error",
            "input_type": "compound_name",
            "resolved_name": resolved["canonical_name"],
            "iupac_name": resolved["iupac_name"]
        })
        return res