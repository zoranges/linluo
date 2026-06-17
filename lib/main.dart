import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

void main() {
  runApp(const FilmWatermarkApp());
}

class FilmWatermarkApp extends StatelessWidget {
  const FilmWatermarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '零落',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6fa875),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xffeef6e9),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0x24dcebdc),
          contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
          border: UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xffafc7ad), width: 0.7),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xffafc7ad), width: 0.7),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xff477d55), width: 1),
          ),
          labelStyle: TextStyle(color: Color(0xff617b64), fontSize: 12),
          prefixIconColor: Color(0xff708677),
        ),
        useMaterial3: true,
      ),
      home: const WatermarkHomePage(),
    );
  }
}

class WatermarkHomePage extends StatefulWidget {
  const WatermarkHomePage({super.key});

  @override
  State<WatermarkHomePage> createState() => _WatermarkHomePageState();
}

class _WatermarkHomePageState extends State<WatermarkHomePage> {
  final _picker = ImagePicker();

  Future<void> _pickImage() async {
    final picked = await _pickImageData(_picker, context);
    if (!mounted || picked == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WatermarkEditorPage(initialImage: picked),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: _studioBackground(),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _WatercolorPagePainter()),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 42,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _HomeHeader(),
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 470),
                            child: const _HomePreviewStack(),
                          ),
                          const SizedBox(height: 18),
                          _PrimaryPickButton(onTap: _pickImage),
                          const SizedBox(height: 12),
                          const _HomeFootnote(),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WatermarkEditorPage extends StatefulWidget {
  const WatermarkEditorPage({super.key, required this.initialImage});

  final PickedImageData initialImage;

  @override
  State<WatermarkEditorPage> createState() => _WatermarkEditorPageState();
}

class _WatermarkEditorPageState extends State<WatermarkEditorPage> {
  static const _galleryChannel = MethodChannel('film_watermark/gallery');

  final _picker = ImagePicker();
  final _dateController = TextEditingController(
    text: _defaultFilmDate(DateTime.now()),
  );
  final _timeController = TextEditingController(
    text: DateFormat('HH:mm').format(DateTime.now()),
  );

  late Uint8List _sourceBytes;
  late String _sourceName;
  late Size _sourceImageSize;
  String? _savedPath;
  bool _includeTime = false;
  final ExportPreset _exportPreset = ExportPreset.png;
  WatermarkTone _watermarkTone = WatermarkTone.amber;
  DateFormatPreset _dateFormatPreset = DateFormatPreset.yySpaced;
  DateTime _watermarkDate = DateTime.now();
  double _watermarkScale = 1.0;
  double _watermarkOpacity = 0.96;
  WatermarkAnchor _watermarkAnchor = WatermarkAnchor.bottomRight;
  bool _isExporting = false;
  bool _chromeVisible = true;
  _EditorTool _activeTool = _EditorTool.size;

  @override
  void initState() {
    super.initState();
    _applyPickedImage(widget.initialImage);
  }

  @override
  void dispose() {
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _pickImageData(_picker, context);
    if (picked == null) {
      return;
    }
    setState(() => _applyPickedImage(picked));
  }

  void _applyPickedImage(PickedImageData image) {
    _sourceBytes = image.bytes;
    _sourceName = image.name;
    _sourceImageSize = image.size;
    if (image.shotTime != null) {
      _watermarkDate = image.shotTime!;
      _dateController.text = _dateFormatPreset.format(image.shotTime!);
      _timeController.text = DateFormat('HH:mm').format(image.shotTime!);
    }
    _savedPath = null;
  }

