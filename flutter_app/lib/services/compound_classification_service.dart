import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../ml/compound_fingerprint_generator.dart';
import '../ml/compound_onnx_service.dart';
import 'cache_service.dart';
import 'error_service.dart';
import 'network_service.dart';

class CompoundClassificationService {
  CompoundClassificationService({
    required CacheService cacheService,
    required NetworkService networkService,
  }) : _cacheService = cacheService,
       _networkService = networkService;

  final CacheService _cacheService;
  final NetworkService _networkService;

  static const String _pubchemBase =
      'https://pubchem.ncbi.nlm.nih.gov/rest/pug';
  static const String _thresholdsAsset = 'assets/models/thresholds_v7_2.json';

  static final RegExp _casRegExp = RegExp(r'^\d{2,7}-\d{2}-\d$');
  static final Set<String> _smilesChars = {
    'C',
    'N',
    'O',
    'S',
    'P',
    'F',
    'B',
    'r',
    'I',
    'l',
    'c',
    'n',
    'o',
    's',
    'p',
    'f',
    'b',
    'h',
    '(',
    ')',
    '[',
    ']',
    '=',
    '@',
    '+',
    '-',
    '.',
    '#',
    '\\',
    '/',
    '%',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  };

  static const List<String> _classNames = [
    'Animal-derived',
    'Bacteria-derived',
    'Chromista-derived',
    'Fungi-derived',
    'Plant-derived',
  ];

  List<double>? _cachedThresholds;

  Future<void> _ensureModelLoaded() async {
    debugPrint(
      '[Compound] _ensureModelLoaded: isInitialized=${CompoundOnnxService.instance.isInitialized}',
    );
    if (!CompoundOnnxService.instance.isInitialized) {
      debugPrint('[Compound] Loading compound ONNX model...');
      await CompoundOnnxService.instance.init();
      debugPrint('[Compound] ✅ Compound ONNX model loaded!');
    }
  }

  Future<List<double>> _loadThresholds() async {
    if (_cachedThresholds != null) {
      debugPrint(
        '[Compound] Using cached thresholds (${_cachedThresholds!.length})',
      );
      return _cachedThresholds!;
    }
    debugPrint('[Compound] Loading thresholds from asset...');
    final jsonString = await rootBundle.loadString(_thresholdsAsset);
    final jsonMap = json.decode(jsonString) as Map<String, dynamic>;
    final thresholdsRaw = jsonMap['thresholds'];
    if (thresholdsRaw is! List) {
      throw AppError(
        code: 'thresholds_parse_error',
        message: 'Threshold metadata is invalid.',
        retryable: false,
        fallbackAllowed: false,
      );
    }
    _cachedThresholds = thresholdsRaw
        .map((item) => (item as num).toDouble())
        .toList();
    debugPrint(
      '[Compound] Thresholds loaded: ${_cachedThresholds!.length} values',
    );
    return _cachedThresholds!;
  }

  String detectInputType(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'empty';
    if (_casRegExp.hasMatch(trimmed)) return 'cas';
    if (_looksLikeSmiles(trimmed)) return 'smiles';
    return 'text';
  }

  bool _looksLikeSmiles(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return false;
    if (normalized.contains(RegExp(r'\s'))) return false;
    if (_casRegExp.hasMatch(normalized)) return false;
    if (!_hasOnlySmilesChars(normalized)) return false;

    // Clear SMILES indicators: ring closure digits, bond descriptors, brackets,
    // chirality, explicit charges, or aromatic element syntax.
    if (RegExp(r'[\[\]@+\-#=\\/%.0-9]').hasMatch(normalized)) {
      return true;
    }

    // Short valid strings are likely SMILES.
    if (normalized.length <= 4) {
      return true;
    }

    final smilesCount = normalized.runes
        .where((r) => _smilesChars.contains(String.fromCharCode(r)))
        .length;
    return smilesCount / max(normalized.length, 1) > 0.8;
  }

