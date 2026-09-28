import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'result_screen.dart';
import '../services/gemini_service.dart';

// ─── Result model ─────────────────────────────────────────────────────────────

class ScanResult {
  final String rawText;
  final String? productName;
  final String? expiryDate;
  final String? imagePath; // back/expiry-side photo
  final String? frontImagePath; // front-label photo
  final bool usedGeminiFallback;

  final Future<Map<String, dynamic>>? geminiFuture;

  const ScanResult({
    required this.rawText,
    this.productName,
    this.expiryDate,
    this.imagePath,
    this.frontImagePath,
    this.usedGeminiFallback = false,
    this.geminiFuture,
  });
}

// ─── Expiry-date regex helper ─────────────────────────────────────────────────

class ExpiryExtractor {
  static const Map<String, String> _monthNames = {
    'jan': '01',
    'feb': '02',
    'mar': '03',
    'apr': '04',
    'may': '05',
    'jun': '06',
    'jul': '07',
    'aug': '08',
    'sep': '09',
    'oct': '10',
    'nov': '11',
    'dec': '12',
  };

  static final List<RegExp> _labeledPatterns = [
    RegExp(
      r'EXP(?:IRY|IRES)?[:\s.]+(?:[A-Z][:.\s]+)?([A-Z]{3})[.\s/\\-]+(20[2-9]\d)',
      caseSensitive: false,
    ),
    RegExp(
      r'EXP(?:IRY|IRES)?[:\s.]+(?:[A-Z][:.\s]+)?(\d{1,2})[/\\\-.\s]+(20[2-9]\d)',
      caseSensitive: false,
    ),
    RegExp(
      r'(?:USE\s+BEFORE|BEST\s+BEFORE)[:\s.]+(\d{1,2})[/\\\-]+(20[2-9]\d)',
      caseSensitive: false,
    ),
    RegExp(
      r'BB[:\s.]+(\d{1,2})[/\\\-]+(20[2-9]\d)',
      caseSensitive: false,
    ),
    RegExp(
      r'\bE[:\s]+([A-Z]{3})[.\s/\\\-]+(20[2-9]\d)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\bE[:\s]+(\d{1,2})[/\\\-.\s]+(20[2-9]\d)\b',
      caseSensitive: false,
    ),
  ];

  static final List<RegExp> _bareDatePatterns = [
    RegExp(
      r'\b(20[2-9]\d)[/\\\-](0[1-9]|1[0-2])\b',
    ),
    RegExp(
      r'\b(0[1-9]|1[0-2])[/\\\-](20[2-9]\d)\b',
    ),
    RegExp(
      r'\b(0[1-9]|1[0-2])\s(20[2-9]\d)\b',
    ),
    RegExp(
      r'\b(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[/\s\\\-.]+(20[2-9]\d)\b',
      caseSensitive: false,
    ),
  ];

  static String? extract(String text) {
    final cleanedLines = text
        .split('\n')
        .where((line) {
          final lower = line.toLowerCase().trim();

          if (lower.contains('mfg') ||
              lower.contains('mfd') ||
              lower.contains('manufactured') ||
              lower.contains('manufacture date') ||
              lower.contains('prod.date') ||
              lower.contains('production date')) {
            return false;
          }

          if (RegExp(
            r'^M[:\s]+[A-Za-z]{3}[.\s/\\\-]+20\d{2}',
            caseSensitive: false,
          ).hasMatch(lower)) {
            return false;
          }

          return true;
        })
        .join('\n');

    for (final re in _labeledPatterns) {
      final match = re.firstMatch(cleanedLines);
      if (match == null) continue;

      final group1 = match.group(1)!.toLowerCase().trim();

      if (_monthNames.containsKey(group1)) {
        final month = _monthNames[group1]!;
        final year = match.group(2)!.trim();
        return '$year-$month';
      }

      final rawMonth = group1.replaceAll(' ', '').padLeft(2, '0');
      final rawYear = match.group(2)!.replaceAll(' ', '');
      final parsedMonth = int.tryParse(rawMonth);

      if (parsedMonth != null && parsedMonth >= 1 && parsedMonth <= 12) {
        return '$rawYear-$rawMonth';
      }
    }

    for (final re in _bareDatePatterns) {
      final match = re.firstMatch(cleanedLines);
      if (match == null) continue;

      if (re.pattern.startsWith(r'\b(20')) {
        final year = match.group(1)!.trim();
        final month = match.group(2)!.replaceAll(' ', '').padLeft(2, '0');
        return '$year-$month';
      }

      final group1 = match.group(1)!.toLowerCase().trim();

      if (_monthNames.containsKey(group1)) {
        final month = _monthNames[group1]!;
        final year = match.group(2)!.trim();
        return '$year-$month';
      }

      final rawMonth = group1.replaceAll(' ', '').padLeft(2, '0');
      final rawYear = match.group(2)!.replaceAll(' ', '');
      final parsedMonth = int.tryParse(rawMonth);

      if (parsedMonth == null || parsedMonth < 1 || parsedMonth > 12) {
        continue;
      }

      return '$rawYear-$rawMonth';
    }

    return null;
  }
}