  Future<void> _exportImage() async {
    if (_isExporting) {
      return;
    }

    setState(() => _isExporting = true);
    try {
      final result = await _renderWatermarkedImage(
        WatermarkJob(
          bytes: _sourceBytes,
          dateText: _dateController.text.trim(),
          timeText: _includeTime ? _timeController.text.trim() : '',
          exportPreset: _exportPreset,
          watermarkTone: _watermarkTone,
          watermarkScale: _watermarkScale,
          watermarkOpacity: _watermarkOpacity,
          watermarkAnchor: _watermarkAnchor,
        ),
      );

      final directory = await _outputDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final ext = _exportPreset.extension;
      final fileName = 'film_watermark_$stamp.$ext';
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(result, flush: true);
      final galleryPath = await _saveToGallery(
        bytes: result,
        fileName: fileName,
        mimeType: _exportPreset.mimeType,
      );

      setState(() => _savedPath = file.path);
      if (mounted) {
        final displayPath = galleryPath ?? file.path;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('\u5df2\u4fdd\u5b58\u5230\u76f8\u518c\uff1a$displayPath')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('\u5bfc\u51fa\u5931\u8d25\uff1a$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<String?> _saveToGallery({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    if (!Platform.isAndroid) {
      return null;
    }
    return _galleryChannel.invokeMethod<String>('saveImage', {
      'bytes': bytes,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }

  Future<Directory> _outputDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    final downloads = await getDownloadsDirectory();
    return downloads ?? await getApplicationDocumentsDirectory();
  }

  Future<void> _shareLastExport() async {
    final savedPath = _savedPath;
    if (savedPath == null) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(savedPath)],
        text: '零落时间水印',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff101611),
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _chromeVisible = !_chromeVisible),
              child: _FullScreenPhotoCanvas(
                imageBytes: _sourceBytes,
                imageSize: _sourceImageSize,
                watermarkScale: _watermarkScale,
                watermarkOpacity: _watermarkOpacity,
                watermarkAnchor: _watermarkAnchor,
                watermarkTone: _watermarkTone,
                showWatermark: true,
                dateText: _dateController.text,
                timeText: _includeTime ? _timeController.text : '',
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: _EditorFloatingBar(
                    isExporting: _isExporting,
                    onBack: () => Navigator.of(context).pop(),
                    onExport: _exportImage,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: _chromeVisible ? Offset.zero : const Offset(0, 1),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 160),
                child: IgnorePointer(
                  ignoring: !_chromeVisible,
                  child: _EditorToolDock(
                    activeTool: _activeTool,
                    sourceName: _sourceName,
                    savedPath: _savedPath,
                    includeTime: _includeTime,
                    watermarkTone: _watermarkTone,
                    dateFormatPreset: _dateFormatPreset,
                    watermarkScale: _watermarkScale,
                    watermarkOpacity: _watermarkOpacity,
                    watermarkAnchor: _watermarkAnchor,
                    isExporting: _isExporting,
                    dateController: _dateController,
                    timeController: _timeController,
                    onToolChanged: (value) => setState(() => _activeTool = value),
                    onChanged: () => setState(() {}),
                    onIncludeTimeChanged: (value) =>
                        setState(() => _includeTime = value),
                    onWatermarkToneChanged: (value) =>
                        setState(() => _watermarkTone = value),
                    onDateFormatChanged: (value) => setState(() {
                      _dateFormatPreset = value;
                      _dateController.text = value.format(_watermarkDate);
                    }),
                    onWatermarkScaleChanged: (value) =>
                        setState(() => _watermarkScale = value),
                    onWatermarkOpacityChanged: (value) =>
                        setState(() => _watermarkOpacity = value),
                    onWatermarkAnchorChanged: (value) =>
                        setState(() => _watermarkAnchor = value),
                    onPickImage: _pickImage,
                    onExport: _exportImage,
                    onShare: _savedPath == null ? null : _shareLastExport,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

BoxDecoration _studioBackground() {
  return BoxDecoration(
    gradient: const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color(0xfffcfbf3),
        Color(0xffedf7ec),
        Color(0xffd8e9df),
        Color(0xffeef7f1),
      ],
      stops: [0, 0.42, 0.78, 1],
    ),
    backgroundBlendMode: BlendMode.srcOver,
  );
}

class _WatercolorPagePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    void wash(Offset center, double radius, Color color) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(rect);
      canvas.drawOval(rect, paint);
    }

    wash(
      Offset(size.width * 0.18, size.height * 0.18),
      size.width * 0.42,
      const Color(0xffdcecf7).withValues(alpha: 0.38),
    );
    wash(
      Offset(size.width * 0.78, size.height * 0.24),
      size.width * 0.34,
      const Color(0xffffefd4).withValues(alpha: 0.30),
    );
    wash(
      Offset(size.width * 0.55, size.height * 0.86),
      size.width * 0.45,
      const Color(0xffbcded0).withValues(alpha: 0.30),
    );
    final threadPaint = Paint()
      ..color = const Color(0xff8cb696).withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    final path = Path()
      ..moveTo(size.width * 0.08, size.height * 0.68)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.58,
        size.width * 0.56,
        size.height * 0.78,
        size.width * 0.92,
        size.height * 0.62,
      );
    canvas.drawPath(path, threadPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _BrandMark(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '\u96f6\u843d',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: const Color(0xff26384a),
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          '\u7528\u65f6\u95f4\u7f1d\u5408\u6240\u6709\u7684\u96f6\u843d',
          style: TextStyle(
            color: Color(0xff395c49),
            fontSize: 18,
            height: 1.28,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          '\u628a\u65e7\u7167\u91cc\u7684\u65e5\u671f\uff0c\u8f7b\u8f7b\u653e\u56de\u90a3\u4e00\u5929\u3002',
          style: TextStyle(
            color: Color(0xff758374),
            fontSize: 13,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: CustomPaint(painter: _BrandMarkPainter()),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final wash = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xffdfeee2),
          const Color(0xffc8dfd1).withValues(alpha: 0.18),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, size.width * 0.48, wash);

    final thread = Paint()
      ..color = const Color(0xff4f7d5d)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.58)
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.28,
        size.width * 0.64,
        size.height * 0.74,
        size.width * 0.80,
        size.height * 0.38,
      );
    canvas.drawPath(path, thread);

    final dotPaint = Paint()..color = const Color(0xffffa51a);
    canvas.drawCircle(Offset(size.width * 0.25, size.height * 0.60), 3.1, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.38), 3.1, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HomePreviewStack extends StatelessWidget {
  const _HomePreviewStack();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 0.74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _LooseThreadsPainter()),
          ),
          Transform.translate(
            offset: const Offset(-46, 34),
            child: Transform.rotate(
              angle: -0.11,
              child: const _MiniPhotoCard(scale: 0.82, opacity: 0.42),
            ),
          ),
          Transform.translate(
            offset: const Offset(46, -28),
            child: Transform.rotate(
              angle: 0.08,
              child: const _MiniPhotoCard(scale: 0.9, opacity: 0.58),
            ),
          ),
          const _MiniPhotoCard(scale: 1, opacity: 1),
          const Positioned(
            right: 18,
            top: 36,
            child: _DigitalDateTag(),
          ),
        ],
      ),
    );
  }
}

class _LooseThreadsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xff85ad91).withValues(alpha: 0.28);
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.30 + i * 0.17);
      final path = Path()
        ..moveTo(size.width * 0.08, y)
        ..cubicTo(
          size.width * 0.32,
          y - 38 + i * 12,
          size.width * 0.58,
          y + 44 - i * 8,
          size.width * 0.90,
          y - 10,
        );
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DigitalDateTag extends StatelessWidget {
  const _DigitalDateTag();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xfff4f2e6).withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '26 6 17',
              style: TextStyle(
                fontFamily: 'DSEG7ClassicMini',
                fontSize: 13,
                height: 1,
                letterSpacing: 1.4,
                color: Color(0xffff9414),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPhotoCard extends StatelessWidget {
  const _MiniPhotoCard({required this.scale, required this.opacity});

  final double scale;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.66 * scale,
      heightFactor: 0.72 * scale,
      child: Opacity(
        opacity: opacity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xffd8e8df),
            borderRadius: BorderRadius.circular(34),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff456253).withValues(alpha: 0.13),
                blurRadius: 34,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const _SampleFilmFrame(),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      '26 6 17',
                      style: TextStyle(
                        fontFamily: 'DSEG7ClassicMini',
                        fontSize: 28 * scale,
                        height: 1,
                        letterSpacing: 2,
                        color: const Color(0xffff9b16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryPickButton extends StatelessWidget {
  const _PrimaryPickButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff4f7d5d).withValues(alpha: 0.94),
        foregroundColor: const Color(0xfffff6da),
        minimumSize: const Size.fromHeight(56),
        shape: const StadiumBorder(),
        elevation: 0,
      ),
      onPressed: onTap,
      icon: const Icon(Icons.add_photo_alternate_outlined),
      label: const Text(
        '\u9009\u62e9\u7167\u7247',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    );
  }
}