  bool _hasOnlySmilesChars(String text) {
    return text.runes
        .every((r) => _smilesChars.contains(String.fromCharCode(r)));
  }

  String _normalizeCacheKey(String text) {
    final normalized = text.trim().toLowerCase();
    final safe = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'pubchem_smiles:$safe';
  }

  Future<Map<String, dynamic>> classifyCompound(
    String input, {
    bool confirmMedicine = false,
  }) async {
    debugPrint('[Compound] ── classifyCompound called ──');
    debugPrint('[Compound] input: "$input"');

    final trimmed = input.trim();
    debugPrint('[SMILES] normalized user input: "$trimmed"');
    if (trimmed.isEmpty) {
      return {
        'status': 'error',
        'message': 'Please enter a compound name, CAS number, or SMILES.',
      };
    }

    final inputType = detectInputType(trimmed);
    debugPrint('[SMILES] input classification: $inputType');
    var effectiveInputType = inputType;

    if (inputType == 'smiles') {
      debugPrint('[SMILES] treating input as SMILES, validating via RDKit');
      try {
        final features = await CompoundFingerprintGenerator.generate(trimmed);
        debugPrint(
          '[RDKit] SMILES validation success for "$trimmed", fingerprint length: ${features.length}',
        );
        return await _classifySmiles(
          trimmed,
          inputType: 'smiles',
          precomputedFeatures: features,
        );
      } catch (error, stack) {
        debugPrint('[RDKit] SMILES validation failed for "$trimmed": $error');
        debugPrint('[RDKit] validation stack: $stack');
        debugPrint(
          '[SMILES] Falling back from SMILES validation to PubChem name lookup for "$trimmed"',
        );
        effectiveInputType = 'text';
      }
    }

    final cacheKey = _normalizeCacheKey(trimmed);
    if (cacheKey == 'pubchem_smiles:cholesterol' ||
        cacheKey == 'pubchem_smiles:quercetin') {
      await _cacheService.remove(cacheKey);
      debugPrint('[Compound] invalidated stale cache for "$trimmed"');
    }
    final cached = _cacheService.get(cacheKey);
    if (cached is Map<String, dynamic>) {
      debugPrint('[Compound] Cache hit for "$trimmed" ($cacheKey)');
      return await _classifyResolved(
        cached,
        confirmMedicine: confirmMedicine,
        inputType: effectiveInputType,
      );
    }
    debugPrint('[Compound] Cache miss for "$trimmed" ($cacheKey)');

    final isConnected = await _networkService.isConnected();
    debugPrint('[Compound] Network connected: $isConnected');

    if (!isConnected) {
      throw AppError(
        code: 'offline_resolution',
        message:
            'No internet connection to resolve compound names. '
            'Please enter a canonical SMILES string or try again later.',
        retryable: true,
        fallbackAllowed: false,
      );
    }

    debugPrint('[Compound] Resolving "$trimmed" via PubChem...');
    final resolved = await _resolveNameToSmiles(trimmed);
    debugPrint('[Compound] PubChem result status: ${resolved['status']}');
    debugPrint('[Compound] PubChem SMILES: ${resolved['smiles']}');

    if (resolved['status'] == 'not_found' && _hasOnlySmilesChars(trimmed)) {
      debugPrint(
        '[SMILES] PubChem lookup failed for "$trimmed"; attempting strict SMILES validation fallback',
      );
      try {
        final features = await CompoundFingerprintGenerator.generate(trimmed);
        debugPrint(
          '[RDKit] Fallback SMILES validation success for "$trimmed", fingerprint length: ${features.length}',
        );
        return await _classifySmiles(
          trimmed,
          inputType: 'smiles',
          precomputedFeatures: features,
        );
      } catch (error, stack) {
        debugPrint(
          '[RDKit] Fallback SMILES validation failed for "$trimmed": $error',
        );
        debugPrint('[RDKit] fallback stack: $stack');
      }
    }

    final bool negativeResult = resolved['status'] == 'not_found';
    await _cacheService.set(
      cacheKey,
      resolved,
      ttl: negativeResult
          ? const Duration(minutes: 5)
          : const Duration(days: 30),
    );
    debugPrint(
      '[Compound] Cache store for "$trimmed" ($cacheKey): ' 
      '${negativeResult ? 'negative short TTL' : 'positive long TTL'}',
    );
    return await _classifyResolved(
      resolved,
      confirmMedicine: confirmMedicine,
      inputType: effectiveInputType,
    );
  }