// ─── ScanScreen ───────────────────────────────────────────────────────────────

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late TextRecognizer _textRecognizer;

  bool _isProcessing = false;
  bool _isCameraInitialized = false;
  bool _hasNavigated = false;
  bool _isNavigating = false;

  int _scanStage = 1;
  // Gate for Stage 2 — brief pause after flipping so the camera can
  // refocus before OCR starts trying to trigger a capture.
  bool _stage2Ready = false;

  String _stage1Text = '';
  String? _frontImagePath;
  bool _isTorchOn = false;

  // Guards the manual "Tap to Capture" button specifically — kept separate
  // from _isProcessing (which the background OCR loop toggles constantly)
  // so a tap isn't silently swallowed just because a frame happens to be
  // mid-processing at that instant.
  bool _isCapturing = false;

  // Latest OCR read of the expiry side, updated on every processed frame —
  // even ones too short to trigger auto-capture. Lets the manual "Tap to
  // Capture" button use whatever text has been read so far, rather than
  // requiring a full 30-char clean read before the user can act.
  String _stage2LatestText = '';

  String _statusMessage = 'Point camera at the FRONT of the medicine';
  int _frameCount = 0;

  bool _isFirstScan = true;
  bool _showInstructions = false;

  // Matches the old, snappier-feeling version: fewer frames processed
  // per second, but each one that clears the length bar captures
  // immediately — no multi-frame stability wait. Gemini (not this raw
  // OCR text) is the actual source of truth for the saved fields, so
  // a slightly rougher trigger condition is an acceptable trade for
  // much faster capture.
  static const int _frameSkip = 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _checkFirstTimeUser();
  }

  // ── First-time scan instructions ───────────────────────────────────────────

  Future<void> _checkFirstTimeUser() async {
    final prefs = await SharedPreferences.getInstance();
    final hasScannedBefore = prefs.getBool('has_scanned_before') ?? false;

    if (!mounted) return;

    setState(() {
      _isFirstScan = !hasScannedBefore;
      _showInstructions = !hasScannedBefore;
    });

    await _initCamera();
  }

  Future<void> _markAsScanned() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_scanned_before', true);
  }

  void _startScanning() {
    if (!mounted) return;
    setState(() {
      _showInstructions = false;
    });
  }

  // ── Torch ──────────────────────────────────────────────────────────────────

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null) return;

    try {
      final newMode = _isTorchOn ? FlashMode.off : FlashMode.torch;
      await controller.setFlashMode(newMode);
      if (!mounted) return;
      setState(() => _isTorchOn = !_isTorchOn);
    } catch (e) {
      debugPrint('Torch toggle error: $e');
    }
  }

  // ── App lifecycle ──────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      controller.dispose();
      _cameraController = null;
      _isCameraInitialized = false;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ── Camera initialization ──────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _updateStatus('No camera found on this device');
        return;
      }

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      _cameraController = controller;
      await controller.initialize();

      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint('Autofocus setup error: $e');
      }

      if (!mounted) return;
      setState(() => _isCameraInitialized = true);

      _startStream();
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      _updateStatus('Unable to start camera');
    }
  }

  // ── Camera OCR stream ──────────────────────────────────────────────────────

  void _startStream() {
    final controller = _cameraController;
    if (controller == null) return;

    try {
      controller.startImageStream((CameraImage image) async {
        _frameCount++;
        if (_frameCount % _frameSkip != 0) return;
        if (_isProcessing || _hasNavigated || _isNavigating) return;
        if (_scanStage == 2 && !_stage2Ready) return;
        if (_showInstructions) return;

        _isProcessing = true;
        final stageAtCapture = _scanStage;

        try {
          final inputImage = _buildInputImage(image);
          if (inputImage == null) return;

          final recognized = await _textRecognizer.processImage(inputImage);
          final rawText = recognized.text.trim();

          // Keep the manual-capture path fed with the latest read, even if
          // it's too short/weak to clear the auto-capture bar below.
          if (stageAtCapture == 2) {
            _stage2LatestText = rawText;
          }

          if (rawText.length < 30) {
            return;
          }

          if (_scanStage != stageAtCapture) {
            return;
          }

          // ── Stage 1 — single read is enough, no stability wait ─────────────

          if (stageAtCapture == 1) {
            _stage1Text = rawText;
            _updateStatus('Front scanned ✓ — tap "Next Side" to flip');
            return;
          }

          // ── Stage 2 — single read triggers capture immediately ─────────────

          final expiryFromStage2 = ExpiryExtractor.extract(rawText);
          final expiryFromStage1 = ExpiryExtractor.extract(_stage1Text);
          final finalExpiry = expiryFromStage2 ?? expiryFromStage1;

          final mergedText = 'FRONT SIDE:\n'
              '$_stage1Text\n\n'
              'BACK/EXPIRY SIDE:\n'
              '$rawText';

          debugPrint('FRONT OCR:\n$_stage1Text');
          debugPrint('BACK OCR:\n$rawText');
          debugPrint('Extracted expiry: $finalExpiry');

          await _markAsScanned();

          await _captureAndNavigate(
            rawText: mergedText,
            backOcrText: rawText, // the Stage 2 frame's own OCR text
            productName: _guessProductName(_stage1Text),
            expiryDate: finalExpiry,
          );
        } catch (e) {
          debugPrint('OCR error: $e');
        } finally {
          _isProcessing = false;
        }
      });
    } catch (e) {
      debugPrint('Image stream error: $e');
    }
  }

  // ── Manual capture (expiry side only) ──────────────────────────────────────
  //
  // The expiry side is often slow to autofocus/stabilize (dot-matrix,
  // curved surfaces, low contrast), which can leave the auto-trigger above
  // waiting a long time. This lets the user force a capture on demand
  // using whatever OCR text has been read so far — Gemini reads the actual
  // photo directly regardless, so a weak/empty OCR text here just means
  // the regex-based `expiryDate` field may come back null and Gemini's
  // result screen fields take over instead.

  Future<void> _manualCaptureExpiry() async {
    if (_hasNavigated || _isNavigating || _scanStage != 2 || _isCapturing) {
      return;
    }
    setState(() => _isCapturing = true);

    try {
      final expiryFromStage2 = ExpiryExtractor.extract(_stage2LatestText);
      final expiryFromStage1 = ExpiryExtractor.extract(_stage1Text);
      final finalExpiry = expiryFromStage2 ?? expiryFromStage1;

      final mergedText = 'FRONT SIDE:\n'
          '$_stage1Text\n\n'
          'BACK/EXPIRY SIDE:\n'
          '$_stage2LatestText';

      debugPrint('Manual capture — FRONT OCR:\n$_stage1Text');
      debugPrint('Manual capture — BACK OCR:\n$_stage2LatestText');
      debugPrint('Manual capture — extracted expiry: $finalExpiry');

      await _markAsScanned();

      await _captureAndNavigate(
        rawText: mergedText,
        backOcrText: _stage2LatestText,
        productName: _guessProductName(_stage1Text),
        expiryDate: finalExpiry,
      );
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // ── Capture final image and navigate ───────────────────────────────────────

  /// Stops the frame stream (if running) and waits briefly before taking the
  /// still photo. Calling takePicture() immediately after stopImageStream()
  /// can grab a frame mid-focus-adjustment or mid-motion, which is the main
  /// source of blurry captures — this settle delay gives the sensor a beat
  /// to lock focus/exposure first.
  Future<XFile> _takeSettledPicture(CameraController controller) async {
    if (controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
    await Future.delayed(const Duration(milliseconds: 400));
    return controller.takePicture();
  }

  Future<void> _captureAndNavigate({
    required String rawText,
    required String backOcrText,
    String? productName,
    String? expiryDate,
  }) async {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    setState(() => _isNavigating = true);

    String? imagePath;

    try {
      final controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) {
        throw Exception('Camera is not initialized');
      }

      final picture = await _takeSettledPicture(controller);
      imagePath = picture.path;

      debugPrint('Final back image captured: $imagePath');
    } catch (e) {
      debugPrint('Capture error: $e');
    }

    if (!mounted) return;

    if (imagePath == null) {
      setState(() {
        _isNavigating = false;
        _hasNavigated = false;
      });
      _updateStatus('Could not capture the expiry-side photo. Please try again.');
      return;
    }

    // Runs the front-label and expiry-label agents CONCURRENTLY — total
    // latency is bounded by whichever finishes slower, not the sum.
    final geminiFuture = GeminiService.analyzeMedicine(
      rawText: rawText,
      frontImagePath: _frontImagePath,
      backImagePath: imagePath,
      frontOcrText: _stage1Text,
      backOcrText: backOcrText,
    );

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          result: ScanResult(
            rawText: rawText,
            productName: productName,
            expiryDate: expiryDate,
            imagePath: imagePath,
            frontImagePath: _frontImagePath,
            geminiFuture: geminiFuture,
          ),
        ),
      ),
    );
  }

  // ── Build ML Kit InputImage ────────────────────────────────────────────────

  InputImage? _buildInputImage(CameraImage image) {
    final controller = _cameraController;
    if (controller == null) return null;

    final camera = controller.description;
    InputImageRotation rotation;

    if (Platform.isIOS) {
      rotation = InputImageRotation.rotation0deg;
    } else {
      switch (camera.sensorOrientation) {
        case 90:
          rotation = InputImageRotation.rotation90deg;
          break;
        case 180:
          rotation = InputImageRotation.rotation180deg;
          break;
        case 270:
          rotation = InputImageRotation.rotation270deg;
          break;
        default:
          rotation = InputImageRotation.rotation0deg;
      }
    }

    final format = Platform.isAndroid
        ? InputImageFormat.nv21
        : InputImageFormat.bgra8888;

    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // ── Local product-name guess ───────────────────────────────────────────────

  String? _guessProductName(String text) {
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final productLines = <String>[];

    for (final line in lines) {
      final lower = line.toLowerCase();

      if (lower.contains('ingredient')) break;
      if (lower.contains('direction')) break;
      if (lower.contains('warning')) break;
      if (lower.contains('caution')) break;
      if (lower.contains('barcode')) break;
      if (lower.contains('how to use')) break;

      if (lower.contains('exp')) continue;
      if (lower.contains('mfg')) continue;
      if (lower.contains('batch')) continue;
      if (lower.contains('lot')) continue;
      if (lower.contains('www.')) continue;
      if (lower.contains('http')) continue;
      if (lower.contains('ml)') || lower.contains('mg)')) continue;
      if (lower.contains('niacinamide')) continue;
      if (lower.contains('glutathione')) continue;
      if (lower.contains('alpha')) continue;

      if (line.length <= 3) continue;

      final alphaCount = line.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
      if (alphaCount < line.length * 0.5) continue;

      productLines.add(line);
      if (productLines.length >= 3) break;
    }

    return productLines.isEmpty ? null : productLines.join(' ');
  }

  // ── Status ─────────────────────────────────────────────────────────────────

  void _updateStatus(String message) {
    if (mounted) setState(() => _statusMessage = message);
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isTorchOn) {
      try {
        _cameraController?.setFlashMode(FlashMode.off);
      } catch (_) {}
    }
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _cameraController == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Starting camera…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!_showInstructions)
            GestureDetector(
              onTapUp: (details) async {
                final controller = _cameraController;
                if (controller == null || !controller.value.isInitialized) return;

                final box = context.findRenderObject() as RenderBox?;
                if (box == null) return;

                final localPosition = box.globalToLocal(details.globalPosition);
                final relative = Offset(
                  (localPosition.dx / box.size.width).clamp(0.0, 1.0),
                  (localPosition.dy / box.size.height).clamp(0.0, 1.0),
                );

                try {
                  await controller.setFocusPoint(relative);
                  await controller.setExposurePoint(relative);
                } catch (e) {
                  debugPrint('Tap-to-focus error: $e');
                }
              },
              child: CameraPreview(_cameraController!),
            ),

          if (_showInstructions)
            Container(
              color: Colors.black.withValues(alpha: 0.85),
              child: Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.document_scanner_rounded,
                        size: 60,
                        color: Color(0xFF4D7CFE),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'How to Scan',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '1. Position the product inside the frame\n'
                        '2. Hold steady until the camera focuses\n'
                        '3. The product details will be recognized automatically',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, height: 1.6),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _startScanning,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4D7CFE),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Got it, Start Scanning',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (!_showInstructions) ...[
            const _ScanOverlay(),

            SafeArea(
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        const Text(
                          'Scan Products',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _scanStage == 1
                              ? 'STEP 1 OF 2  •  SCAN FRONT SIDE'
                              : 'STEP 2 OF 2  •  SCAN BACK / EXPIRY SIDE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: 8,
                    child: GestureDetector(
                      onTap: _toggleTorch,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isTorchOn ? Colors.amber.shade600 : Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isTorchOn ? Icons.flash_on : Icons.flash_off,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width * 0.9,
                    height: MediaQuery.of(context).size.height * 0.55,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _scanStage == 2 ? Colors.greenAccent : Colors.white,
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),

            if (_isNavigating)
              Container(
                color: Colors.black87,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 16),
                      Text(
                        'Processing scan…',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Next Side button (Stage 1 only) ───────────────────────────────

            if (!_isNavigating && _scanStage == 1 && _stage1Text.isNotEmpty)
              Positioned(
                bottom: 110,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () async {
                      try {
                        final controller = _cameraController;
                        if (controller != null) {
                          final photo = await _takeSettledPicture(controller);
                          _frontImagePath = photo.path;
                        }
                      } catch (e) {
                        debugPrint('Front capture error: $e');
                      }

                      if (!mounted) return;
                      setState(() {
                        _scanStage = 2;
                        _stage2Ready = false;
                        _statusMessage =
                            'Flip the product — point at BACK / expiry date side';
                      });

                      try {
                        final controller = _cameraController;
                        if (controller != null) {
                          await controller.setFocusMode(FocusMode.auto);
                          await controller.setFocusPoint(const Offset(0.5, 0.5));
                          await controller.setExposurePoint(const Offset(0.5, 0.5));
                        }
                      } catch (e) {
                        debugPrint('Focus reset error: $e');
                      }

                      _startStream();

                      // Brief pause so the camera can refocus on the new
                      // side before OCR is allowed to trigger a capture.
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _stage2Ready = true);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.shade600,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flip, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Next Side',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Tap to Capture button (Stage 2 only) ──────────────────────────
            //
            // Lets the user force-capture the expiry side instead of waiting
            // on autofocus/stability, which can drag on dot-matrix/curved/
            // low-contrast codes. Only shown once the post-flip refocus
            // delay (_stage2Ready) has cleared, same gate the auto-trigger
            // uses, so it doesn't appear mid-flip.

            if (!_isNavigating && _scanStage == 2 && _stage2Ready)
              Positioned(
                bottom: 110,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _isCapturing ? null : _manualCaptureExpiry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: _isCapturing
                            ? Colors.blue.shade300
                            : Colors.blue.shade600,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isCapturing)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          else
                            const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _isCapturing ? 'Capturing…' : 'Tap to Capture',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // ── Cancel button ─────────────────────────────────────────────────

            if (!_isNavigating)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.red.shade600,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── Overlay ──────────────────────────────────────────────────────────────────

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _OverlayPainter());
  }
}

class _OverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = size.width * 0.9;
    final frameHeight = size.height * 0.55;

    final frameRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: frameWidth,
        height: frameHeight,
      ),
      const Radius.circular(14),
    );

    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      frameRect,
      Paint()
        ..color = Colors.transparent
        ..blendMode = BlendMode.clear,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}