class _HomeFootnote extends StatelessWidget {
  const _HomeFootnote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      '\u8fdb\u5165\u7f16\u8f91\u540e\u53ef\u8c03\u6574\u5927\u5c0f\u3001\u900f\u660e\u5ea6\u3001\u6837\u5f0f\u548c\u4f4d\u7f6e',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(0xff718071),
        fontSize: 12,
        height: 1.35,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _EditorFloatingBar extends StatelessWidget {
  const _EditorFloatingBar({
    required this.isExporting,
    required this.onBack,
    required this.onExport,
  });

  final bool isExporting;
  final VoidCallback onBack;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _GlassCircleButton(
          icon: Icons.arrow_back,
          tooltip: '返回',
          onTap: onBack,
        ),
        const Spacer(),
        _GlassPillButton(
          isBusy: isExporting,
          onTap: isExporting ? null : onExport,
        ),
      ],
    );
  }
}

class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: InkWell(
            onTap: onTap,
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xff102018).withValues(alpha: 0.34),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.22),
                  width: 0.8,
                ),
              ),
              child: Icon(icon, color: const Color(0xfffff6da), size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPillButton extends StatelessWidget {
  const _GlassPillButton({required this.isBusy, required this.onTap});

  final bool isBusy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xff527d63).withValues(alpha: 0.88),
            foregroundColor: const Color(0xfffff6da),
            disabledBackgroundColor: const Color(
              0xff527d63,
            ).withValues(alpha: 0.48),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: onTap,
          child: isBusy
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ),
    );
  }
}

class _FullScreenPhotoCanvas extends StatelessWidget {
  const _FullScreenPhotoCanvas({
    required this.imageBytes,
    required this.imageSize,
    required this.watermarkScale,
    required this.watermarkOpacity,
    required this.watermarkAnchor,
    required this.watermarkTone,
    required this.showWatermark,
    required this.dateText,
    required this.timeText,
  });

  final Uint8List imageBytes;
  final Size imageSize;
  final double watermarkScale;
  final double watermarkOpacity;
  final WatermarkAnchor watermarkAnchor;
  final WatermarkTone watermarkTone;
  final bool showWatermark;
  final String dateText;
  final String timeText;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasSize = Size(constraints.maxWidth, constraints.maxHeight);
        final fittedSize = applyBoxFit(
          BoxFit.contain,
          imageSize,
          canvasSize,
        ).destination;
        final displayScale = fittedSize.width / imageSize.width;
        final layout = _watermarkLayout(
          imageSize: imageSize,
          displayScale: displayScale,
          watermarkScale: watermarkScale,
          anchor: watermarkAnchor,
          dateText: dateText,
          timeText: timeText,
        );
        final imageLeft = (canvasSize.width - fittedSize.width) / 2;
        final imageTop = (canvasSize.height - fittedSize.height) / 2;