  Future<Map<String, dynamic>> _classifyResolved(
    Map<String, dynamic> resolved, {
    required bool confirmMedicine,
    required String inputType,
  }) async {
    debugPrint('[Compound] _classifyResolved: status=${resolved['status']}');

    if (resolved['status'] == 'medicine_detected' && !confirmMedicine) {
      return {
        'status': 'medicine_detected',
        'input_type': inputType,
        'medicine_name': resolved['query'] ?? '',
        'active_compound': resolved['active_compound'],
        'canonical_name': resolved['canonical_name'],
        'smiles': resolved['smiles'] ?? '',
        'drug_indication': resolved['drug_indication'],
        'message': resolved['message'],
      };
    }

    final smiles = resolved['smiles'] as String?;
    debugPrint('[Compound] SMILES to classify: "$smiles"');

    if (smiles == null || smiles.isEmpty) {
      debugPrint('[Compound] ❌ No SMILES — returning not_found');
      return {
        'status': 'not_found',
        'input_type': inputType,
        'message':
            resolved['message'] ?? 'Could not resolve compound to SMILES.',
        'suggestions': resolved['suggestions'] ?? [],
      };
    }

    return await _classifySmiles(
      smiles,
      inputType: 'canonical_smiles',
      resolvedName: resolved['canonical_name'] as String?,
      iupacName: resolved['iupac_name'] as String?,
      saltWarning: resolved['salt_warning'] as String?,
    );
  }

  Future<Map<String, dynamic>> _classifySmiles(
    String smiles, {
    required String inputType,
    Float32List? precomputedFeatures,
    String? resolvedName,
    String? iupacName,
    String? saltWarning,
  }) async {
    debugPrint('[Compound] ── _classifySmiles ──');
    debugPrint('[Compound] SMILES: "$smiles"');

    try {
      debugPrint(
        '[Compound] Step 1: Generating fingerprint via RDKit WebView...',
      );
      final features = precomputedFeatures ??
          await CompoundFingerprintGenerator.generate(smiles);
      debugPrint(
        '[Compound] ✅ Fingerprint generated, length: ${features.length}',
      );

      debugPrint('[Compound] Step 2: Ensuring ONNX model loaded...');
      await _ensureModelLoaded();
      debugPrint('[Compound] ✅ ONNX model ready');

      debugPrint('[Compound] Step 3: Running ONNX inference...');
      final probs = await CompoundOnnxService.instance.runInference(features);
      debugPrint('[Compound] ✅ Inference done: $probs');

      debugPrint('[Compound] Step 4: Loading thresholds...');
      final thresholds = await _loadThresholds();
      debugPrint('[Compound] ✅ Thresholds: $thresholds');

      if (thresholds.length != probs.length) {
        throw AppError(
          code: 'threshold_mismatch',
          message:
              'Model and threshold dimensions do not match. '
              'probs=${probs.length}, thresholds=${thresholds.length}',
          retryable: false,
          fallbackAllowed: false,
        );
      }

      final margins = List<double>.generate(
        probs.length,
        (i) => probs[i] - thresholds[i],
      );
      final maxMargin = margins.reduce(max);
      final int chosenIndex = maxMargin >= 0
          ? margins.indexOf(maxMargin)
          : probs.indexWhere((p) => p == probs.reduce(max));
      final chosenClass = _classNames[chosenIndex];
      final confidence = probs[chosenIndex];

      debugPrint(
        '[Compound] ✅ Result: $chosenClass (${(confidence * 100).toStringAsFixed(1)}%)',
      );

      final probabilities = Map<String, dynamic>.fromIterables(
        _classNames,
        probs,
      );
      final marginMap = Map<String, dynamic>.fromIterables(
        _classNames,
        margins,
      );

      return {
        'status': 'classified',
        'input_type': inputType,
        'resolved_name': resolvedName,
        'iupac_name': iupacName,
        'smiles': smiles,
        'class_name': chosenClass,
        'class_short': chosenClass.split('-').first,
        'confidence': confidence,
        'confidence_percentage': double.parse(
          (confidence * 100).toStringAsFixed(1),
        ),
        'probabilities': probabilities,
        'margins': marginMap,
        'thresholds': thresholds,
        'margin_based': maxMargin >= 0,
        'selected_by': maxMargin >= 0 ? 'margin' : 'probability',
        'salt_warning': saltWarning,
        'message':
            'Predicted $chosenClass with ${(confidence * 100).toStringAsFixed(1)}% confidence.',
      };
    } catch (error, stack) {
      debugPrint('[Compound] ❌ ERROR in _classifySmiles: $error');
      debugPrint('[Compound] Stack: $stack');
      final appError = ErrorService.parse(error);
      return {'status': 'error', 'message': appError.message};
    }
  }

  Future<Map<String, dynamic>> _resolveNameToSmiles(String query) async {
    debugPrint('[PubChem] _resolveNameToSmiles called with raw query: "$query"');
    final normalized = query.trim();
    debugPrint('[PubChem] normalized query: "$normalized"');
    final cid = await _resolveNameToCid(normalized);
    debugPrint('[PubChem] extracted CID: $cid');

    if (cid == null) {
      debugPrint('[PubChem] not_found reason: CID lookup failed or returned no CID for "$normalized"');
      return {
        'status': 'not_found',
        'message': "'$query' not found on PubChem.",
        'suggestions': [],
      };
    }

    final props = await _fetchPropertiesByCid(cid);
    debugPrint('[PubChem] resolved PubChem properties: $props');

    if (props == null) {
      debugPrint('[PubChem] not_found reason: property fetch returned no usable SMILES for CID $cid');
      return {
        'status': 'not_found',
        'message': "No structure properties found for '$query'.",
        'suggestions': [],
      };
    }

    final smiles =
        (props['IsomericSMILES'] ??
                props['CanonicalSMILES'] ??
                props['SMILES'] ??
                '')
            .toString()
            .trim();
    final canonicalName = (props['Title'] ?? query) as String;
    final iupacName = (props['IUPACName'] ?? '') as String;

    debugPrint('[PubChem] Final resolved SMILES before RDKit: "$smiles"');
    debugPrint('[PubChem] Canonical name: "$canonicalName"');

    final bool isMedicine =
        _containsFormulationLanguage(normalized) ||
        _looksLikeBrandName(normalized);
    if (isMedicine) {
      return {
        'status': 'medicine_detected',
        'query': query,
        'active_compound': iupacName.isNotEmpty ? iupacName : canonicalName,
        'canonical_name': canonicalName,
        'iupac_name': iupacName,
        'smiles': smiles,
        'drug_indication': 'Looks like a formulated pharmaceutical product.',
        'message': "'$query' appears to be a pharmaceutical product.",
      };
    }

    if (smiles.isEmpty) {
      return {
        'status': 'not_found',
        'message': "PubChem found '$query' but no SMILES was available.",
      };
    }

    return {
      'status': 'resolved',
      'query': query,
      'smiles': smiles,
      'canonical_name': canonicalName,
      'iupac_name': iupacName,
      'salt_warning': null,
    };
  }