        return Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Image.memory(
                imageBytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.22),
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.34),
                  ],
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                boundaryMargin: EdgeInsets.zero,
                child: Stack(
                  children: [
                    Positioned(
                      left: imageLeft,
                      top: imageTop,
                      width: fittedSize.width,
                      height: fittedSize.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            imageBytes,
                            fit: BoxFit.fill,
                            gaplessPlayback: true,
                          ),
                          if (showWatermark)
                            Positioned(
                              left: layout.left,
                              top: layout.top,
                              child: SizedBox(
                                width: layout.blockWidth,
                                height: layout.blockHeight,
                                child: Align(
                                  alignment: watermarkAnchor.isRight
                                      ? Alignment.topRight
                                      : Alignment.topLeft,
                                  child: _DigitalTimestamp(
                                    dateText: dateText,
                                    timeText: timeText,
                                    layout: layout,
                                    opacity: watermarkOpacity,
                                    alignRight: watermarkAnchor.isRight,
                                    tone: watermarkTone,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _EditorTool {
  size(Icons.straighten, '大小'),
  style(Icons.palette_outlined, '样式'),
  position(Icons.open_with, '位置'),
  date(Icons.calendar_month_outlined, '日期');

  const _EditorTool(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _EditorToolDock extends StatelessWidget {
  const _EditorToolDock({
    required this.activeTool,
    required this.sourceName,
    required this.savedPath,
    required this.includeTime,
    required this.watermarkTone,
    required this.dateFormatPreset,
    required this.watermarkScale,
    required this.watermarkOpacity,
    required this.watermarkAnchor,
    required this.isExporting,
    required this.dateController,
    required this.timeController,
    required this.onToolChanged,
    required this.onChanged,
    required this.onIncludeTimeChanged,
    required this.onWatermarkToneChanged,
    required this.onDateFormatChanged,
    required this.onWatermarkScaleChanged,
    required this.onWatermarkOpacityChanged,
    required this.onWatermarkAnchorChanged,
    required this.onPickImage,
    required this.onExport,
    required this.onShare,
  });

  final _EditorTool activeTool;
  final String? sourceName;
  final String? savedPath;
  final bool includeTime;
  final WatermarkTone watermarkTone;
  final DateFormatPreset dateFormatPreset;
  final double watermarkScale;
  final double watermarkOpacity;
  final WatermarkAnchor watermarkAnchor;
  final bool isExporting;
  final TextEditingController dateController;
  final TextEditingController timeController;
  final ValueChanged<_EditorTool> onToolChanged;
  final VoidCallback onChanged;
  final ValueChanged<bool> onIncludeTimeChanged;
  final ValueChanged<WatermarkTone> onWatermarkToneChanged;
  final ValueChanged<DateFormatPreset> onDateFormatChanged;
  final ValueChanged<double> onWatermarkScaleChanged;
  final ValueChanged<double> onWatermarkOpacityChanged;
  final ValueChanged<WatermarkAnchor> onWatermarkAnchorChanged;
  final VoidCallback onPickImage;
  final VoidCallback? onExport;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, math.max(10, bottomInset + 6)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolContextSurface(child: _activeContent(context)),
          const SizedBox(height: 8),
          _ToolRail(
            activeTool: activeTool,
            onToolChanged: onToolChanged,
            onPickImage: onPickImage,
            onExport: onExport,
            isExporting: isExporting,
          ),
        ],
      ),
    );
  }

  Widget _activeContent(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: switch (activeTool) {
        _EditorTool.size => _SizeToolContent(
            key: const ValueKey('size'),
            scale: watermarkScale,
            opacity: watermarkOpacity,
            onScaleChanged: onWatermarkScaleChanged,
            onOpacityChanged: onWatermarkOpacityChanged,
          ),
        _EditorTool.style => _StyleToolContent(
            key: const ValueKey('style'),
            tone: watermarkTone,
            includeTime: includeTime,
            onToneChanged: onWatermarkToneChanged,
            onIncludeTimeChanged: onIncludeTimeChanged,
          ),
        _EditorTool.position => _PositionToolContent(
            key: const ValueKey('position'),
            anchor: watermarkAnchor,
            onAnchorChanged: onWatermarkAnchorChanged,
          ),
        _EditorTool.date => _DateToolContent(
            key: const ValueKey('date'),
            includeTime: includeTime,
            dateFormatPreset: dateFormatPreset,
            dateController: dateController,
            timeController: timeController,
            onChanged: onChanged,
            onIncludeTimeChanged: onIncludeTimeChanged,
            onDateFormatChanged: onDateFormatChanged,
          ),
      },
    );
  }
}

class _ToolContextSurface extends StatelessWidget {
  const _ToolContextSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xffe8f2e7).withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.30),
              width: 0.8,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ToolRail extends StatelessWidget {
  const _ToolRail({
    required this.activeTool,
    required this.onToolChanged,
    required this.onPickImage,
    required this.onExport,
    required this.isExporting,
  });

  final _EditorTool activeTool;
  final ValueChanged<_EditorTool> onToolChanged;
  final VoidCallback onPickImage;
  final VoidCallback? onExport;
  final bool isExporting;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff122016).withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: SizedBox(
            height: 76,
            child: Row(
              children: [
                const SizedBox(width: 8),
                _ToolRailButton(
                  icon: Icons.photo_library_outlined,
                  label: '更换',
                  selected: false,
                  onTap: onPickImage,
                ),
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    children: [
                      for (final tool in _EditorTool.values)
                        _ToolRailButton(
                          icon: tool.icon,
                          label: tool.label,
                          selected: activeTool == tool,
                          onTap: () => onToolChanged(tool),
                        ),
                    ],
                  ),
                ),
                _ToolRailButton(
                  icon: isExporting ? Icons.hourglass_top : Icons.check,
                  label: '保存',
                  selected: true,
                  onTap: isExporting ? null : onExport,
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolRailButton extends StatelessWidget {
  const _ToolRailButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fill = selected
        ? const Color(0xff83b58d).withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.08);
    final color = selected
        ? const Color(0xff102018)
        : const Color(0xffedf7e9).withValues(alpha: enabled ? 0.92 : 0.42);
    return Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 58,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xffb8d7b7)
                  : Colors.white.withValues(alpha: 0.10),
              width: 0.8,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 21, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SizeToolContent extends StatelessWidget {
  const _SizeToolContent({
    super.key,
    required this.scale,
    required this.opacity,
    required this.onScaleChanged,
    required this.onOpacityChanged,
  });

  final double scale;
  final double opacity;
  final ValueChanged<double> onScaleChanged;
  final ValueChanged<double> onOpacityChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SoftSlider(
          label: '大小',
          value: scale,
          min: 0.18,
          max: 2.8,
          divisions: 52,
          displayValue: '${(scale * 100).round()}%',
          onChanged: onScaleChanged,
        ),
        _SoftSlider(
          label: '透明',
          value: opacity,
          min: 0.02,
          max: 1.0,
          divisions: 49,
          displayValue: '${(opacity * 100).round()}%',
          onChanged: onOpacityChanged,
        ),
      ],
    );
  }
}

class _StyleToolContent extends StatelessWidget {
  const _StyleToolContent({
    super.key,
    required this.tone,
    required this.includeTime,
    required this.onToneChanged,
    required this.onIncludeTimeChanged,
  });