  bool _containsFormulationLanguage(String text) {
    const formulationPatterns = [
      r'\b(tablet|capsule|injection|syrup|suspension|solution|cream|ointment|patch|inhaler|suppository|drops|lozenge|gel|spray|sachet|vial|ampoule)\b',
      r'\b(extended[- ]release|immediate[- ]release|sustained[- ]release|delayed[- ]release|modified[- ]release|controlled[- ]release)\b',
      r'\b(film[- ]coated|enteric[- ]coated|effervescent|chewable|dispersible)\b',
      r'\d+\s*mg\b',
      r'\d+\s*mcg\b',
      r'\d+\s*ml\b',
      r'\b\d+\s*%\s*(w/v|v/v|w/w)\b',
    ];
    return formulationPatterns.any(
      (pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text),
    );
  }

  bool _looksLikeBrandName(String text) {
    final lower = text.toLowerCase();
    const knownBrands = [
      'tylenol',
      'advil',
      'motrin',
      'aleve',
      'excedrin',
      'nurofen',
      'panadol',
      'disprin',
      'augmentin',
      'amoxil',
      'zithromax',
      'cipro',
      'flagyl',
      'keflex',
      'bactrim',
      'septra',
      'lipitor',
      'crestor',
      'zocor',
      'norvasc',
      'lopressor',
      'tenormin',
      'lasix',
      'aldactone',
      'plavix',
      'coumadin',
      'warfarin',
      'glucophage',
      'metformin',
      'januvia',
      'jardiance',
      'ozempic',
      'prozac',
      'zoloft',
      'lexapro',
      'paxil',
      'effexor',
      'wellbutrin',
      'abilify',
      'seroquel',
      'risperdal',
      'zyprexa',
      'xanax',
      'valium',
      'ativan',
      'klonopin',
      'nexium',
      'prilosec',
      'prevacid',
      'protonix',
      'viagra',
      'cialis',
      'levitra',
      'tamiflu',
      'plaquenil',
      'hydroxychloroquine',
    ];
    return knownBrands.any((brand) => lower.contains(brand));
  }