  final WatermarkTone tone;
  final bool includeTime;
  final ValueChanged<WatermarkTone> onToneChanged;
  final ValueChanged<bool> onIncludeTimeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in WatermarkTone.values)
                _SoftChip(
                  text: item.label,
                  selected: item == tone,
                  tone: item == WatermarkTone.white
                      ? _ChipTone.blue
                      : _ChipTone.amber,
                  onTap: () => onToneChanged(item),
                ),
              _SoftChip(
                text: includeTime ? '显示时间' : '隐藏时间',
                selected: includeTime,
                tone: _ChipTone.blue,
                onTap: () => onIncludeTimeChanged(!includeTime),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PositionToolContent extends StatelessWidget {
  const _PositionToolContent({
    super.key,
    required this.anchor,
    required this.onAnchorChanged,
  });

  final WatermarkAnchor anchor;
  final ValueChanged<WatermarkAnchor> onAnchorChanged;

  @override
  Widget build(BuildContext context) {
    return _AnchorGrid(selected: anchor, onChanged: onAnchorChanged);
  }
}

class _DateToolContent extends StatelessWidget {
  const _DateToolContent({
    super.key,
    required this.includeTime,
    required this.dateFormatPreset,
    required this.dateController,
    required this.timeController,
    required this.onChanged,
    required this.onIncludeTimeChanged,
    required this.onDateFormatChanged,
  });

  final bool includeTime;
  final DateFormatPreset dateFormatPreset;
  final TextEditingController dateController;
  final TextEditingController timeController;
  final VoidCallback onChanged;
  final ValueChanged<bool> onIncludeTimeChanged;
  final ValueChanged<DateFormatPreset> onDateFormatChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: dateController,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: '日期',
                  prefixIcon: Icon(Icons.text_fields, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: timeController,
                enabled: includeTime,
                onChanged: (_) => onChanged(),
                decoration: const InputDecoration(
                  labelText: '时间',
                  prefixIcon: Icon(Icons.schedule, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SoftToggle(
              value: includeTime,
              onChanged: onIncludeTimeChanged,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _DateFormatControl(
          preset: dateFormatPreset,
          onTap: () => onDateFormatChanged(dateFormatPreset.next),
        ),
      ],
    );
  }
}

class _SampleFilmFrame extends StatelessWidget {
  const _SampleFilmFrame();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SampleFilmPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _SampleFilmPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final skyRect = Offset.zero & size;
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xff8ebee8),
          Color(0xffd9dff0),
          Color(0xfff4cfc8),
          Color(0xff184468),
        ],
        stops: [0, 0.44, 0.66, 1],
      ).createShader(skyRect);
    canvas.drawRect(skyRect, sky);

    _drawCloudWash(canvas, size);
    _drawMountain(canvas, size, reflected: false);
    _drawShore(canvas, size);
    _drawLake(canvas, size);
    _drawMountain(canvas, size, reflected: true);
    _drawLights(canvas, size);
    _drawSakura(canvas, size);
    _drawFilmGrain(canvas, size);
  }

  void _drawCloudWash(Canvas canvas, Size size) {
    final cloud = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.42),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.18, size.height * 0.18),
              radius: size.width * 0.55,
            ),
          );
    canvas.drawOval(
      Rect.fromLTWH(
        -size.width * 0.2,
        size.height * 0.02,
        size.width * 0.85,
        size.height * 0.32,
      ),
      cloud,
    );
  }

  void _drawMountain(Canvas canvas, Size size, {required bool reflected}) {
    final horizon = size.height * 0.58;
    final peak = reflected ? size.height * 0.82 : size.height * 0.26;
    final baseY = reflected ? size.height * 0.62 : horizon;
    final left = size.width * 0.15;
    final right = size.width * 0.78;
    final center = size.width * 0.47;

    final body = Path()
      ..moveTo(left, baseY)
      ..lineTo(center, peak)
      ..lineTo(right, baseY)
      ..close();
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: reflected ? Alignment.bottomCenter : Alignment.topCenter,
        end: reflected ? Alignment.topCenter : Alignment.bottomCenter,
        colors: reflected
            ? [
                const Color(0xffd7e3f2).withValues(alpha: 0.38),
                const Color(0xff365a82).withValues(alpha: 0.18),
              ]
            : [
                const Color(0xffffffff),
                const Color(0xffdbe8f2),
                const Color(0xff426b94),
              ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(body, bodyPaint);

    final shade = Path()
      ..moveTo(center, peak)
      ..lineTo(right, baseY)
      ..lineTo(center * 1.03, baseY)
      ..close();
    canvas.drawPath(
      shade,
      Paint()
        ..color =
            (reflected ? const Color(0xff44678b) : const Color(0xff517aa2))
                .withValues(alpha: reflected ? 0.12 : 0.32),
    );

    if (!reflected) {
      final snow = Path()
        ..moveTo(center, peak)
        ..lineTo(center - size.width * 0.055, size.height * 0.41)
        ..lineTo(center - size.width * 0.015, size.height * 0.37)
        ..lineTo(center + size.width * 0.025, size.height * 0.45)
        ..lineTo(center + size.width * 0.07, size.height * 0.39)
        ..close();
      canvas.drawPath(
        snow,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }

  void _drawShore(Canvas canvas, Size size) {
    final shore = Paint()
      ..color = const Color(0xff173753).withValues(alpha: 0.88);
    final path = Path()
      ..moveTo(0, size.height * 0.59)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.56,
        size.width,
        size.height * 0.59,
      )
      ..lineTo(size.width, size.height * 0.65)
      ..lineTo(0, size.height * 0.66)
      ..close();
    canvas.drawPath(path, shore);
  }

  void _drawLake(Canvas canvas, Size size) {
    final lake = Paint()
      ..shader =
          const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xff245176), Color(0xff0e2d4d)],
          ).createShader(
            Rect.fromLTWH(0, size.height * 0.62, size.width, size.height),
          );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height * 0.62, size.width, size.height * 0.38),
      lake,
    );

    final ripple = Paint()
      ..color = Colors.white.withValues(alpha: 0.11)
      ..strokeWidth = 1;
    for (var i = 0; i < 18; i++) {
      final y = size.height * (0.66 + i * 0.018);
      canvas.drawLine(
        Offset(size.width * 0.08, y),
        Offset(size.width * (0.85 + 0.08 * math.sin(i)), y),
        ripple,
      );
    }
  }

  void _drawLights(Canvas canvas, Size size) {
    for (var i = 0; i < 18; i++) {
      final x = size.width * (0.08 + i * 0.048);
      final y = size.height * (0.605 + 0.012 * math.sin(i * 1.7));
      final light = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xffffc15b).withValues(alpha: 0.9),
            const Color(0xffffc15b).withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: 7));
      canvas.drawCircle(Offset(x, y), 7, light);
    }
  }

  void _drawSakura(Canvas canvas, Size size) {
    final branch = Paint()
      ..color = const Color(0xff36272d).withValues(alpha: 0.78)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final start = Offset(size.width * 0.76, size.height * 0.08);
    final end = Offset(size.width * 0.98, size.height * 0.43);
    canvas.drawLine(start, end, branch);
    for (var i = 0; i < 22; i++) {
      final t = i / 22;
      final x = size.width * (0.74 + 0.24 * t + 0.035 * math.sin(i));
      final y = size.height * (0.1 + 0.32 * t + 0.025 * math.cos(i * 1.3));
      _drawBlossom(canvas, Offset(x, y), 3.0 + (i % 3));
    }
  }

  void _drawBlossom(Canvas canvas, Offset center, double radius) {
    final petal = Paint()
      ..color = const Color(0xffffbfd0).withValues(alpha: 0.86);
    for (var i = 0; i < 5; i++) {
      final angle = i * math.pi * 2 / 5;
      canvas.drawCircle(
        center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.7,
        radius * 0.55,
        petal,
      );
    }
    canvas.drawCircle(
      center,
      radius * 0.35,
      Paint()..color = const Color(0xfff39aa9).withValues(alpha: 0.88),
    );
  }

  void _drawFilmGrain(Canvas canvas, Size size) {
    final grain = Paint()..color = Colors.white.withValues(alpha: 0.028);
    final darkGrain = Paint()..color = Colors.black.withValues(alpha: 0.018);
    for (var i = 0; i < 520; i++) {
      final x = (i * 73 % 997) / 997 * size.width;
      final y = (i * 37 % 733) / 733 * size.height;
      canvas.drawCircle(
        Offset(x, y),
        0.45 + (i % 3) * 0.18,
        i.isEven ? grain : darkGrain,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DigitalTimestamp extends StatelessWidget {
  const _DigitalTimestamp({
    required this.dateText,
    required this.timeText,
    required this.layout,
    required this.opacity,
    required this.alignRight,
    required this.tone,
  });

  final String dateText;
  final String timeText;
  final WatermarkLayout layout;
  final double opacity;
  final bool alignRight;
  final WatermarkTone tone;

  @override
  Widget build(BuildContext context) {
    final date = _cleanDigitalText(
      dateText.isEmpty ? _defaultFilmDate(DateTime.now()) : dateText,
    );
    final time = _cleanDigitalText(timeText);

    return Column(
      crossAxisAlignment: alignRight
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _DsegText(
          text: date,
          fontSize: layout.dateFontSize,
          letterSpacing: layout.dateLetterSpacing,
          opacity: opacity,
          tone: tone,
        ),
        if (time.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: layout.gap),
            child: _DsegText(
              text: time,
              fontSize: layout.timeFontSize,
              letterSpacing: layout.timeLetterSpacing,
              opacity: opacity * 0.72,
              tone: tone,
            ),
          ),
      ],
    );
  }
}

class _DsegText extends StatelessWidget {
  const _DsegText({
    required this.text,
    required this.fontSize,
    required this.letterSpacing,
    required this.opacity,
    required this.tone,
  });

  final String text;
  final double fontSize;
  final double letterSpacing;
  final double opacity;
  final WatermarkTone tone;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Text(
          text,
          style: TextStyle(
            fontFamily: 'DSEG7ClassicMini',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: letterSpacing,
            height: 1,
            color: tone.shadow.withValues(alpha: opacity * 0.72),
          ),
        ),
        Text(
          text,
          style: TextStyle(
            fontFamily: 'DSEG7ClassicMini',
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: letterSpacing,
            height: 1,
            foreground: Paint()
              ..shader =
                  LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [tone.top, tone.bottom],
                  ).createShader(
                    Rect.fromLTWH(0, 0, fontSize * text.length, fontSize),
                  ),
          ),
        ),
      ],
    );
  }
}