  Future<int?> _resolveNameToCid(String name) async {
    final encoded = Uri.encodeComponent(name);
    final url = '$_pubchemBase/compound/name/$encoded/cids/JSON';
    debugPrint('[PubChem] CID lookup URL: $url');
    final jsonMap = await _pubchemGet(url);
    debugPrint('[PubChem] CID lookup raw response: $jsonMap');

    if (jsonMap == null) {
      debugPrint('[PubChem] CID lookup returned null or invalid JSON for name "$name"');
      return null;
    }

    debugPrint('[PubChem] CID lookup top-level keys: ${jsonMap.keys.toList()}');
    final identifierList = jsonMap['IdentifierList'];
    debugPrint('[PubChem] IdentifierList payload: $identifierList');

    if (identifierList is! Map) {
      debugPrint('[PubChem] CID lookup missing IdentifierList map');
      return null;
    }

    final cidValue = identifierList['CID'];
    debugPrint('[PubChem] CID array raw value: $cidValue');

    try {
      final cid = cidValue?[0];
      debugPrint('[PubChem] extracted CID value: $cid');
      return cid is int ? cid : null;
    } catch (e, stack) {
      debugPrint('[PubChem] CID extraction error: $e');
      debugPrint('[PubChem] stack: $stack');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchPropertiesByCid(int cid) async {
    final url =
        '$_pubchemBase/compound/cid/$cid/property/IsomericSMILES,CanonicalSMILES,IUPACName,Title/JSON';
    debugPrint('[PubChem] properties lookup URL: $url');
    final data = await _pubchemGet(url);
    if (data == null) {
      debugPrint('[PubChem] properties lookup returned null for CID $cid');
      return null;
    }

    final rawJson = json.encode(data);
    debugPrint('[PubChem] properties lookup raw JSON body: $rawJson');
    debugPrint('[PubChem] properties lookup top-level keys: ${data.keys.toList()}');

    String formatJson(String jsonText) {
      if (jsonText.length <= 1200) return jsonText;
      return '${jsonText.substring(0, 1200)}...';
    }

    try {
      final propsData = data['PropertyTable']?['Properties'];
      if (propsData is List && propsData.isNotEmpty) {
        final props = Map<String, dynamic>.from(propsData[0] as Map);
        debugPrint('[PubChem] primary Property entry keys: ${props.keys.toList()}');
        debugPrint('[PubChem] primary CanonicalSMILES: ${props['CanonicalSMILES']}');
        debugPrint('[PubChem] primary IsomericSMILES: ${props['IsomericSMILES']}');
        debugPrint('[PubChem] primary SMILES fallback: ${props['SMILES']}');
        final smiles =
            (props['IsomericSMILES'] ??
                    props['CanonicalSMILES'] ??
                    props['SMILES'] ??
                    '')
                .toString()
                .trim();
        debugPrint('[PubChem] primary final resolved SMILES before RDKit: "$smiles"');
        if (smiles.isNotEmpty) {
          return props;
        }
        debugPrint(
          '[PubChem] not_found reason: primary property response contained no usable SMILES; raw JSON: ${formatJson(rawJson)}',
        );
      } else {
        debugPrint(
          '[PubChem] not_found reason: PropertyTable.Properties missing or empty; raw JSON: ${formatJson(rawJson)}',
        );
      }
    } catch (e) {
      debugPrint(
        '[Compound] PubChem properties parse error: $e; raw JSON: ${formatJson(rawJson)}',
      );
    }

    // Fallback to the simple SMILES endpoint if the first property query did not yield a usable SMILES.
    final fallbackUrl = '$_pubchemBase/compound/cid/$cid/property/SMILES/JSON';
    debugPrint('[PubChem] fallback SMILES lookup URL: $fallbackUrl');
    final fallbackData = await _pubchemGet(fallbackUrl);
    if (fallbackData != null) {
      final fallbackRawJson = json.encode(fallbackData);
      debugPrint('[PubChem] fallback SMILES raw JSON body: $fallbackRawJson');
      debugPrint('[PubChem] fallback SMILES top-level keys: ${fallbackData.keys.toList()}');
      try {
        final fallbackProps = fallbackData['PropertyTable']?['Properties'];
        if (fallbackProps is List && fallbackProps.isNotEmpty) {
          final props = Map<String, dynamic>.from(fallbackProps[0] as Map);
          debugPrint('[PubChem] fallback Property entry keys: ${props.keys.toList()}');
          final smiles = (props['SMILES'] ?? '').toString().trim();
          debugPrint('[PubChem] fallback SMILES extracted: "$smiles"');
          if (smiles.isNotEmpty) {
            return props;
          }
          debugPrint(
            '[PubChem] not_found reason: fallback SMILES response contained empty SMILES; raw JSON: ${formatJson(fallbackRawJson)}',
          );
        } else {
          debugPrint(
            '[PubChem] not_found reason: fallback response missing PropertyTable.Properties; raw JSON: ${formatJson(fallbackRawJson)}',
          );
        }
      } catch (e) {
        debugPrint(
          '[PubChem] fallback parse error: $e; raw JSON: ${formatJson(fallbackRawJson)}',
        );
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _pubchemGet(String url) async {
    try {
      debugPrint('[PubChem] HTTP GET: $url');
      final response = await http.get(Uri.parse(url));
      debugPrint('[PubChem] HTTP status: ${response.statusCode}');
      debugPrint('[PubChem] HTTP response body: ${response.body}');
      if (response.statusCode == 404) {
        debugPrint('[PubChem] HTTP 404 for URL: $url');
        return null;
      }
      if (response.statusCode != 200) {
        debugPrint('[PubChem] HTTP non-200 response (${response.statusCode}) for URL: $url');
        return null;
      }
      final decoded = json.decode(response.body) as Map<String, dynamic>;
      debugPrint('[PubChem] HTTP JSON top-level keys: ${decoded.keys.toList()}');
      return decoded;
    } catch (e, stack) {
      debugPrint('[PubChem] HTTP error: $e');
      debugPrint('[PubChem] HTTP stack: $stack');
      return null;
    }
  }
}