enum _ChipTone { amber, blue }

class _SoftChip extends StatelessWidget {
  const _SoftChip({
    required this.text,
    required this.selected,
    required this.tone,
    required this.onTap,
  });

  final String text;
  final bool selected;
  final _ChipTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedFill = tone == _ChipTone.amber
        ? const Color(0xffffb14a)
        : const Color(0xff89b6c4);
    final textColor = selected
        ? const Color(0xff173827)
        : const Color(0xff42634b);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? selectedFill.withValues(alpha: 0.76)
              : const Color(0xffdceadf).withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? selectedFill : const Color(0xffa8c0ac),
            width: selected ? 1.1 : 0.7,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _DateFormatControl extends StatelessWidget {
  const _DateFormatControl({required this.preset, required this.onTap});

  final DateFormatPreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '切换日期格式',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xffdceadf).withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xffa8c0ac), width: 0.7),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 7, 9, 7),
            child: Row(
              children: [
                const Icon(
                  Icons.calendar_month_outlined,
                  size: 18,
                  color: Color(0xff55735f),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '日期格式',
                        style: TextStyle(
                          color: Color(0xff66806c),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preset.example,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff263f30),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.swap_horiz,
                  size: 19,
                  color: Color(0xff54725f),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _AnchorGrid extends StatelessWidget {
  const _AnchorGrid({required this.selected, required this.onChanged});

  final WatermarkAnchor selected;
  final ValueChanged<WatermarkAnchor> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffdcebdc).withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xffaac4a7), width: 0.7),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _AnchorCell(
                    anchor: WatermarkAnchor.topLeft,
                    selected: selected == WatermarkAnchor.topLeft,
                    onTap: onChanged,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _AnchorCell(
                    anchor: WatermarkAnchor.topRight,
                    selected: selected == WatermarkAnchor.topRight,
                    onTap: onChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _AnchorCell(
                    anchor: WatermarkAnchor.bottomLeft,
                    selected: selected == WatermarkAnchor.bottomLeft,
                    onTap: onChanged,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _AnchorCell(
                    anchor: WatermarkAnchor.bottomRight,
                    selected: selected == WatermarkAnchor.bottomRight,
                    onTap: onChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AnchorCell extends StatelessWidget {
  const _AnchorCell({
    required this.anchor,
    required this.selected,
    required this.onTap,
  });

  final WatermarkAnchor anchor;
  final bool selected;
  final ValueChanged<WatermarkAnchor> onTap;

  @override
  Widget build(BuildContext context) {
    final fill = selected ? const Color(0xff82b890) : const Color(0xffd5e6d5);
    final textColor = selected
        ? const Color(0xff123f2d)
        : const Color(0xff466b4d);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => onTap(anchor),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xff477f58) : const Color(0xff9ec09b),
            width: selected ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(anchor.icon, size: 16, color: textColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                anchor.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftToggle extends StatelessWidget {
  const _SoftToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final fill = value ? const Color(0xff8fc5a4) : const Color(0xffd3e8d5);
    final stroke = value ? const Color(0xff4f9471) : const Color(0xff8fb587);
    final thumb = value ? const Color(0xffffc96f) : const Color(0xff6f9865);
    final iconColor = value ? const Color(0xff315f49) : const Color(0xffeef8df);

    return Tooltip(
      message: value ? '隐藏时间' : '显示时间',
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: 58,
          height: 34,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: stroke, width: 1),
            boxShadow: [
              BoxShadow(
                color: const Color(0xff66836d).withValues(alpha: 0.12),
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: thumb,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xff355d47).withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                value ? Icons.schedule : Icons.schedule_outlined,
                size: 15,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftSlider extends StatelessWidget {
  const _SoftSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xff35573b),
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              displayValue,
              style: const TextStyle(color: Color(0xff5c775f), fontSize: 12),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: const Color(0xff496f4f),
            inactiveTrackColor: const Color(0xffb6cbb1),
            thumbColor: const Color(0xff294c33),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

enum ExportPreset {
  png;

  String get extension => 'png';

  String get mimeType => 'image/png';
}

enum DateFormatPreset {
  yySpaced,
  yyDot,
  yyyyDot,
  mmDdYy,
  ddMmYy;

  String get example => format(DateTime(2026, 6, 17));

  String format(DateTime date) => switch (this) {
    DateFormatPreset.yySpaced =>
      '${DateFormat('yy').format(date)} ${date.month} ${date.day}',
    DateFormatPreset.yyDot => DateFormat('yy.MM.dd').format(date),
    DateFormatPreset.yyyyDot => DateFormat('yyyy.MM.dd').format(date),
    DateFormatPreset.mmDdYy =>
      '${date.month} ${date.day} ${DateFormat('yy').format(date)}',
    DateFormatPreset.ddMmYy =>
      '${date.day} ${date.month} ${DateFormat('yy').format(date)}',
  };

  DateFormatPreset get next {
    final values = DateFormatPreset.values;
    return values[(index + 1) % values.length];
  }
}

enum WatermarkTone {
  amber,
  honey,
  redOrange,
  paleGold,
  white;

  String get label => switch (this) {
    WatermarkTone.amber => '琥珀数码',
    WatermarkTone.honey => '蜜黄胶片',
    WatermarkTone.redOrange => '橙红日期',
    WatermarkTone.paleGold => '淡金旧照',
    WatermarkTone.white => '白色数码',
  };

  Color get top => switch (this) {
    WatermarkTone.amber => const Color(0xffffb12a),
    WatermarkTone.honey => const Color(0xffffc85d),
    WatermarkTone.redOrange => const Color(0xffff9a31),
    WatermarkTone.paleGold => const Color(0xffffd986),
    WatermarkTone.white => const Color(0xffffffff),
  };

  Color get bottom => switch (this) {
    WatermarkTone.amber => const Color(0xffff8d0c),
    WatermarkTone.honey => const Color(0xffffa424),
    WatermarkTone.redOrange => const Color(0xffff681f),
    WatermarkTone.paleGold => const Color(0xffffb94f),
    WatermarkTone.white => const Color(0xffe7ece8),
  };

  Color get shadow => switch (this) {
    WatermarkTone.amber => const Color(0xffa64f05),
    WatermarkTone.honey => const Color(0xffa45e08),
    WatermarkTone.redOrange => const Color(0xff9d3608),
    WatermarkTone.paleGold => const Color(0xff9e721d),
    WatermarkTone.white => const Color(0xff9aa39a),
  };

  WatermarkTone get next {
    final values = WatermarkTone.values;
    return values[(index + 1) % values.length];
  }
}

enum WatermarkAnchor {
  bottomRight,
  bottomLeft,
  topRight,
  topLeft;

  String get label => switch (this) {
    WatermarkAnchor.bottomRight => '右下',
    WatermarkAnchor.bottomLeft => '左下',
    WatermarkAnchor.topRight => '右上',
    WatermarkAnchor.topLeft => '左上',
  };

  IconData get icon => switch (this) {
    WatermarkAnchor.bottomRight => Icons.south_east,
    WatermarkAnchor.bottomLeft => Icons.south_west,
    WatermarkAnchor.topRight => Icons.north_east,
    WatermarkAnchor.topLeft => Icons.north_west,
  };

  bool get isRight =>
      this == WatermarkAnchor.bottomRight || this == WatermarkAnchor.topRight;

  bool get isTop =>
      this == WatermarkAnchor.topRight || this == WatermarkAnchor.topLeft;

  Alignment get alignment => switch (this) {
    WatermarkAnchor.bottomRight => Alignment.bottomRight,
    WatermarkAnchor.bottomLeft => Alignment.bottomLeft,
    WatermarkAnchor.topRight => Alignment.topRight,
    WatermarkAnchor.topLeft => Alignment.topLeft,
  };
}

class WatermarkJob {
  const WatermarkJob({
    required this.bytes,
    required this.dateText,
    required this.timeText,
    required this.exportPreset,
    required this.watermarkTone,
    required this.watermarkScale,
    required this.watermarkOpacity,
    required this.watermarkAnchor,
  });

  final Uint8List bytes;
  final String dateText;
  final String timeText;
  final ExportPreset exportPreset;
  final WatermarkTone watermarkTone;
  final double watermarkScale;
  final double watermarkOpacity;
  final WatermarkAnchor watermarkAnchor;
}

class WatermarkLayout {
  const WatermarkLayout({
    required this.left,
    required this.top,
    required this.blockWidth,
    required this.blockHeight,
    required this.dateFontSize,
    required this.timeFontSize,
    required this.dateLetterSpacing,
    required this.timeLetterSpacing,
    required this.gap,
  });

  final double left;
  final double top;
  final double blockWidth;
  final double blockHeight;
  final double dateFontSize;
  final double timeFontSize;
  final double dateLetterSpacing;
  final double timeLetterSpacing;
  final double gap;
}

class PickedImageData {
  const PickedImageData({
    required this.bytes,
    required this.name,
    required this.size,
    required this.shotTime,
  });

  final Uint8List bytes;
  final String name;
  final Size size;
  final DateTime? shotTime;
}

Future<PickedImageData?> _pickImageData(
  ImagePicker picker,
  BuildContext context,
) async {
  final XFile? file;
  if (Platform.isAndroid || Platform.isIOS) {
    file = await picker.pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: true,
    );
  } else {
    file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Photos',
          extensions: ['jpg', 'jpeg', 'png', 'heic', 'webp'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
        ),
      ],
    );
  }

  if (file == null) {
    return null;
  }

  try {
    final bytes = await file.readAsBytes();
    return PickedImageData(
      bytes: bytes,
      name: file.name,
      size: await _readImageSize(bytes),
      shotTime: _readShotTime(bytes),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法读取图片，请换一张常见格式图片：$error')));
    }
    return null;
  }
}

String _defaultFilmDate(DateTime date) {
  return DateFormatPreset.yySpaced.format(date);
}

Future<Size> _readImageSize(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final width = image.width;
  final height = image.height;
  image.dispose();
  if (width <= 0 || height <= 0) {
    throw StateError('图片尺寸异常');
  }
  return Size(width.toDouble(), height.toDouble());
}

DateTime? _readShotTime(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    final exif = decoded?.exif;
    if (exif == null) {
      return null;
    }

    for (final value in [
      exif.exifIfd['DateTimeOriginal'],
      exif.exifIfd['DateTimeDigitized'],
      exif.imageIfd['DateTime'],
    ]) {
      final parsed = _parseExifDate(value?.toString());
      if (parsed != null) {
        return parsed;
      }
    }
  } catch (_) {
    return null;
  }
  return null;
}

DateTime? _parseExifDate(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  final match = RegExp(
    r'(\d{4})[:/-](\d{2})[:/-](\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
}

WatermarkLayout _watermarkLayout({
  required Size imageSize,
  required double displayScale,
  required double watermarkScale,
  required WatermarkAnchor anchor,
  required String dateText,
  required String timeText,
}) {
  final cleanDate = _cleanDigitalText(
    dateText.isEmpty ? _defaultFilmDate(DateTime.now()) : dateText,
  );
  final cleanTime = _cleanDigitalText(timeText);
  final baseScale =
      math.max(1.0, math.min(imageSize.width, imageSize.height) / 980) *
      watermarkScale.clamp(0.3, 2.6) *
      displayScale;
  final dateFontSize = 21.0 * baseScale;
  final timeFontSize = 13.0 * baseScale;
  final dateLetterSpacing = 2.4 * baseScale;
  final timeLetterSpacing = 2.0 * baseScale;
  final datePainter = _measureDsegText(
    cleanDate,
    dateFontSize,
    dateLetterSpacing,
  );
  final timePainter = cleanTime.isEmpty
      ? null
      : _measureDsegText(cleanTime, timeFontSize, timeLetterSpacing);
  final gap = 8.0 * baseScale;
  final blockWidth = math
      .max(datePainter.width, timePainter == null ? 0 : timePainter.width)
      .toDouble();
  final blockHeight =
      datePainter.height + (timePainter == null ? 0 : timePainter.height + gap);
  final margin =
      math.min(imageSize.width, imageSize.height) * 0.046 * displayScale;
  final displayWidth = imageSize.width * displayScale;
  final displayHeight = imageSize.height * displayScale;
  final left = anchor.isRight ? displayWidth - margin - blockWidth : margin;
  final top = anchor.isTop ? margin : displayHeight - margin - blockHeight;

  return WatermarkLayout(
    left: left,
    top: top,
    blockWidth: blockWidth,
    blockHeight: blockHeight,
    dateFontSize: dateFontSize,
    timeFontSize: timeFontSize,
    dateLetterSpacing: dateLetterSpacing,
    timeLetterSpacing: timeLetterSpacing,
    gap: gap,
  );
}

TextPainter _measureDsegText(
  String text,
  double fontSize,
  double letterSpacing,
) {
  return TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'DSEG7ClassicMini',
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
        height: 1,
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
}

Future<Uint8List> _renderWatermarkedImage(WatermarkJob job) async {
  final codec = await ui.instantiateImageCodec(job.bytes);
  final frame = await codec.getNextFrame();
  final source = frame.image;
  final width = source.width;
  final height = source.height;
  final date = job.dateText.isEmpty
      ? _defaultFilmDate(DateTime.now())
      : job.dateText;
  final cleanDate = _cleanDigitalText(date);
  final cleanTime = _cleanDigitalText(job.timeText);
  final layout = _watermarkLayout(
    imageSize: Size(width.toDouble(), height.toDouble()),
    displayScale: 1,
    watermarkScale: job.watermarkScale,
    anchor: job.watermarkAnchor,
    dateText: date,
    timeText: job.timeText,
  );
  final datePainter = _buildExportTextPainter(
    cleanDate,
    layout.dateFontSize,
    job.watermarkOpacity,
    layout.dateLetterSpacing,
    job.watermarkTone,
  );
  final timePainter = cleanTime.isEmpty
      ? null
      : _buildExportTextPainter(
          cleanTime,
          layout.timeFontSize,
          job.watermarkOpacity * 0.72,
          layout.timeLetterSpacing,
          job.watermarkTone,
        );

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImage(source, Offset.zero, Paint());

  final dateOffset = Offset(
    job.watermarkAnchor.isRight
        ? layout.left + layout.blockWidth - datePainter.width
        : layout.left,
    layout.top,
  );
  datePainter.paint(canvas, dateOffset);

  if (timePainter != null) {
    timePainter.paint(
      canvas,
      Offset(
        job.watermarkAnchor.isRight
            ? layout.left + layout.blockWidth - timePainter.width
            : layout.left,
        dateOffset.dy + datePainter.height + layout.gap,
      ),
    );
  }

  final rendered = await recorder.endRecording().toImage(width, height);
  source.dispose();
  final byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  if (byteData == null) {
    throw StateError('无法导出图片');
  }
  return byteData.buffer.asUint8List();
}

TextPainter _buildExportTextPainter(
  String text,
  double fontSize,
  double opacity,
  double letterSpacing,
  WatermarkTone tone,
) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'DSEG7ClassicMini',
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: letterSpacing,
        height: 1,
        foreground: Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, fontSize), [
            tone.top.withValues(alpha: opacity),
            tone.bottom.withValues(alpha: opacity),
          ]),
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  return painter;
}

String _cleanDigitalText(String text) {
  return text.replaceAll(RegExp(r'[^0-9 .:-]'), '');
}
